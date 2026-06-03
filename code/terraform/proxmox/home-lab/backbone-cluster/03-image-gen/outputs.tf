output "container_id" {
  description = "LXC VMID"
  value       = proxmox_virtual_environment_container.image_gen.vm_id
}

output "container_ip" {
  description = "Container IP"
  value       = var.ct_ip
}

output "sd_server_url" {
  description = "stable-diffusion.cpp server (API + UI root)"
  value       = "http://${var.ct_ip}:${var.sd_port}/"
}

output "sd_api_a1111" {
  description = "Automatic1111-compatible endpoint — wire this into Open WebUI (Admin → Images → Automatic1111) on the existing LLM stack"
  value       = "http://${var.ct_ip}:${var.sd_port}/sdapi/v1"
}

output "container_root_password" {
  description = "Generated root password for `pct console` fallback. Key-based SSH (injected ssh_public_key) is the primary access path; Debian's sshd disables password login by default."
  value       = random_password.ct.result
  sensitive   = true
}

output "ops_hints" {
  description = "Common operations"
  value = {
    enter_container = "ssh root@${var.proxmox_host} -- pct enter ${var.ct_id}"
    service_status  = "pct exec ${var.ct_id} -- systemctl status sd-server"
    service_logs    = "pct exec ${var.ct_id} -- journalctl -u sd-server -f"
    switch_to_flux  = "pct exec ${var.ct_id} -- sd-switch flux"
    switch_to_turbo = "pct exec ${var.ct_id} -- sd-switch single"
  }
}
