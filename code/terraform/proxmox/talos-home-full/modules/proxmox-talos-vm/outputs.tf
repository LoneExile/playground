output "vm_ids" {
  description = "Map of VM names to their IDs"
  value       = { for name, vm in proxmox_vm_qemu.this : name => vm.id }
}

output "vm_ips" {
  description = "Map of VM names to their IPv4 addresses"
  value       = { for name, vm in proxmox_vm_qemu.this : name => vm.default_ipv4_address }
}

output "vm_ip_list" {
  description = "List of all VM IPv4 addresses"
  value       = [for vm in proxmox_vm_qemu.this : vm.default_ipv4_address]
}

output "nodes" {
  description = "The nodes configuration passed in"
  value       = var.nodes
}
