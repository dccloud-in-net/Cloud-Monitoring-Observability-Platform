# ────────────────────────────────────────────────────────────────────
#  Namespaces
# ────────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
    labels = {
      purpose                                = "monitoring"
      "pod-security.kubernetes.io/enforce"   = "privileged"
    }
  }
}

resource "kubernetes_namespace" "opentelemetry" {
  metadata {
    name = "opentelemetry"
    labels = {
      purpose                              = "tracing"
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_namespace" "demo_apps" {
  metadata {
    name = "demo-apps"
    labels = {
      purpose                              = "workloads"
      instrumentation                      = "enabled"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

# ────────────────────────────────────────────────────────────────────
#  Application Insights connection string — consumed by OTel exporter
# ────────────────────────────────────────────────────────────────────
resource "kubernetes_secret" "azure_monitor" {
  metadata {
    name      = "azure-monitor"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }
  data = {
    "connection-string" = azurerm_application_insights.this.connection_string
  }
  type = "Opaque"
}

# ────────────────────────────────────────────────────────────────────
#  Helm charts — observability stack
# ────────────────────────────────────────────────────────────────────
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.15.0"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  timeout    = 600
  values     = [file("${path.module}/../kubernetes/helm-values/cert-manager-values.yaml")]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.10.1"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  timeout    = 600
  values     = [file("${path.module}/../kubernetes/helm-values/ingress-nginx-values.yaml")]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kps"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "61.3.0"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  timeout    = 900
  values     = [file("${path.module}/../kubernetes/helm-values/kube-prometheus-stack-values.yaml")]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.6.4"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  timeout    = 600
  values     = [file("${path.module}/../kubernetes/helm-values/loki-values.yaml")]
}

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.10.1"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  timeout    = 600
  values     = [file("${path.module}/../kubernetes/helm-values/tempo-values.yaml")]
  depends_on = [helm_release.kube_prometheus_stack]
}

resource "helm_release" "otel_operator" {
  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = "0.62.0"
  namespace  = kubernetes_namespace.opentelemetry.metadata[0].name
  timeout    = 600
  values     = [file("${path.module}/../kubernetes/helm-values/opentelemetry-operator-values.yaml")]
  set {
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-contrib"
  }
  depends_on = [helm_release.cert_manager]
}
