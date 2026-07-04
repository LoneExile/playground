# Keycloak (identity provider) via the codecentric keycloakx chart.
# https://github.com/codecentric/helm-charts (chart: keycloakx, Keycloak 26).
#
# Postgres + secret are provisioned by manifests/keycloak-db.yaml (applied via
# kubectl_manifest.apps), with the DB data on NFS at config/keycloak/db. The
# chart deploys into the pre-existing 'keycloak' namespace and reads the DB
# password from the 'keycloak' secret. Values in values/keycloak.yaml.
#
# Exposure (same LAN + tunnel pattern as harbor/grafana):
#   https://keycloak.home.0dl.me   (LAN, wildcard TLS at the gateway)
#   https://keycloak.0dl.me        (public via Cloudflare Tunnel)
# NOTE: keycloak.0dl.me needs a matching public-hostname entry on the tunnel in
# the Cloudflare Zero Trust dashboard (same as harbor/grafana tunnel routes).

resource "helm_release" "keycloak" {
  depends_on = [
    time_sleep.wait_for_gateway,
    kubectl_manifest.apps,                          # keycloak-db.yaml: namespace + secret + postgres
    kubernetes_config_map_v1.keycloak_theme_homelab, # login theme mounted via extraVolumes
  ]

  name             = "keycloak"
  repository       = "https://codecentric.github.io/helm-charts"
  chart            = "keycloakx"
  version          = var.keycloakx_chart_version
  namespace        = "keycloak"
  create_namespace = false # owned by manifests/keycloak-db.yaml
  wait             = true
  timeout          = 600 # first boot builds the Quarkus image + runs DB migrations

  values = [file("${path.module}/values/keycloak.yaml")]
}

# LAN route — wildcard TLS at the gateway. Backend is the chart's http Service.
resource "kubectl_manifest" "keycloak_route" {
  depends_on = [
    helm_release.keycloak,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "keycloak"
      namespace = "keycloak"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "https-wildcard"
      }]
      hostnames = [local.hostnames.keycloak]
      rules = [{
        backendRefs = [{
          name = "keycloak-http"
          port = 80
        }]
      }]
    }
  })
}

# Tunnel route — bare keycloak.<primary_domain> via Cloudflare Tunnel (CF
# terminates TLS; bind to the :http listener). Requires the matching
# public-hostname entry on the tunnel in the CF Zero Trust dashboard.
resource "kubectl_manifest" "keycloak_route_tunnel" {
  depends_on = [
    helm_release.keycloak,
    time_sleep.wait_for_gateway,
  ]

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "keycloak-tunnel"
      namespace = "keycloak"
    }
    spec = {
      parentRefs = [{
        name        = "backbone-gateway"
        namespace   = "gateway-system"
        sectionName = "http"
      }]
      hostnames = ["keycloak.${var.primary_domain}"]
      rules = [{
        # The tunnel terminates TLS at Cloudflare and forwards plain HTTP to the
        # gateway's :80 listener, so Envoy stamps X-Forwarded-Proto: http.
        # Keycloak (SSL-required=external) then rejects with "HTTPS required" and
        # the admin console's session-check iframe hangs. This path is ALWAYS
        # https at the edge, so force the header back to https for Keycloak.
        filters = [{
          type = "RequestHeaderModifier"
          requestHeaderModifier = {
            set = [{ name = "X-Forwarded-Proto", value = "https" }]
          }
        }]
        backendRefs = [{
          name = "keycloak-http"
          port = 80
        }]
      }]
    }
  })
}
