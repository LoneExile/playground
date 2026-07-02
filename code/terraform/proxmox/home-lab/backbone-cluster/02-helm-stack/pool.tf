# pool-monitor Grafana dashboard. The kube-prometheus-stack Grafana sidecar
# watches ALL namespaces for ConfigMaps labeled grafana_dashboard=1 and
# auto-imports their JSON. Lives in the monitoring namespace (already exists).
resource "kubectl_manifest" "pool_dashboard" {
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "pool-dashboard"
      namespace = "monitoring"
      labels    = { grafana_dashboard = "1" }
    }
    data = {
      "pool.json" = file("${path.module}/values/pool-dashboard.json")
    }
  })
}
