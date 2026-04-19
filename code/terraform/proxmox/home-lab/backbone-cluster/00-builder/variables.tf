# --- Proxmox connection ---
variable "proxmox_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox root password (SSH provisioner)"
  type        = string
  sensitive   = true
}

variable "proxmox_host" {
  description = "Proxmox host IP"
  type        = string
  default     = "10.0.10.10"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

# --- VM config ---
variable "vm_id" {
  description = "VMID for the builder VM"
  type        = number
  default     = 199
}

variable "builder_ip" {
  description = "Static IP for the builder VM"
  type        = string
  default     = "10.0.10.199"
}

variable "builder_gateway" {
  description = "Gateway for the builder VM"
  type        = string
  default     = "10.0.10.1"
}

variable "builder_prefix" {
  description = "Network prefix length"
  type        = number
  default     = 24
}

variable "builder_bridge" {
  description = "Proxmox bridge for builder VM"
  type        = string
  default     = "vmbr0"
}

variable "cpu_cores" {
  description = "CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "os_disk_size" {
  description = "OS disk size in GB"
  type        = number
  default     = 20
}

# --- SSH ---
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "vm_password" {
  description = "VM password (unused by cloud-init, but needed for provider)"
  type        = string
  sensitive   = true
  default     = ""
}

# --- RustFS ---
variable "rustfs_root_user" {
  description = "RustFS root access key"
  type        = string
  default     = "rustfsadmin"
}

variable "rustfs_root_password" {
  description = "RustFS root secret key"
  type        = string
  sensitive   = true
  default     = "rustfsadmin"
}

variable "nameservers" {
  description = "DNS nameservers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}
