terraform {
  required_version = ">= 1.9"

  # Remote state on the RustFS S3-compatible backend deployed by stage 00-builder
  # (10.0.10.199:9000, see 00-builder/main.tf). Credentials live in
  # `backend.tfvars` (gitignored); init with:
  #   terraform init -backend-config=backend.tfvars
  #
  # NOTE: this state holds Talos PKI secrets and the kubeconfig/talosconfig —
  # they now live in RustFS. Treat the bucket as sensitive.
  backend "s3" {
    endpoints = {
      s3 = "http://10.0.10.199:9000"
    }
    bucket = "terraform-state"
    key    = "backbone-cluster/01-talos-cluster/terraform.tfstate"
    region = "us-east-1"

    # RustFS isn't real AWS — skip API checks the s3 backend would do at init
    # time, and force path-style addressing (bucket.host vs host/bucket).
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.102"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.9.0-alpha.0" # NOTE: alpha — no stable release available yet
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
