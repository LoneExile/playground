output "builder_ip" {
  description = "Builder VM static IP"
  value       = var.builder_ip
}

output "rustfs_endpoint" {
  description = "RustFS S3 API endpoint"
  value       = "http://${var.builder_ip}:9000"
}

output "rustfs_console" {
  description = "RustFS web console URL"
  value       = "http://${var.builder_ip}:9001"
}

output "rustfs_access_key" {
  description = "RustFS access key for S3 backend"
  value       = var.rustfs_root_user
}
