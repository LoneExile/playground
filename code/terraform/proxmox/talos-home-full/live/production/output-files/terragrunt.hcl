# Output Files configuration - saves kubeconfig and secrets
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${dirname(find_in_parent_folders("root.hcl"))}/../modules//output-files"
}

dependency "talos_cluster" {
  config_path = "../talos-cluster"

  mock_outputs = {
    kubeconfig_raw  = "mock-kubeconfig"
    machine_secrets = {
      cluster = {
        id     = "mock-id"
        secret = "mock-secret"
      }
      secrets = {
        bootstrap_token             = "mock-token"
        secretbox_encryption_secret = "mock-secret"
        aescbc_encryption_secret    = "mock-secret"
      }
      trustdinfo = {
        token = "mock-token"
      }
      certs = {
        os = {
          cert = "mock-cert"
          key  = "mock-key"
        }
        k8s = {
          cert = "mock-cert"
          key  = "mock-key"
        }
        k8s_aggregator = {
          cert = "mock-cert"
          key  = "mock-key"
        }
        k8s_serviceaccount = {
          key = "mock-key"
        }
        etcd = {
          cert = "mock-cert"
          key  = "mock-key"
        }
      }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  # Proxmox credentials (for provider)
  pm_host             = local.env_vars.locals.pm_host
  pm_api_token_id     = local.env_vars.locals.pm_api_token_id
  pm_api_token_secret = local.env_vars.locals.pm_api_token_secret

  kubeconfig_raw  = dependency.talos_cluster.outputs.kubeconfig_raw
  machine_secrets = dependency.talos_cluster.outputs.machine_secrets
  output_dir      = get_terragrunt_dir()
}
