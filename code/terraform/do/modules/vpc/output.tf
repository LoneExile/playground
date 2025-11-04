output "vpc_id" {
  value = digitalocean_vpc.singapore_vpc.id
}

output "vpc_name" {
  value = digitalocean_vpc.singapore_vpc.name
}

output "vpc_name_suffix" {
  value = random_string.vpc_name_suffix.result
}
