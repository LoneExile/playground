terraform {
  required_version = ">= 1.9"

  # Local state by default (same as stage 00-builder / 01-talos-cluster). This
  # stage is standalone Proxmox infra and shares state with nothing.
  #
  # To use the RustFS S3 backend instead (like 02-helm-stack), uncomment and
  # `terraform init -backend-config=backend.tfvars`:
  #
  # backend "s3" {
  #   endpoints                   = { s3 = "http://10.0.10.199:9000" }
  #   bucket                      = "terraform-state"
  #   key                         = "backbone-cluster/03-image-gen/terraform.tfstate"
  #   region                      = "us-east-1"
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  # }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.102"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
