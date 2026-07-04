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
  # login_theme references the "homelab" theme, which only exists on the server
  # once the pod has rolled with the ConfigMap mounted — depend on the release so
  # the provider's theme validation doesn't race the rollout.
  depends_on = [helm_release.keycloak]

  realm        = "homelab"
  enabled      = true
  display_name = "Homelab"

  # Custom login page — theme files in themes/homelab/, shipped to the pod by
  # keycloak-theme.tf and mounted via values/keycloak.yaml.
  login_theme = "homelab"
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

  # Realm access gate: only the owner's email may complete a GitHub login into
  # this realm. Runs on EVERY broker login (post-broker), so it also blocks any
  # account that already brokered in — not just first logins. Flow below.
  post_broker_login_flow_alias = keycloak_authentication_flow.restrict_owner.alias
}

# =============================================================================
# Realm access restriction — "only the owner may enter the homelab realm"
# =============================================================================
# Closes the hole that the GitHub IdP admits ANY GitHub account into the realm.
# A CONDITIONAL subflow denies access unless the authenticated user's `email`
# equals var.homelab_owner_email. For the owner the condition is FALSE (the email
# matches), so the subflow is skipped and login proceeds; for everyone else the
# condition is TRUE (email != owner, via `not = true`) → Deny Access.
#
# Config keys are exact (from Keycloak source ConditionalUserAttributeValueFactory):
# attribute_name / attribute_expected_value / not. The match is case-sensitive.
#
# TERMINAL ALLOW (critical): a Keycloak flow MUST end with an execution that
# SUCCEEDS, or the whole flow throws AuthenticationFlowException ("no successful
# execution") and login dies with error=invalid_user_credentials — BEFORE any
# redirect back to the app. For the owner the deny subflow is skipped, so without
# a trailing success the flow is empty → every homelab app OIDC login breaks on a
# fresh GitHub re-broker (cached SSO sessions mask it until logout). The
# `allow-access-authenticator` below is that required terminal success: the owner
# reaches it (subflow skipped) and passes; a non-owner is denied inside the
# subflow and the flow fails before ever reaching it.
#
# LOCKOUT NOTE: the deny only fires for non-matching emails, so a correct
# owner_email can't lock the owner out. If it's ever wrong (e.g. GitHub email
# change / wrong case), OIDC breaks for every homelab app — recover via any app's
# local admin, or fix the flow in the master-realm Keycloak admin console.
resource "keycloak_authentication_flow" "restrict_owner" {
  realm_id = keycloak_realm.homelab.id
  alias    = "restrict-to-owner"
}

resource "keycloak_authentication_subflow" "restrict_owner_check" {
  realm_id          = keycloak_realm.homelab.id
  alias             = "restrict-to-owner-check"
  parent_flow_alias = keycloak_authentication_flow.restrict_owner.alias
  requirement       = "CONDITIONAL"
}

resource "keycloak_authentication_execution" "restrict_owner_condition" {
  realm_id          = keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.restrict_owner_check.alias
  authenticator     = "conditional-user-attribute"
  requirement       = "REQUIRED"
}

resource "keycloak_authentication_execution_config" "restrict_owner_condition" {
  realm_id     = keycloak_realm.homelab.id
  execution_id = keycloak_authentication_execution.restrict_owner_condition.id
  alias        = "restrict-to-owner-email"
  config = {
    attribute_name           = "email"
    attribute_expected_value = var.homelab_owner_email
    not                      = "true" # deny when email != owner
  }
}

# depends_on forces this execution to be created AFTER the condition so it sits
# below it in the subflow (executions run in creation order); the deny must run
# only after the condition has been evaluated.
resource "keycloak_authentication_execution" "restrict_owner_deny" {
  realm_id          = keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_subflow.restrict_owner_check.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution.restrict_owner_condition]
}

# Terminal success at the TOP level of restrict-to-owner (NOT inside the subflow).
# Sits AFTER the conditional-deny subflow (creation order → execution order, hence
# the depends_on). The owner skips the subflow and lands here → SUCCESS → the flow
# succeeds and login continues. A non-owner is denied inside the subflow, which
# fails the flow before this ever runs. Without this the owner path is empty and
# the flow throws AuthenticationFlowException (see header).
resource "keycloak_authentication_execution" "restrict_owner_allow" {
  realm_id          = keycloak_realm.homelab.id
  parent_flow_alias = keycloak_authentication_flow.restrict_owner.alias
  authenticator     = "allow-access-authenticator"
  requirement       = "REQUIRED"

  depends_on = [keycloak_authentication_execution.restrict_owner_deny]
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
