# OpenBao (secrets manager, Vault fork) via the official chart.
# https://openbao.org/docs/platform/k8s/helm/  (chart: openbao)
#
# Standalone single node, `file` storage on NFS at config/openbao/data (PV +
# namespace from manifests/openbao-nfs.yaml). Values in values/openbao.yaml.
#
# Exposure (same LAN + tunnel pattern as harbor/keycloak):
#   https://openbao.home.0dl.me   (LAN, wildcard TLS at the gateway)
#   https://openbao.0dl.me        (public via Cloudflare Tunnel — add the
#                                  public-hostname entry in the CF dashboard)
#
# The readiness probe (values/openbao.yaml) reports Ready even while sealed/
# uninitialised, so the pod is routable and the UI/API are reachable through the
# gateway for setup. wait = false anyway: a fresh OpenBao is uninitialised and
# we don't want the apply coupled to app state. One-time setup after apply, via
# the UI at https://openbao.home.0dl.me (or `kubectl -n openbao exec`):
#   bao operator init
#     → save the 5 unseal keys + the root token somewhere safe (this is the
#       ONLY time they are shown; losing the unseal keys = losing the data).
#   bao operator unseal <key>   # ×3
# OpenBao must be unsealed again after any restart (no auto-unseal configured);
# because the pod stays Ready while sealed, the UI stays reachable to do it.

resource "helm_release" "openbao" {
  depends_on = [
    time_sleep.wait_for_gateway,
    kubectl_manifest.apps, # openbao-nfs.yaml: namespace + NFS PV/PVC
  ]

  name             = "openbao"
  repository       = "https://openbao.github.io/openbao-helm"
  chart            = "openbao"
  version          = var.openbao_chart_version
  namespace        = "openbao"
  create_namespace = false # owned by manifests/openbao-nfs.yaml
  wait             = false # boots sealed → never Ready until manual unseal
  timeout          = 300

  values = [file("${path.module}/values/openbao.yaml")]
}

# LAN route — wildcard TLS at the gateway. Backend is the chart's server Service.
resource "kubectl_manifest" "openbao_route" {
  depends_on = [
    helm_release.openbao,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "openbao"
      namespace = "openbao"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "https-wildcard"
      }]
      hostnames = [local.hostnames.openbao]
      rules = [{
        backendRefs = [{
          name = "openbao"
          port = 8200
        }]
      }]
    }
  })
}

# Tunnel route — bare openbao.<primary_domain> via Cloudflare Tunnel (CF
# terminates TLS; bind to the :http listener). Requires the matching
# public-hostname entry on the tunnel in the CF Zero Trust dashboard.
resource "kubectl_manifest" "openbao_route_tunnel" {
  depends_on = [
    helm_release.openbao,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "openbao-tunnel"
      namespace = "openbao"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "http"
      }]
      hostnames = ["openbao.${var.primary_domain}"]
      rules = [{
        backendRefs = [{
          name = "openbao"
          port = 8200
        }]
      }]
    }
  })
}
