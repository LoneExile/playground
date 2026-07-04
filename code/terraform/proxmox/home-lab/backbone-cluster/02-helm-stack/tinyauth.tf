# Keycloak OIDC client for TinyAuth (homelab realm). TinyAuth is a forward-auth
# gateway: Envoy Gateway SecurityPolicy ext_authz points the protected apps'
# routes at it, and it authenticates the user against Keycloak (generic OIDC
# provider) before allowing the request through. See manifests/tinyauth.yaml.
#
# The client secret is pinned from var.tinyauth_oidc_client_secret so the same
# value feeds both this Keycloak client and TinyAuth's env (rendered in apps.tf)
# without reading the generated secret back — same cycle-break rationale as
# sftpgo/gitlab/paperless (referencing the computed client secret from an
# app_rendered manifest would cycle through helm_release.keycloak).
#
# TinyAuth runs at the PUBLIC host tinyauth.<primary_domain> so its session
# cookie is scoped to the registrable domain (.0dl.me) and therefore covers BOTH
# the LAN apps (*.home.0dl.me) and the Cloudflare-tunnel apps (*.0dl.me) with one
# SSO. TinyAuth registers its OAuth callback at <APPURL>/api/oauth/callback/generic
# (provider id "generic").
#
# MANUAL (Cloudflare, can't be terraformed): add a Zero Trust tunnel
# public-hostname entry tinyauth.<primary_domain> → http://<gateway_ip>:80 and the
# matching CNAME, same as the other *.0dl.me tunnel hosts.
resource "keycloak_openid_client" "tinyauth" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "tinyauth"
  name      = "TinyAuth"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  client_secret         = var.tinyauth_oidc_client_secret

  valid_redirect_uris = [
    "https://tinyauth.${var.primary_domain}/api/oauth/callback/generic",
  ]
  web_origins = [
    "https://tinyauth.${var.primary_domain}",
  ]
}
