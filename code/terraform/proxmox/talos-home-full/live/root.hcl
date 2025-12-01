# Root Terragrunt configuration
# This file contains common configuration that is included by all child configurations

locals {
  # Parse the file path to get environment information
  parsed = regex(".*/live/(?P<env>[^/]+)/.*", get_terragrunt_dir())
  env    = local.parsed.env
}

# Configure local backend for state storage
# For production, consider using a remote backend like S3, GCS, or Terraform Cloud
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_parent_terragrunt_dir()}/state/${local.env}/${path_relative_to_include()}/terraform.tfstate"
  }
}

# Generate provider configuration
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.1.0"

      required_providers {
        proxmox = {
          source  = "telmate/proxmox"
          version = "3.0.2-rc03"
        }
        talos = {
          source  = "siderolabs/talos"
          version = "0.9.0-alpha.0"
        }
        local = {
          source  = "hashicorp/local"
          version = "2.5.3"
        }
        null = {
          source  = "hashicorp/null"
          version = ">= 3.0.0"
        }
      }
    }

    provider "proxmox" {
      pm_api_url          = var.pm_host
      pm_api_token_id     = var.pm_api_token_id
      pm_api_token_secret = var.pm_api_token_secret
      pm_tls_insecure     = true
    }
  EOF
}

# Generate common variables
generate "common_variables" {
  path      = "common_variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    variable "pm_host" {
      description = "Proxmox host URL"
      type        = string
    }

    variable "pm_api_token_id" {
      description = "Proxmox API Token ID"
      type        = string
    }

    variable "pm_api_token_secret" {
      description = "Proxmox API Token Secret"
      type        = string
      sensitive   = true
    }
  EOF
}

# Inputs that are common across all configurations
inputs = {
  # These will be overridden by environment-specific env.hcl files
}
