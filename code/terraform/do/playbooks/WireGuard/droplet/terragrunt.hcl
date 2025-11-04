terraform {
  source = "${get_parent_terragrunt_dir()}/../../modules/droplets"
}

include {
  path = find_in_parent_folders("terragrunt.hcl")
}

# Get VPC ID from the vpc module output
dependency "vpc" {
  config_path = "../vpc"
}

inputs = {
  name           = "wireguard-vpn"
  instance_count = 1

  # Minimal spec for WireGuard - 1 vCPU, 1GB RAM
  size   = "s-1vcpu-1gb"

  # Ubuntu 24.04 LTS (latest)
  image  = "ubuntu-24-04-x64"

  # Region should match VPC
  region = "sgp1"

  # Attach to VPC
  vpc_id = dependency.vpc.outputs.vpc_id

  # Assign to project (from root terragrunt.hcl inputs)
  project_id = get_env("DO_PROJECT_ID", "")

  # SSH keys - Add your SSH key IDs here
  # You can get them with: doctl compute ssh-key list
  ssh_keys = ["51735948"] 

  # Enable monitoring for performance tracking
  monitoring = true

  # Enable backups for production use
  backups = false

  # Enable IPv6
  ipv6 = true

  # Tags for organization
  tags = ["wireguard", "vpn", "singapore"]

  # User data to install WireGuard as Central Hub
  user_data = file("${get_terragrunt_dir()}/user-data.sh")

  # Create firewall for WireGuard
  create_firewall = true

  # Inbound rules
  inbound_rules = [
    {
      protocol         = "tcp"
      port_range       = "22"
      source_addresses = ["0.0.0.0/0", "::/0"]
    },
    {
      protocol         = "udp"
      port_range       = "51820"
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  ]

  # Outbound rules - Allow all
  outbound_rules = [
    {
      protocol              = "tcp"
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0", "::/0"]
    },
    {
      protocol              = "udp"
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0", "::/0"]
    }
  ]
}
