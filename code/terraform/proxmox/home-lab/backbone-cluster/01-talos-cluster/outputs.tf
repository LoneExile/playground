output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = local_sensitive_file.kubeconfig.filename
}

output "talosconfig_path" {
  description = "Path to the talosconfig file"
  value       = local_sensitive_file.talosconfig.filename
}

output "control_plane_ips" {
  description = "Map of node name to IP"
  value       = { for name, node in var.nodes : name => node.ip }
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (VIP)"
  value       = local.cluster_endpoint
}

output "cluster_name" {
  description = "Talos cluster name"
  value       = var.cluster_name
}
