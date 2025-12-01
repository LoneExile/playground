# Control Plane VMs configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules//proxmox-talos-vm"
}

inputs = {
  # Proxmox credentials
  pm_host             = local.env_vars.locals.pm_host
  pm_api_token_id     = local.env_vars.locals.pm_api_token_id
  pm_api_token_secret = local.env_vars.locals.pm_api_token_secret

  # Node configuration
  nodes = local.env_vars.locals.control_plane_nodes

  # VM Resources
  cpu_cores   = local.env_vars.locals.control_plane_cpu_core
  cpu_sockets = local.env_vars.locals.control_plane_cpu_socket
  memory      = local.env_vars.locals.control_plane_ram

  # Storage
  os_disk_size      = local.env_vars.locals.control_plane_os_disk_size
  storage_disk_size = local.env_vars.locals.control_plane_storage_disk_size
  storage           = local.env_vars.locals.control_plane_proxmox_storage

  # Boot
  cdrom_iso = local.env_vars.locals.cdrom_iso
}
