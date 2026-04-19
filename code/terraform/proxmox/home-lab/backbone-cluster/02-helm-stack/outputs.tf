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

output "cloudflare_wildcard_record" {
  description = "Cloudflare A record managed by this stage"
  value = {
    name    = "*.${var.subdomain}.${var.primary_domain}"
    content = var.gateway_external_ip
    ttl     = cloudflare_record.wildcard_home.ttl
  }
}
