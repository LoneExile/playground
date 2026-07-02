# EcoFlow Grafana dashboard. The kube-prometheus-stack Grafana sidecar watches
# ALL namespaces for ConfigMaps labeled grafana_dashboard=1 and auto-imports
# their JSON, so this needs no Grafana API call — it lands in Grafana on apply.
# Lives in the monitoring namespace (already exists) to avoid ordering against
# the ecoflow namespace.
resource "kubectl_manifest" "ecoflow_dashboard" {
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "ecoflow-dashboard"
      namespace = "monitoring"
      labels    = { grafana_dashboard = "1" }
    }
    data = {
      "ecoflow.json" = file("${path.module}/values/ecoflow-dashboard.json")
    }
  })
}
