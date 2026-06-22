# Architecture

## Goals
- Centralized **metrics, logs, and traces** for AKS workloads and the
  underlying Azure infrastructure.
- Vendor-neutral instrumentation via **OpenTelemetry**.
- Operate every layer through code — no portal clicks.

## High-level topology

```
                ┌─────────────────────────────────────────────┐
                │                Azure subscription           │
                │                                             │
                │   ┌──────────┐    ┌──────────────────────┐  │
                │   │   ACR    │◀──▶│  Azure Container Reg │  │
                │   └──────────┘    └──────────────────────┘  │
                │                                             │
                │   ┌──────────────┐  ┌─────────────────────┐ │
                │   │  Key Vault   │  │ Log Analytics WS    │ │
                │   │ (secrets via │  │ (Container Insights │ │
                │   │   CSI)       │  │  + AKS control      │ │
                │   └──────────────┘  │  plane logs)        │ │
                │                     └──────────┬──────────┘ │
                │                                │            │
                │     ┌─────────────────┐        │            │
                │     │ Azure Monitor   │◀───────┘            │
                │     │  Workspace      │                     │
                │     │ (managed Prom)  │                     │
                │     └────────┬────────┘                     │
                │              │                              │
                │   ┌──────────▼─────────┐                    │
                │   │       AKS          │                    │
                │   │  (3 node pools:    │                    │
                │   │  system / user /   │                    │
                │   │  observability)    │                    │
                │   └──────────┬─────────┘                    │
                └──────────────┼─────────────────────────────-┘
                               │
   ┌───────────────────────────┴──────────────────────────────┐
   │                  In-cluster (AKS)                        │
   │                                                          │
   │  apps (auto-instrumented)                                │
   │      │  OTLP                                             │
   │      ▼                                                   │
   │  ┌──────────────────────────┐                            │
   │  │ OTel Collector (gateway) │   DaemonSet sidecar        │
   │  │ otlp / hostmetrics /     │   ┌───────────────────┐    │
   │  │ k8s_cluster / prometheus │   │ OTel Collector    │    │
   │  └────┬──────────┬──────────┘   │ (node: filelog +  │    │
   │       │          │              │  kubeletstats →   │    │
   │  metrics       traces           │  OTLP → gateway)  │    │
   │       │          │              └───────────────────┘    │
   │       ▼          ▼                                       │
   │  ┌──────────┐  ┌────────┐                                │
   │  │Prometheus│  │ Tempo  │                                │
   │  └────┬─────┘  └───┬────┘                                │
   │       │            │                                     │
   │       │            │                                     │
   │       ▼            ▼                                     │
   │  ┌──────────────────────────┐    ┌─────────────────────┐ │
   │  │         Grafana          │◀──▶│    Alertmanager     │ │
   │  │ (datasources: Prom/Loki/ │    │  webhook / email    │ │
   │  │  Tempo)                  │    │  PagerDuty / Slack  │ │
   │  └──────────────────────────┘    └─────────────────────┘ │
   │                                                          │
   │  Logs ─────────► Loki  (in-cluster) ─────► Grafana       │
   │  All signals ──► Azure Monitor (longer retention)        │
   └──────────────────────────────────────────────────────────┘
```

## Why three signals through one collector?

| Signal  | Source                                     | In-cluster sink | Long-term sink   |
|---------|--------------------------------------------|-----------------|------------------|
| Metrics | OTLP from apps, hostmetrics, k8s_cluster   | Prometheus      | Azure Monitor    |
| Traces  | OTLP from apps                             | Tempo           | Azure Monitor    |
| Logs    | filelog (DaemonSet) + OTLP from apps       | Loki            | Azure Monitor    |

The **gateway Collector** runs as a Deployment for fan-in/fan-out and
batching. The **node Collector** runs as a DaemonSet, owns log tail-and-parse
and kubelet metrics, and forwards via OTLP to the gateway.

## AKS topology

- **3 node pools**:
  - `system` — control-plane add-ons only (`only_critical_addons_enabled`)
  - `user` — application workloads
  - `obs` — tainted `workload=observability:NoSchedule` so Prometheus, Tempo,
    Loki, and Grafana never compete with apps for CPU/memory
- **Workload identity + OIDC issuer** enabled — apps that need Azure APIs
  use federated identity, never static secrets.
- **Azure RBAC for Kubernetes** — cluster admin scoped to AAD groups.

## Deployment model

Everything — Azure infra, Helm releases, in-cluster manifests, dashboards, the
demo app — is provisioned by a single `terraform apply`. The Terraform graph:

```
azurerm_resource_group ─┬─ module.networking ─┐
                        ├─ module.registry    ├─→ module.aks ─┐
                        ├─ module.keyvault    │               │
                        └─ Log Analytics +    │   kube_config │
                           App Insights +     ┘   (in-memory) │
                           Azure Monitor WS                   │
                                                              ▼
                                                kubernetes_namespace.*
                                                helm_release.* (cert-mgr, ingress,
                                                                 KPS, Loki, Tempo,
                                                                 OTel operator)
                                                              │
                                                              ▼
                                                kubectl_manifest.*
                                                (OTel collector, Instrumentation,
                                                 PrometheusRule, NetworkPolicy)
                                                              │
                                                              ▼
                                              kubernetes_config_map.dashboards
                                              null_resource.build_images (Python 3.12 → ACR Tasks)
                                                              │
                                                              ▼
                                                kubectl_manifest.sample_app
```

`terraform destroy` walks the graph in reverse — Helm releases come down first,
then the AKS cluster, then the Azure infrastructure.

## CI/CD

- `lint.yml` — every PR: `terraform fmt/validate`, `tflint`, `tfsec`, `yamllint`,
  `kube-linter`, `ruff`, `mypy --strict`, `node -c`.
- `deploy.yml` — manual dispatch with per-environment **plan job** + reviewer-gated
  **apply job**. The plan artifact is passed between jobs so the applied plan is
  exactly the reviewed plan.
- `destroy.yml` — manual dispatch with a `DESTROY` confirmation input plus a
  GitHub *Environment* protection rule.

OIDC federation to Azure means no client secrets stored in GitHub.

## Scaling notes

- Prometheus retention 15d, 8 GB cap — bump `retentionSize` for prod and
  consider Thanos / Mimir or push to Azure Monitor Workspace for long-term.
- Loki single-binary is fine up to a few hundred GB/day — switch to
  microservices mode or Grafana Cloud / Azure Log Analytics export for more.
- The observability node pool autoscales 1→3; Prometheus PVC is
  ReadWriteOnce so reschedules stick to its AZ.

## Failure modes & runbooks

See [runbooks.md](runbooks.md).
