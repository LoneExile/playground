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

output "cloudflare_wildcard_record" {
  description = "Cloudflare A record managed by this stage"
  value = {
    name    = "*.${var.subdomain}.${var.primary_domain}"
    content = var.gateway_external_ip
    ttl     = cloudflare_record.wildcard_home.ttl
  }
}
