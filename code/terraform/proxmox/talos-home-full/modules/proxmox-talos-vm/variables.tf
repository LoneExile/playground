variable "nodes" {
  description = "Map of node names to their configuration"
  type = map(object({
    target_node = string
    arc         = optional(string, "amd64")
  }))
}

variable "cpu_cores" {
  description = "Number of CPU cores per VM"
  type        = number
  default     = 4
}

variable "cpu_sockets" {
  description = "Number of CPU sockets per VM"
  type        = number
  default     = 1
}

variable "cpu_type" {
  description = "CPU type for VMs"
  type        = string
  default     = "host"
}

variable "memory" {
  description = "RAM allocation in MB"
  type        = number
  default     = 20480
}

variable "os_disk_size" {
  description = "Size of the OS disk"
  type        = string
  default     = "40G"
}

variable "storage_disk_size" {
  description = "Size of the storage disk"
  type        = string
  default     = "300G"
}

variable "storage" {
  description = "Proxmox storage location"
  type        = string
  default     = "local-lvm"
}

variable "cdrom_iso" {
  description = "Path to the ISO in Proxmox storage"
  type        = string
}

variable "network_bridge" {
  description = "Network bridge to use"
  type        = string
  default     = "vmbr0"
}

variable "network_model" {
  description = "Network model"
  type        = string
  default     = "virtio"
}

variable "vm_state" {
  description = "State of the VM (running/stopped)"
  type        = string
  default     = "running"
}

variable "agent" {
  description = "Enable QEMU guest agent"
  type        = number
  default     = 1
}

variable "skip_ipv6" {
  description = "Skip IPv6 configuration"
  type        = bool
  default     = true
}

variable "boot_order" {
  description = "Boot order for the VM"
  type        = string
  default     = "order=virtio0;net0;ide2"
}
