# Cloud Monitoring & Observability Platform

[![lint](https://img.shields.io/badge/CI-lint-success)](.github/workflows/lint.yml)
[![deploy](https://img.shields.io/badge/CI-deploy-blue)](.github/workflows/deploy.yml)
[![terraform](https://img.shields.io/badge/IaC-terraform-7B42BC?logo=terraform)](terraform/)
[![aks](https://img.shields.io/badge/Azure-AKS-0078D4?logo=microsoftazure)](terraform/modules/aks/)
[![otel](https://img.shields.io/badge/OpenTelemetry-collector-f5a800?logo=opentelemetry)](kubernetes/otel/)

A centralized, production-grade observability platform delivering deep operational visibility across cloud infrastructure, **Azure Kubernetes Service (AKS)** workloads, and enterprise applications. Built on **OpenTelemetry (OTel)**, **Prometheus**, **Grafana**, **Loki**, and **Tempo**, the platform provides correlation across metrics, logs, and distributed traces—fully automated via **GitHub Actions CI/CD** and provisioned via **Terraform**.

> **Fully automated deployment and teardown via GitHub Actions CI/CD workflows — no manual CLI execution or glue scripts.**

---

## 📋 Platform Profile

| Field | Detail |
| :--- | :--- |
| **Cloud Provider** | Microsoft Azure |
| **Technology Stack** | OpenTelemetry · Prometheus · Grafana · Tempo · Loki · Azure Monitor · Log Analytics · Application Insights · AKS · GitHub Actions · Terraform · Helm |
| **Automation Glue** | 100% Declarative Terraform & Kubernetes Manifests (No custom build scripts) |
| **CI/CD Pipeline** | GitHub Actions (Plan-then-Apply with Environment Gates & OIDC Federation) |
| **Deployment Time** | ~15 minutes end-to-end |

### 🔍 Challenge & Context
Managing and debugging distributed microservice architectures on Kubernetes without unified telemetry leads to blind spots, high Mean Time to Resolution (MTTR), and reactive operations. This platform was built to solve these issues by providing a single pane of glass for metrics, logs, and traces with standard OpenTelemetry instrumentation.

### 🛠️ My Role & Scope
* **Unified Infrastructure as Code**: Codified the entire Azure landing zone and in-cluster observability stack with Terraform, utilizing the Helm, Kubernetes, and Kubectl providers to avoid local bootstrapping scripts.
* **OpenTelemetry Instrumentation**: Instrumented application workloads to auto-collect OTel metrics and distributed traces, establishing end-to-end context propagation.
* **Telemetry Collection & Sinks**: Configured Prometheus remote-write capabilities to store metrics in Azure Monitor for long-term retention.
* **Grafana Visualization & Alerts**: Designed operational dashboards for Kubernetes resources and SLOs, and set up Alertmanager-routed SRE alerts based on Golden Signals and error budget burn rates.

### 💡 Business Value Delivered
* **Complete System Visibility**: Unified view across infrastructure health, OTel pipelines, and business workloads.
* **Drill-down Troubleshooting**: Traces, logs, and metrics are fully correlated in Grafana, enabling rapid root-cause analysis.
* **Proactive SRE Alerting**: Automated notifications based on SLO multi-window burn rates, signaling issues before users are impacted.

---

## 🏗️ Architecture

```
        Azure subscription                          AKS cluster
   ┌──────────────────────────┐         ┌────────────────────────────────┐
   │  RG ─ VNet ─ AKS         │         │  ns: opentelemetry             │
   │  ACR    Key Vault        │         │   ┌────────────────────────┐   │
   │  Log Analytics WS        │  ◀───── │   │ OTel Collector gateway │   │
   │  Application Insights    │  OTLP   │   │  + DaemonSet (logs)    │   │
   │  Azure Monitor Workspace │         │   └─────┬──────┬─────┬─────┘   │
   └──────────────────────────┘         │   metrics traces  logs         │
                                        │         ▼      ▼     ▼         │
                                        │   Prometheus  Tempo  Loki      │
                                        │         │      │      │        │
                                        │         ▼      ▼      ▼        │
                                        │      Grafana  ◀──▶  Alertmgr   │
                                        └────────────────────────────────┘
```

*For a deep dive into data flow and component configuration, see [docs/architecture.md](docs/architecture.md).*

---

## 📁 Repository Structure

```
.
├── terraform/                           # Infrastructure as Code
│   ├── providers.tf · backend.tf        # Providers and Remote State configuration
│   ├── variables.tf · outputs.tf        # Inputs and Outputs definitions
│   ├── main.tf                          # Azure Resources (AKS, ACR, Key Vault, Monitor WS, Log Analytics)
│   ├── monitoring.tf                    # Observability namespaces and Helm releases (Loki, Tempo, cert-manager)
│   ├── manifests.tf                     # Kubernetes custom resources (OTel Collector, alerts, network policies)
│   ├── dashboards.tf                    # Dashboard ConfigMaps for auto-importing into Grafana
│   ├── sample_app.tf                    # ACR Tasks configuration & sample app manifests deployment
│   ├── terraform.tfvars.example         # Template for local development/reference variables
│   └── modules/                         # Reusable Terraform modules (networking, aks, registry, keyvault)
├── kubernetes/                          # Kubernetes Manifests & Configuration
│   ├── helm-values/                     # Overrides and values for Helm-installed releases
│   ├── otel/                            # OTel Collector, DaemonSets, and Instrumentation configurations
│   ├── alerts/prometheus-rules.yaml     # Prometheus custom rules (Golden Signals & SRE SLO alerts)
│   ├── dashboards/*.json                # Dashboard templates auto-imported into Grafana
│   ├── policies/network-policies.yaml   # Network security policies for namespaces
│   └── sample-app/manifests.yaml.tftpl  # Terraform-rendered template for the demo workload
├── sample-app/                          # Telemetry Demonstration Workload
│   ├── frontend/                        # Flask application (Python) — OTel Auto-instrumented
│   └── backend/                         # Express application (Node.js) — OTel Auto-instrumented
├── scripts/                             # Utility Scripts
│   └── port_forward.py                  # CLI utility for local dashboard port-forwarding
├── .github/workflows/                   # GitHub Actions Workflows (CI/CD)
├── .config/                             # Linter & formatter configurations
└── docs/                                # Technical Documentation & Runbooks
```

---

## ⚙️ CI/CD & Pipeline Deployment

The platform is designed to be deployed and managed entirely via **GitHub Actions**.

### Prerequisites & Setup

> [!NOTE]
> All credentials and state configs are maintained securely in GitHub Secrets. Manual CLI deployments are not required.

#### 1. Federated Azure Credentials (OIDC)
Set up OIDC federation for GitHub Actions to authenticate securely with Azure without using long-lived secrets. Create the following repository secrets:
* `AZURE_CLIENT_ID` — Application (client) ID of the Azure AD app registration
* `AZURE_TENANT_ID` — Directory (tenant) ID
* `AZURE_SUBSCRIPTION_ID` — Target Azure Subscription ID

#### 2. Terraform Remote Backend Setup
Configure Azure Blob Storage for remote state tracking and define these secrets:
* `TF_STATE_RG` — Resource Group name for the Storage Account
* `TF_STATE_SA` — Storage Account name
* `TF_STATE_CONTAINER` — Storage Container name for state backend files

---

### 🚀 Deploying the Platform

1. Navigate to the **Actions** tab in your GitHub repository.
2. Select the **deploy** workflow in the sidebar.
3. Click **Run workflow**, choose your branch (e.g., `main`), and select the target environment (`dev`, `staging`, `prod`).
4. Once the plan phase finishes, review the `terraform plan` output in the pipeline logs.
5. Approve the deployment gate (for `staging` and `prod`) to execute the apply step and provision the resources.

### 🧹 Tearing Down the Platform

To destroy all provisioned infrastructure and avoid Azure usage charges:
1. Navigate to the **Actions** tab.
2. Select the **destroy** workflow.
3. Click **Run workflow**, choose the environment, and type `DESTROY` as the confirmation input.

---

## 🔍 Accessing the Dashboards

Since the platform is deployed in a secure private network, you can port-forward to the cluster dashboards locally:

```bash
python3 scripts/port_forward.py
```

Once running, the following endpoints will be available locally:
* **Grafana**: [http://localhost:3000](http://localhost:3000) (admin / auto-generated password)
* **Prometheus**: [http://localhost:9090](http://localhost:9090)
* **Alertmanager**: [http://localhost:9093](http://localhost:9093)
* **Tempo**: [http://localhost:3200](http://localhost:3200)
* **OTel Gateway zpages**: [http://localhost:55679](http://localhost:55679)

---

## 📊 Out-of-the-Box Dashboards & Alerts

### Grafana Dashboards
* **AKS Cluster Overview**: CPU/Memory utilization, node readiness, pod restart counts, and network throughput.
* **OTel Pipeline Health**: Telemetry ingestion rates, queue saturation, drops, and exporter failure metrics.
* **Application Golden Signals**: Request rate, error percentage, latency (p50, p95, p99), and SLO burn-rate budget.

### Alerting Policies Deployed
* **Infrastructure Health**: `KubeNodeNotReady`, `KubePodCrashLoopingHigh`, `KubeMemoryPressure`.
* **Telemetry Pipeline**: `OTelCollectorDown`, `OTelExporterQueueSaturated`.
* **SRE SLO Rules**: Google SRE-style multi-window multi-burn-rate alerts (`SLOErrorBudgetBurnFast`, `SLOErrorBudgetBurnSlow`).

---

## 📖 Further Reading

* [docs/architecture.md](docs/architecture.md) — Detailed components and data-flow explanation.
* [docs/runbooks.md](docs/runbooks.md) — Operator runbooks for resolving active alerts.
* [docs/onboarding.md](docs/onboarding.md) — Workload onboarding guides and platform extension.
