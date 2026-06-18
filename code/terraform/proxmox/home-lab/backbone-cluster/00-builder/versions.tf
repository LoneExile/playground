terraform {
  required_version = ">= 1.9"

  # Remote state on the RustFS S3-compatible backend this very stage deploys
  # (10.0.10.199:9000, see main.tf). Credentials live in `backend.tfvars`
  # (gitignored); init with:
  #   terraform init -backend-config=backend.tfvars
  #
  # WARNING: this is the bootstrap stage — it builds the VM that hosts this
  # backend. If that VM is destroyed, the state needed to rebuild it lives only
  # in the dead VM. Keep an out-of-band copy of this state (e.g. pull it with
  # `terraform state pull > builder-state.backup.json`) before any destroy.
  backend "s3" {
    endpoints = {
      s3 = "http://10.0.10.199:9000"
    }
    bucket = "terraform-state"
    key    = "backbone-cluster/00-builder/terraform.tfstate"
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
      version = "~> 0.97"
    }
  }
}
