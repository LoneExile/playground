# Keycloak OIDC client for SFTPGo (homelab realm). The client secret is pinned
# from var.sftpgo_oidc_client_secret so the same value can be fed to SFTPGo's
# oidc config (manifests/sftpgo.yaml, rendered in apps.tf) without reading the
# generated secret back — keeps the two in lockstep with no resource coupling.
#
# SFTPGo appends /web/oidc/redirect to its redirect_base_url; register that path
# for both the LAN and public hosts.
resource "keycloak_openid_client" "sftpgo" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "sftpgo"
  name      = "SFTPGo"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  client_secret         = var.sftpgo_oidc_client_secret

  valid_redirect_uris = [
    "https://sftpgo.${var.primary_domain}/web/oidc/redirect",
    "https://${local.hostnames.sftpgo}/web/oidc/redirect",
  ]
}
