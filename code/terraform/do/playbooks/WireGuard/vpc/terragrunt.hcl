terraform {
  source = "${get_parent_terragrunt_dir()}/../../modules/vpc"
}

include {
  path = find_in_parent_folders("terragrunt.hcl")
}

inputs = {
  region   = "sgp1"
  vpc_name = "wireguard-vpc"
  ip_range = "10.100.0.0/16"
}
