output "gateway_ip" {
  description = "External MetalLB IP assigned to backbone-gateway"
  value       = var.gateway_external_ip
}

output "service_urls" {
  description = "HTTPS URLs for each app routed through the gateway"
  value = {
    for app, host in local.hostnames : app => "https://${host}"
  }
}

output "grafana_mcp_token" {
  description = "Grafana service-account token for the standalone mcp-grafana server (GRAFANA_SERVICE_ACCOUNT_TOKEN). Retrieve with `terraform output -raw grafana_mcp_token`."
  value       = grafana_service_account_token.claude_mcp.key
  sensitive   = true
}

output "grafana_mcp_urls" {
  description = "Grafana base URLs mcp-grafana can target (GRAFANA_URL) — both reach the same Grafana"
  value = {
    lan    = "https://${local.hostnames.grafana}"
    public = "https://grafana.${var.primary_domain}"
  }
}

output "openbao_oidc_client_secret" {
  description = "Keycloak `openbao` client secret. Feed to OpenBao's oidc auth config (auth/oidc/config oidc_client_secret). Retrieve with `terraform output -raw openbao_oidc_client_secret`."
  value       = keycloak_openid_client.openbao.client_secret
  sensitive   = true
}

# Client secrets for the three apps whose OIDC config lives outside Terraform
# (open-webui on off-cluster LXC 102; immich + memos store it in their DB). Wire
# them by hand — see the "Homelab — Keycloak OIDC rollout" ZenNote. Retrieve with
# `terraform output -raw <name>`.
output "immich_oidc_client_secret" {
  description = "Keycloak `immich` client secret. Set in Immich admin OAuth settings (or its config file)."
  value       = keycloak_openid_client.immich.client_secret
  sensitive   = true
}

output "memos_oidc_client_secret" {
  description = "Keycloak `memos` client secret. Set in Memos SSO identity provider (Settings → SSO / API)."
  value       = keycloak_openid_client.memos.client_secret
  sensitive   = true
}

output "open_webui_oidc_client_secret" {
  description = "Keycloak `open-webui` client secret. Set OAUTH_CLIENT_SECRET on the Open WebUI container (LXC 102)."
  value       = keycloak_openid_client.open_webui.client_secret
  sensitive   = true
}

output "cloudflare_wildcard_record" {
  description = "Cloudflare A record managed by this stage"
  value = {
    name    = "*.${var.subdomain}.${var.primary_domain}"
    content = var.gateway_external_ip
    ttl     = cloudflare_record.wildcard_home.ttl
  }
}
