# Talos Cluster configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules//talos-cluster"
}

dependency "control_plane_vms" {
  config_path = "../control-plane-vms"

  mock_outputs = {
    vm_ips = {
      "talos-control-px-01" = "10.0.10.101"
      "talos-control-px-02" = "10.0.10.102"
      "talos-control-px-03" = "10.0.10.103"
    }
    nodes = {
      "talos-control-px-01" = { target_node = "pve", arc = "amd64" }
      "talos-control-px-02" = { target_node = "pve", arc = "amd64" }
      "talos-control-px-03" = { target_node = "pve", arc = "amd64" }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "worker_vms" {
  config_path = "../worker-vms"
  skip_outputs = true

  mock_outputs = {
    vm_ips = {}
    nodes  = {}
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  # Proxmox credentials (for provider)
  pm_host             = local.env_vars.locals.pm_host
  pm_api_token_id     = local.env_vars.locals.pm_api_token_id
  pm_api_token_secret = local.env_vars.locals.pm_api_token_secret

  # Cluster configuration
  cluster_name       = "talos-proxmox-cluster"
  talos_version      = local.env_vars.locals.talos_version
  kubernetes_version = local.env_vars.locals.kubernetes_version
  talos_image_url    = local.env_vars.locals.talos_image_url

  # Network configuration
  vip_ip       = local.env_vars.locals.vip_ip
  cluster_cidr = local.env_vars.locals.cluster_cidr
  dns_domain   = local.env_vars.locals.dns_domain

  # Initial control plane IP for bootstrap
  initial_control_plane_ip = dependency.control_plane_vms.outputs.vm_ips["talos-control-px-01"]

  # Control plane nodes with their IPs
  control_plane_nodes = {
    for name, config in dependency.control_plane_vms.outputs.nodes : name => {
      ip  = dependency.control_plane_vms.outputs.vm_ips[name]
      arc = config.arc
    }
  }

  # Worker nodes - empty for now
  worker_nodes = {}
}
