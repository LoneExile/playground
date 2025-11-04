variable "name" {
  description = "The name of the Droplet"
  type        = string
}

variable "instance_count" {
  description = "The number of Droplet instances to create"
  type        = number
  default     = 1
}

variable "size" {
  description = "The size of the Droplet"
  type        = string
}

variable "image" {
  description = "The image ID or slug for the Droplet"
  type        = string
}

variable "region" {
  description = "The region to deploy the Droplet in"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC to deploy the Droplet in"
  type        = string
  default     = null
}

variable "tags" {
  description = "A list of tags to apply to the Droplet"
  type        = list(string)
  default     = []
}

variable "ssh_keys" {
  description = "A list of SSH key IDs or fingerprints to add to the Droplet"
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "User data to be used on the Droplet"
  type        = string
  default     = null
}

variable "backups" {
  description = "Enable backups for the Droplet"
  type        = bool
  default     = false
}

variable "monitoring" {
  description = "Enable monitoring for the Droplet"
  type        = bool
  default     = true
}

variable "ipv6" {
  description = "Enable IPv6 for the Droplet"
  type        = bool
  default     = false
}

variable "resize_disk" {
  description = "Resize the disk when resizing the Droplet"
  type        = bool
  default     = true
}

variable "droplet_agent" {
  description = "Enable the DigitalOcean agent for the Droplet"
  type        = bool
  default     = true
}

variable "graceful_shutdown" {
  description = "Enable graceful shutdown for the Droplet"
  type        = bool
  default     = false
}

variable "create_firewall" {
  description = "Whether to create a firewall for the Droplet"
  type        = bool
  default     = false
}

variable "inbound_rules" {
  description = "List of inbound rules for the firewall"
  type = list(object({
    protocol         = string
    port_range       = string
    source_addresses = list(string)
  }))
  default = []
}

variable "outbound_rules" {
  description = "List of outbound rules for the firewall"
  type = list(object({
    protocol              = string
    port_range            = string
    destination_addresses = list(string)
  }))
  default = []
}

variable "create_volume" {
  description = "Whether to create a volume for the Droplet"
  type        = bool
  default     = false
}

variable "volume_name" {
  description = "The name of the volume"
  type        = string
  default     = ""
}

variable "volume_size" {
  description = "The size of the volume in GB"
  type        = number
  default     = 10
}

variable "volume_filesystem_type" {
  description = "The filesystem type for the volume"
  type        = string
  default     = "ext4"
}

variable "volume_description" {
  description = "The description of the volume"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "The ID of the project to assign the droplet to"
  type        = string
  default     = null
}
