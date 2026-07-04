# Keycloak OIDC client for Dashy (homelab realm).
#
# Dashy's dashboard is a SPA that authenticates with generic OIDC (oidc-client-ts)
# using the redirect auth-code flow + PKCE — so this is a PUBLIC client with no
# secret (nothing to pin into the manifest, unlike sftpgo/openbao). conf.yml sets
# enableSilentRenew:false, so there's no cross-origin renew iframe and the shared
# homelab realm's X-Frame-Options / CSP stay untouched.
#
# Redirect, post-logout, and web-origin entries cover both access paths — the
# public Cloudflare tunnel (dashy.0dl.me) and the LAN wildcard (dashy.home.0dl.me).
# The current window origin is what oidc-client-ts uses as redirect_uri, so both
# must be registered. web_origins is required for the browser's CORS token
# request. `/*` covers whatever hash/callback path Dashy lands on.
#
# No realm-role/group mapper: with appConfig.preventWriteToDisk the dashboard is
# read-only for everyone, so admin-vs-user is moot — any authenticated homelab
# realm user (i.e. the GitHub-brokered account) is allowed in.
resource "keycloak_openid_client" "dashy" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "dashy"
  name      = "Dashy"
  enabled   = true

  access_type                = "PUBLIC"
  standard_flow_enabled      = true
  pkce_code_challenge_method = "S256"

  valid_redirect_uris = [
    "https://dashy.${var.primary_domain}/*",
    "https://dashy.${local.fqdn_base}/*",
  ]
  valid_post_logout_redirect_uris = [
    "https://dashy.${var.primary_domain}/*",
    "https://dashy.${local.fqdn_base}/*",
  ]
  web_origins = [
    "https://dashy.${var.primary_domain}",
    "https://dashy.${local.fqdn_base}",
  ]
}
