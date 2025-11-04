output "droplet_ids" {
  description = "The IDs of the created Droplets"
  value       = digitalocean_droplet.this[*].id
}

output "droplet_urns" {
  description = "The uniform resource names of the created Droplets"
  value       = digitalocean_droplet.this[*].urn
}

output "droplet_names" {
  description = "The names of the created Droplets"
  value       = digitalocean_droplet.this[*].name
}

output "droplet_ips" {
  description = "The IPv4 addresses of the created Droplets"
  value       = digitalocean_droplet.this[*].ipv4_address
}

output "droplet_ipv6_ips" {
  description = "The IPv6 addresses of the created Droplets"
  value       = digitalocean_droplet.this[*].ipv6_address
}

output "volume_ids" {
  description = "The IDs of the created volumes"
  value       = var.create_volume ? digitalocean_volume.this[*].id : []
}

output "firewall_id" {
  description = "The ID of the created firewall"
  value       = var.create_firewall ? digitalocean_firewall.this[0].id : null
}
