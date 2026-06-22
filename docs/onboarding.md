# Onboarding

## Local prerequisites

| Tool        | Version | Install                          | Required for |
|-------------|--------:|-----------------------------------|-------------|
| Terraform   | ≥ 1.6   | `brew install terraform`          | provisioning everything |
| Azure CLI   | ≥ 2.60  | `brew install azure-cli`          | login + ACR image builds |
| Python      | 3.12    | `brew install python@3.12`        | `scripts/build_images.py` |
| kubectl     | ≥ 1.29  | `brew install kubectl`            | optional — only for `port_forward.py` |
| jq          | latest  | `brew install jq`                 | optional |

`helm` and a local Docker daemon are **not** required — Terraform talks to AKS via
the helm/kubernetes/kubectl providers, and image builds happen remotely in ACR Tasks.

## First-time deploy

```bash
az login
az account set --subscription "<YOUR-SUBSCRIPTION-ID>"

cd terraform
cp terraform.tfvars.example terraform.tfvars   # tune sizes / region if you want
terraform init
terraform apply

# When apply finishes, open the dashboards locally:
cd ..
python3.12 scripts/port_forward.py             # then visit http://localhost:3000
```

## Instrumenting a new service

1. Put the service in a namespace labelled
   `instrumentation: enabled` (e.g. `demo-apps`).
2. Add annotations to the pod template — the OTel Operator does the rest:
   ```yaml
   metadata:
     annotations:
       instrumentation.opentelemetry.io/inject-python: "true"   # or nodejs / java / dotnet / go
       instrumentation.opentelemetry.io/container-names: "myapp"
   ```
3. Optional: set `OTEL_SERVICE_NAME` and
   `OTEL_RESOURCE_ATTRIBUTES=service.namespace=...,service.version=...`.

Within ~30 seconds the service shows up in Tempo and the
**Application Golden Signals** dashboard.

## Adding an alert

Edit `kubernetes/alerts/prometheus-rules.yaml` and re-apply:

```bash
cd terraform
terraform apply -target=kubectl_manifest.alerts
```

Prometheus picks the rule up on its next evaluation interval (30s).

## Adding a Grafana dashboard

Drop a JSON file into `kubernetes/dashboards/` and re-apply — the
`kubernetes_config_map` resource uses `fileset()`, so a new file is
picked up automatically on the next `terraform apply`:

```bash
cd terraform
terraform apply -target='kubernetes_config_map.grafana_dashboards'
```

The Grafana sidecar imports it within ~30 seconds — no UI clicks.

## Tear down

```bash
cd terraform
terraform destroy
```

Resource group, VNet, AKS, ACR, Key Vault, Log Analytics, App Insights,
Monitor Workspace — all gone.
