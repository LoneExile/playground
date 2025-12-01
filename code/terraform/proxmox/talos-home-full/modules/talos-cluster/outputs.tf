output "kubeconfig_raw" {
  description = "Raw kubeconfig content"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration"
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "machine_secrets" {
  description = "Talos machine secrets"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "cluster_name" {
  description = "Name of the cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Cluster API endpoint"
  value       = "https://${var.vip_ip}:6443"
}
