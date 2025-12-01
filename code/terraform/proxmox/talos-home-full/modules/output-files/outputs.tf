output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = local_file.kubeconfig.filename
}

output "secrets_path" {
  description = "Path to the secrets file"
  value       = local_file.secrets.filename
}
