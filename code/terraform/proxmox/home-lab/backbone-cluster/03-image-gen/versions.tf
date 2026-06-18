terraform {
  required_version = ">= 1.9"

  # Remote state on the RustFS S3-compatible backend deployed by stage 00-builder
  # (10.0.10.199:9000, see 00-builder/main.tf). Credentials live in
  # `backend.tfvars` (gitignored); init with:
  #   terraform init -backend-config=backend.tfvars
  backend "s3" {
    endpoints = {
      s3 = "http://10.0.10.199:9000"
    }
    bucket = "terraform-state"
    key    = "backbone-cluster/03-image-gen/terraform.tfstate"
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
