# Homelab alert rules (PrometheusRule CRD). Prometheus picks it up cluster-wide
# (ruleSelectorNilUsesHelmValues=false). The single source of truth is
# manifests/alert-rules.yaml; edits go there. Alertmanager routing that forwards
# these to the hermes webhook -> Telegram lives in
# values/kube-prometheus-stack-alerting.yaml.tftpl (wired in monitoring.tf).
resource "kubectl_manifest" "homelab_alert_rules" {
  depends_on = [helm_release.kube_prometheus_stack] # needs the PrometheusRule CRD

  yaml_body = file("${path.module}/manifests/alert-rules.yaml")
}
