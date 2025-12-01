variable "vm_ips" {
  description = "List of VM IP addresses to wait for"
  type        = list(string)
}

variable "ipv4_subnet" {
  description = "IPv4 subnet for the VMs"
  type        = string
}

variable "talos_api_port" {
  description = "Talos API port"
  type        = number
  default     = 50000
}

variable "max_retries" {
  description = "Maximum number of retries"
  type        = number
  default     = 60
}

variable "retry_interval" {
  description = "Seconds between retries"
  type        = number
  default     = 5
}
