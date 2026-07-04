# GitHub → Keycloak → OpenBao single sign-on.
#
# The chain: a user hits OpenBao → OpenBao (oidc auth method) redirects to
# Keycloak → Keycloak offers "Login with GitHub" → GitHub OAuth → back to
# Keycloak → back to OpenBao with an ID token mapped to an OpenBao policy.
#
# This file manages the KEYCLOAK side via the keycloak provider:
#   - a dedicated `homelab` realm for cluster-service SSO (kept out of `master`,
#     which stays for Keycloak admin only)
#   - GitHub as a brokered social Identity Provider
#   - an `openbao` confidential OIDC client that OpenBao points at
#
# GitHub side (MANUAL — GitHub OAuth Apps are not API-creatable): register an
# OAuth App at https://github.com/settings/developers →
#   Application name:           OpenBao (or anything)
#   Homepage URL:               https://keycloak.0dl.me
#   Authorization callback URL: https://keycloak.0dl.me/realms/homelab/broker/github/endpoint
# Copy its Client ID + generate a Client secret into terraform.tfvars as
# keycloak_github_client_id / keycloak_github_client_secret, THEN apply.
#
# OpenBao side (MANUAL — the root/admin token stays out of TF state): enable the
# oidc auth method pointed at this realm, using the client secret from
# `terraform output -raw openbao_oidc_client_secret`. See the runbook note
# "OpenBao — GitHub SSO via Keycloak".
#
# One canonical host for the whole flow: everything uses the PUBLIC
# https://keycloak.0dl.me so the issuer matches whether you log in on-LAN
# (Cloudflare hairpin) or remote. (Keycloak runs KC_HOSTNAME_STRICT=false, so
# the issuer follows the request host — pinning one host avoids issuer drift.)

resource "keycloak_realm" "homelab" {
  realm        = "homelab"
  enabled      = true
  display_name = "Homelab"
}

# GitHub social login, brokered into the homelab realm. trust_email verifies the
# imported email so first-broker-login doesn't prompt; IMPORT copies the GitHub
# profile into a local Keycloak user on first login.
resource "keycloak_oidc_github_identity_provider" "github" {
  realm         = keycloak_realm.homelab.id
  alias         = "github"
  client_id     = var.keycloak_github_client_id
  client_secret = var.keycloak_github_client_secret
  trust_email   = true
  sync_mode     = "IMPORT"
}

# GitHub login for the Keycloak admin console itself (master realm), so the
# cluster can be administered with a GitHub account instead of the temporary
# bootstrap admin. Reuses the SAME GitHub OAuth App as the homelab IdP above:
# GitHub allows a request redirect_uri that is a subdirectory of the App's
# registered callback, so the App's Authorization callback URL is broadened to
# the parent `https://keycloak.0dl.me/realms/`, which covers every realm's
# `/realms/<realm>/broker/github/endpoint`. Hence the same client id/secret.
#
# NOTE: the `admin` role must be granted to your brokered master user BY HAND
# (Users → your user → Role mapping → assign `admin`). Terraform can't do it —
# the user only exists after the first GitHub login. Never auto-assign admin via
# an IdP role-mapper: that would make every GitHub account a Keycloak admin.
resource "keycloak_oidc_github_identity_provider" "github_master" {
  realm         = "master"
  alias         = "github"
  client_id     = var.keycloak_github_client_id
  client_secret = var.keycloak_github_client_secret
  trust_email   = true
  sync_mode     = "IMPORT"
}

# Confidential OIDC client OpenBao authenticates as. The redirect URIs are
# OpenBao's OIDC callbacks — UI (both hostnames) + the CLI's localhost listener.
# Path segment `oidc/oidc/callback` = <auth-method-mount=oidc>/oidc/callback.
resource "keycloak_openid_client" "openbao" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "openbao"
  name      = "OpenBao"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://openbao.0dl.me/ui/vault/auth/oidc/oidc/callback",
    "https://openbao.home.0dl.me/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
}
