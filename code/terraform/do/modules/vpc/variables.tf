variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sgp1"
}

variable "vpc_name" {
  description = "Name prefix for the VPC"
  type        = string
  default     = "singapore-vpc"
}

variable "ip_range" {
  description = "The range of IP addresses for the VPC in CIDR notation"
  type        = string
  default     = null
}
