# OIDC clients for the second wave of homelab-realm services (Grafana, GitLab,
# Harbor, Immich, Paperless, Memos, Open WebUI, Reactive Resume). The first wave
# (openbao, sftpgo, dashy) lives in keycloak-oidc.tf / sftpgo.tf / dashy.tf.
#
# All are CONFIDENTIAL authorization-code clients. The client secret is
# Keycloak-GENERATED and consumed via the computed `.client_secret` attribute —
# no tfvars entry, no openssl. Each app's config references it directly (helm
# set_sensitive / templatefile → Secret), or, for the three apps whose OIDC
# config lives outside Terraform (open-webui on an off-cluster LXC; immich +
# memos store it in their DB), it's surfaced via a sensitive output in outputs.tf
# for a one-time manual wiring step.
#
# Access policy = "lock to me": the clients just register redirect URIs; each
# app's config blocks auto-signup and links OIDC to the existing owner account.
# NOTE: the homelab realm's GitHub IdP is itself unrestricted (any GitHub user
# can broker in) — the durable fix is a realm-level restriction; see the ZenNote.

# Realm role granted to the owner's Keycloak user by hand (Users → you → Role
# mapping). Apps that support role→admin mapping (Grafana here; Open WebUI via
# LXC env) key their admin off this. Never auto-assigned via an IdP mapper —
# that would make every brokered GitHub account an admin.
resource "keycloak_role" "homelab_admin" {
  realm_id    = keycloak_realm.homelab.id
  name        = "homelab-admin"
  description = "Homelab administrator — mapped to app admin where supported. Assign to your user by hand."
}

# --- Grafana --------------------------------------------------------------
resource "keycloak_openid_client" "grafana" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "grafana"
  name      = "Grafana"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://grafana.${var.primary_domain}/login/generic_oauth",
    "https://grafana.${local.fqdn_base}/login/generic_oauth",
  ]
  web_origins = [
    "https://grafana.${var.primary_domain}",
    "https://grafana.${local.fqdn_base}",
  ]
}

# --- GitLab ---------------------------------------------------------------
resource "keycloak_openid_client" "gitlab" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "gitlab"
  name      = "GitLab"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  client_secret         = var.gitlab_oidc_client_secret # pinned — see variables.tf (cycle break)

  # external_url is the LAN host, but redirect_uri is omitted in GitLab's config
  # so OmniAuth derives it per request host — register both.
  valid_redirect_uris = [
    "https://gitlab.${local.fqdn_base}/users/auth/openid_connect/callback",
    "https://gitlab.${var.primary_domain}/users/auth/openid_connect/callback",
  ]
}

# --- Harbor ---------------------------------------------------------------
# Confidential client + a Group Membership mapper so Harbor can read a `groups`
# claim and auto-promote members of `harbor-admins` (harbor.tf config_auth).
resource "keycloak_openid_client" "harbor" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "harbor"
  name      = "Harbor"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  # Harbor derives redirect_uri from its externalURL (LAN host) — LAN login only.
  valid_redirect_uris = [
    "https://harbor.${local.fqdn_base}/c/oidc/callback",
    "https://harbor.${var.primary_domain}/c/oidc/callback",
  ]
}

resource "keycloak_group" "harbor_admins" {
  realm_id = keycloak_realm.homelab.id
  name     = "harbor-admins"
}

# Emit a `groups` claim on the harbor client's tokens (flat name, not full path)
# so Harbor's oidc_groups_claim="groups" + oidc_admin_group="harbor-admins" work.
resource "keycloak_openid_group_membership_protocol_mapper" "harbor_groups" {
  realm_id   = keycloak_realm.homelab.id
  client_id  = keycloak_openid_client.harbor.id
  name       = "groups"
  claim_name = "groups"
  full_path  = false

  add_to_id_token     = true
  add_to_access_token = true
  add_to_userinfo     = true
}

# --- Immich (app-side wired by hand via admin API — see outputs.tf) --------
resource "keycloak_openid_client" "immich" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "immich"
  name      = "Immich"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://immich.${var.primary_domain}/auth/login",
    "https://immich.${var.primary_domain}/user-settings",
    "https://immich.${local.fqdn_base}/auth/login",
    "https://immich.${local.fqdn_base}/user-settings",
    "app.immich:///oauth-callback", # mobile deep link
  ]
}

# --- Paperless ------------------------------------------------------------
resource "keycloak_openid_client" "paperless" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "paperless"
  name      = "Paperless-ngx"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  client_secret         = var.paperless_oidc_client_secret # pinned — see variables.tf (cycle break)

  # allauth provider_id = "keycloak"; callback path has a trailing slash.
  valid_redirect_uris = [
    "https://paperless.${local.fqdn_base}/accounts/oidc/keycloak/login/callback/",
    "https://paperless.${var.primary_domain}/accounts/oidc/keycloak/login/callback/",
  ]
}

# --- Memos (app-side wired by hand via admin API — see outputs.tf) ---------
resource "keycloak_openid_client" "memos" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "memos"
  name      = "Memos"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://memos.${var.primary_domain}/auth/callback",
    "https://memos.${local.fqdn_base}/auth/callback",
  ]
}

# --- Open WebUI (app-side env set on off-cluster LXC 102 — see outputs.tf) -
resource "keycloak_openid_client" "open_webui" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "open-webui"
  name      = "Open WebUI"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true

  valid_redirect_uris = [
    "https://chat.${var.primary_domain}/oauth/oidc/callback",
    "https://chat.${local.fqdn_base}/oauth/oidc/callback",
  ]
}

# --- Reactive Resume ------------------------------------------------------
# Better Auth genericOAuth: callback is <APP_URL>/api/auth/oauth2/callback/custom,
# and only APP_URL (public host) is a trusted origin — public host only.
resource "keycloak_openid_client" "reactive_resume" {
  realm_id  = keycloak_realm.homelab.id
  client_id = "reactive-resume"
  name      = "Reactive Resume"
  enabled   = true

  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  client_secret         = var.reactive_resume_oidc_client_secret # pinned — see variables.tf (cycle break)

  valid_redirect_uris = [
    "https://resume.${var.primary_domain}/api/auth/oauth2/callback/custom",
  ]
}
