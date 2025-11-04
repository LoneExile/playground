resource "random_string" "vpc_name_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "random_integer" "vpc_cidr_second_octet" {
  min = 10
  max = 250
}

resource "digitalocean_vpc" "singapore_vpc" {
  name     = "${var.vpc_name}-${random_string.vpc_name_suffix.result}"
  region   = var.region
  ip_range = var.ip_range != null ? var.ip_range : "10.${random_integer.vpc_cidr_second_octet.result}.0.0/16"

  lifecycle {
    create_before_destroy = true
  }
}
