# Monitoring: kube-prometheus-stack (prometheus-operator/kube-prometheus as a
# Helm chart) — Prometheus Operator, Prometheus, Alertmanager, Grafana,
# node-exporter, kube-state-metrics, default dashboards + alert rules.
# Talos-specific value overrides live in values/kube-prometheus-stack.yaml.
# Grafana is exposed at grafana.<fqdn_base> through backbone-gateway (covered
# by the existing wildcard cert + wildcard Cloudflare A record).
#
# The 'monitoring' namespace is NOT created here — manifests/node-thermal.yaml
# owns it (applied via kubectl_manifest.apps) and already carries the
# privileged PSA labels node-exporter needs for hostNetwork/hostPID/hostPath.

resource "helm_release" "kube_prometheus_stack" {
  depends_on = [
    kubectl_manifest.apps,                # namespace comes from node-thermal.yaml doc 0
    helm_release.nfs_subdir_provisioner,  # Prometheus/Grafana/Alertmanager PVCs
  ]

  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = false
  wait             = true
  timeout          = 900 # CRDs + operator + Prometheus/Grafana image pulls

  # Base values, then an alerting layer that injects the Alertmanager route +
  # hermes webhook receiver (secret kept out of the committed base file).
  values = [
    file("${path.module}/values/kube-prometheus-stack.yaml"),
    templatefile("${path.module}/values/kube-prometheus-stack-alerting.yaml.tftpl", {
      hermes_webhook_url    = var.hermes_webhook_url
      hermes_webhook_secret = var.hermes_webhook_secret
    }),
  ]

  # Canonical URL = the public tunnel hostname (grafana.<primary_domain>);
  # the LAN name (grafana.<fqdn_base>) still serves fine, but absolute links
  # and login redirects point here.
  set {
    name  = "grafana.grafana\\.ini.server.root_url"
    value = "https://grafana.${var.primary_domain}"
  }

  # Seeds the admin user on FIRST boot only (persistence is enabled, so later
  # changes to this value do not rotate the password — see variables.tf).
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

# Public hostname for Grafana on the shared gateway. Service name follows the
# grafana subchart convention: <release>-grafana, port 80. Bound explicitly to
# the HTTPS listener so the login form never serves over cleartext :80.
resource "kubectl_manifest" "grafana_route" {
  depends_on = [
    helm_release.kube_prometheus_stack,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana"
      namespace = "monitoring"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "https-wildcard"
      }]
      hostnames = [local.hostnames.grafana]
      rules = [{
        backendRefs = [{
          name = "kube-prometheus-stack-grafana"
          port = 80
        }]
      }]
    }
  })
}

# Tunnel route — bare grafana.<primary_domain> via Cloudflare Tunnel. HTTP-only
# (the wildcard cert covers *.<fqdn_base>, not this hostname), so bind
# explicitly to the :80 listener. CF terminates TLS at the edge. Requires the
# matching public-hostname entry on the tunnel in the CF Zero Trust dashboard
# (same origin as memos/files: http://<gateway_external_ip>:80).
resource "kubectl_manifest" "grafana_route_tunnel" {
  depends_on = [
    helm_release.kube_prometheus_stack,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana-tunnel"
      namespace = "monitoring"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "http"
      }]
      hostnames = ["grafana.${var.primary_domain}"]
      rules = [{
        backendRefs = [{
          name = "kube-prometheus-stack-grafana"
          port = 80
        }]
      }]
    }
  })
}
