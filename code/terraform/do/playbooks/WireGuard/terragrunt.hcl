remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }

    bucket = get_env("DO_SPACES_BUCKET")
    key    = "${path_relative_to_include()}/wireguard/terraform.tfstate"

    # Deactivate AWS-specific checks for DigitalOcean Spaces
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    region                      = "ap-southeast-1"
    use_lockfile                = true
  }
}

# Generate provider configurations
generate "provider" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 0.12"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.68.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }
}

provider "digitalocean" {
  token     = var.do_token
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

provider "random" {}
EOF
}

# Generate variables file
generate "common_variables" {
  path      = "common_variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
variable "do_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "spaces_access_id" {
  description = "DigitalOcean Spaces Access ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "spaces_secret_key" {
  description = "DigitalOcean Spaces Secret Key"
  type        = string
  sensitive   = true
  default     = ""
}
EOF
}

# Define inputs that are common across all modules
inputs = {
  do_token          = get_env("DO_TOKEN", "")
  project_id        = get_env("DO_PROJECT_ID", "")
  spaces_access_id  = get_env("DO_SPACES_ACCESS_ID", "")
  spaces_secret_key = get_env("DO_SPACES_SECRET_KEY", "")
}
