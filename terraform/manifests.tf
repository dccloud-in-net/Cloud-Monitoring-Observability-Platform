# Apply raw YAML manifests via the kubectl provider so multi-document
# files and CRDs (OpenTelemetryCollector, Instrumentation, PrometheusRule)
# work without round-tripping through HCL.

# ────────────────────────────────────────────────────────────────────
#  OpenTelemetry Collector — gateway Deployment + node DaemonSet
# ────────────────────────────────────────────────────────────────────
data "kubectl_file_documents" "otel_collector" {
  content = file("${path.module}/../kubernetes/otel/collector.yaml")
}

resource "kubectl_manifest" "otel_collector" {
  for_each  = data.kubectl_file_documents.otel_collector.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.otel_operator,
    kubernetes_secret.azure_monitor,
    helm_release.kube_prometheus_stack,
    helm_release.tempo,
    helm_release.loki,
  ]
}

data "kubectl_file_documents" "otel_collector_daemonset" {
  content = file("${path.module}/../kubernetes/otel/collector-daemonset.yaml")
}

resource "kubectl_manifest" "otel_collector_daemonset" {
  for_each  = data.kubectl_file_documents.otel_collector_daemonset.manifests
  yaml_body = each.value
  depends_on = [kubectl_manifest.otel_collector]
}

# ────────────────────────────────────────────────────────────────────
#  Auto-instrumentation CR (consumed by the Operator's mutating webhook)
# ────────────────────────────────────────────────────────────────────
data "kubectl_file_documents" "otel_instrumentation" {
  content = file("${path.module}/../kubernetes/otel/instrumentation.yaml")
}

resource "kubectl_manifest" "otel_instrumentation" {
  for_each  = data.kubectl_file_documents.otel_instrumentation.manifests
  yaml_body = each.value
  depends_on = [
    helm_release.otel_operator,
    kubernetes_namespace.demo_apps,
  ]
}

# ────────────────────────────────────────────────────────────────────
#  Prometheus alert rules (golden signals + SLO burn-rate)
# ────────────────────────────────────────────────────────────────────
data "kubectl_file_documents" "alerts" {
  content = file("${path.module}/../kubernetes/alerts/prometheus-rules.yaml")
}

resource "kubectl_manifest" "alerts" {
  for_each  = data.kubectl_file_documents.alerts.manifests
  yaml_body = each.value
  depends_on = [helm_release.kube_prometheus_stack]
}

# ────────────────────────────────────────────────────────────────────
#  Network policies (default-deny + per-flow allows)
# ────────────────────────────────────────────────────────────────────
data "kubectl_file_documents" "network_policies" {
  content = file("${path.module}/../kubernetes/policies/network-policies.yaml")
}

resource "kubectl_manifest" "network_policies" {
  for_each  = data.kubectl_file_documents.network_policies.manifests
  yaml_body = each.value
  depends_on = [kubernetes_namespace.demo_apps]
}
