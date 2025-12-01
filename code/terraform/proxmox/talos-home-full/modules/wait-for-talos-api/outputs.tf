output "ready" {
  description = "Indicates all Talos APIs are ready"
  value       = true
  depends_on  = [null_resource.wait_for_talos_api]
}
