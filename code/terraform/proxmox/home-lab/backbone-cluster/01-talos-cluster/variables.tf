# --- Proxmox connection ---
variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (e.g., 'root@pam!terraform')"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox root password (used for SSH provisioner in bpg/proxmox)"
  type        = string
  sensitive   = true
}

variable "proxmox_host" {
  description = "Proxmox host IP"
  type        = string
  default     = "10.0.10.10"
}

variable "proxmox_node" {
  description = "Proxmox cluster node name"
  type        = string
  default     = "pve"
}

variable "proxmox_storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

# --- Cluster ---
variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
  default     = "backbone-cluster"
}

variable "talos_version" {
  description = "Talos OS version"
  type        = string
  default     = "v1.12.6"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "v1.35.0"
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic ID (single schematic for all nodes; per-node IPs come from machineconfig)"
  type        = string
  default     = "19b1e20f9a26f178d836505229c1fdbad0347f145a440af17044c2f113c65870"
}

# Separate schematic for workers that need Intel-specific extensions (i915, intel-ucode).
variable "worker_schematic_id" {
  description = "Talos Image Factory schematic ID used by worker nodes"
  type        = string
  default     = "d5ca60beb17607256bf0986594c0040077c18f78f4b12b1d90a11a3bdee8244c"
}

# --- Second Proxmox host (NAS / worker host) ---
variable "proxmox_host_nas" {
  description = "Secondary Proxmox host IP (currently hosts NFS + Intel iGPU worker)"
  type        = string
  default     = "192.168.1.179"
}

variable "proxmox_node_nas" {
  description = "Proxmox node name on the NAS host"
  type        = string
  default     = "proxmox"
}

variable "proxmox_storage_nas" {
  description = "Storage pool on the NAS host for VM disks"
  type        = string
  default     = "SSD-01"
}

variable "proxmox_iso_storage_nas" {
  description = "Storage pool on the NAS host for ISOs"
  type        = string
  default     = "local"
}

variable "proxmox_api_token_id_nas" {
  description = "API token ID on the NAS host"
  type        = string
  default     = "root@pam!terraform"
}

variable "proxmox_api_token_secret_nas" {
  description = "API token secret on the NAS host"
  type        = string
  sensitive   = true
}

variable "proxmox_password_nas" {
  description = "Root password on the NAS host (bpg SSH provisioner)"
  type        = string
  sensitive   = true
}

# --- Network (flat, single NIC on vmbr0) ---
variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "10.0.10.1"
}

variable "network_prefix" {
  description = "Network prefix length"
  type        = number
  default     = 24
}

variable "network_bridge" {
  description = "Proxmox bridge"
  type        = string
  default     = "vmbr0"
}

variable "vip" {
  description = "Kubernetes API VIP"
  type        = string
  default     = "10.0.10.204"
}

variable "nameservers" {
  description = "DNS nameservers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# --- Nodes ---
variable "nodes" {
  description = "Map of node name to IP and MAC address"
  type = map(object({
    ip          = string
    mac_address = string
  }))
  default = {
    "bb-ctrl-01" = { ip = "10.0.10.201", mac_address = "BC:24:11:BB:60:01" }
    "bb-ctrl-02" = { ip = "10.0.10.202", mac_address = "BC:24:11:BB:61:02" }
    "bb-ctrl-03" = { ip = "10.0.10.203", mac_address = "BC:24:11:BB:62:03" }
  }
}

variable "bootstrap_node" {
  description = "Node name for etcd bootstrap"
  type        = string
  default     = "bb-ctrl-01"
}

# Worker nodes — optional, scheduled via nodeSelector (e.g. GPU workloads).
# VLAN 2 tagging carries the NIC onto 10.0.10.0/24 even though the NAS uplink
# is untagged 192.168.1.0/24. UniFi DHCP reservation keeps the IP stable on
# first boot before machineconfig applies the static address.
variable "worker_nodes" {
  description = "Map of worker node name to VM config (empty map = no workers)"
  type = map(object({
    ip          = string
    mac_address = string
    vm_id       = number
    gpu_pci     = string # PCI address to pass through, or "" for none
  }))
  default = {
    "bb-worker-01" = {
      ip          = "10.0.10.205"
      mac_address = "BC:24:11:BB:64:01"
      vm_id       = 300
      gpu_pci     = "0000:00:02.0"
    }
  }
}

# --- VM sizing ---
variable "cpu_cores" {
  description = "CPU cores per VM"
  type        = number
  default     = 4
}

variable "memory_mb" {
  description = "RAM per VM in MB"
  type        = number
  default     = 8192
}

variable "os_disk_size" {
  description = "OS disk size in GB"
  type        = number
  default     = 50
}

# --- VM base ID ---
variable "vm_id_base" {
  description = "Starting VMID for the cluster VMs (bb-ctrl-01=base, 02=base+1, 03=base+2)"
  type        = number
  default     = 200
}

# --- Unused but kept for shared tfvars compatibility ---
variable "ssh_public_key" {
  description = "SSH public key (used by other stages, kept for shared tfvars)"
  type        = string
  default     = ""
}

variable "vm_password" {
  description = "VM password (used by other stages, kept for shared tfvars)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vm_password_hash" {
  description = "VM password hash (used by other stages, kept for shared tfvars)"
  type        = string
  default     = ""
}

variable "rustfs_root_user" {
  description = "RustFS user (used by other stages, kept for shared tfvars)"
  type        = string
  default     = ""
}

variable "rustfs_root_password" {
  description = "RustFS password (used by other stages, kept for shared tfvars)"
  type        = string
  sensitive   = true
  default     = ""
}
