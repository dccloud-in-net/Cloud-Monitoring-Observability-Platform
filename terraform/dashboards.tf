# Wrap each Grafana dashboard JSON in a labelled ConfigMap so the
# kube-prometheus-stack Grafana sidecar imports it automatically.
resource "kubernetes_config_map" "grafana_dashboards" {
  for_each = fileset("${path.module}/../kubernetes/dashboards", "*.json")

  metadata {
    name      = "grafana-dashboard-${trimsuffix(each.value, ".json")}"
    namespace = kubernetes_namespace.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
      grafana_folder    = "Platform"
    }
  }

  data = {
    (each.value) = file("${path.module}/../kubernetes/dashboards/${each.value}")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
