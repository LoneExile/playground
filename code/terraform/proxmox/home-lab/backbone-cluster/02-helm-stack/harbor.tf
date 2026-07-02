# Harbor container registry. Chart values in values/harbor.yaml; secrets and
# externalURL injected here.
#
# Canonical URL is the LAN name (harbor.<fqdn_base>): docker login/push/pull
# get a real wildcard cert and skip the Cloudflare proxy's 100MB per-request
# body cap. The tunnel route (harbor.<primary_domain>) is for browsing the UI
# from outside — registry clients hitting it get token/redirect URLs pointing
# at the canonical name, so pushes/pulls only work where that resolves.

resource "helm_release" "harbor" {
  depends_on = [
    time_sleep.wait_for_gateway,
    helm_release.nfs_subdir_provisioner,  # registry/db/redis/trivy PVCs
    helm_release.kube_prometheus_stack,   # ServiceMonitor CRD must exist first
  ]

  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = var.harbor_chart_version
  namespace        = "harbor"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [file("${path.module}/values/harbor.yaml")]

  set {
    name  = "externalURL"
    value = "https://${local.hostnames.harbor}"
  }

  set_sensitive {
    name  = "harborAdminPassword"
    value = var.harbor_admin_password
  }

  set_sensitive {
    name  = "database.internal.password"
    value = var.harbor_db_password
  }

  set_sensitive {
    name  = "secretKey"
    value = var.harbor_secret_key
  }
}

# LAN route on the HTTPS wildcard listener. Backend is harbor's nginx Service
# (named "harbor"), which fronts core/portal/registry. 900s timeouts: Envoy's
# default 15s request timeout kills large layer uploads.
resource "kubectl_manifest" "harbor_route" {
  depends_on = [
    helm_release.harbor,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "harbor"
      namespace = "harbor"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "https-wildcard"
      }]
      hostnames = [local.hostnames.harbor]
      rules = [{
        backendRefs = [{
          name = "harbor"
          port = 80
        }]
        timeouts = {
          request        = "900s"
          backendRequest = "900s"
        }
      }]
    }
  })
}

# Tunnel route — bare harbor.<primary_domain> via Cloudflare Tunnel (UI
# browsing from outside; see canonical-URL note above). Requires the matching
# public-hostname entry on the tunnel in the CF Zero Trust dashboard.
resource "kubectl_manifest" "harbor_route_tunnel" {
  depends_on = [
    helm_release.harbor,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "harbor-tunnel"
      namespace = "harbor"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "http"
      }]
      hostnames = ["harbor.${var.primary_domain}"]
      rules = [{
        backendRefs = [{
          name = "harbor"
          port = 80
        }]
        timeouts = {
          request        = "900s"
          backendRequest = "900s"
        }
      }]
    }
  })
}
