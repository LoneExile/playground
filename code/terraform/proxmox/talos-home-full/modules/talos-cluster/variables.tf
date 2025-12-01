variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
}

variable "talos_version" {
  description = "Version of Talos OS"
  type        = string
}

variable "kubernetes_version" {
  description = "Version of Kubernetes"
  type        = string
}

variable "talos_image_url" {
  description = "URL of the Talos OS image"
  type        = string
}

variable "vip_ip" {
  description = "Virtual IP address for the cluster"
  type        = string
}

variable "cluster_cidr" {
  description = "CIDR block for the cluster network"
  type        = string
}

variable "initial_control_plane_ip" {
  description = "IP address of the first control plane node for bootstrapping"
  type        = string
}

variable "control_plane_nodes" {
  description = "Map of control plane node names to their configuration"
  type = map(object({
    ip  = string
    arc = optional(string, "amd64")
  }))
}

variable "worker_nodes" {
  description = "Map of worker node names to their configuration"
  type = map(object({
    ip  = string
    arc = optional(string, "amd64")
  }))
  default = {}
}

variable "install_disk" {
  description = "Disk to install Talos on"
  type        = string
  default     = "/dev/vda"
}

variable "network_interface" {
  description = "Network interface name"
  type        = string
  default     = "ens18"
}

variable "allow_scheduling_on_control_planes" {
  description = "Allow scheduling pods on control plane nodes"
  type        = bool
  default     = true
}

variable "disable_kube_proxy" {
  description = "Disable kube-proxy"
  type        = bool
  default     = true
}

variable "enable_discovery" {
  description = "Enable cluster discovery"
  type        = bool
  default     = false
}

variable "cni_name" {
  description = "CNI plugin name"
  type        = string
  default     = "none"
}

variable "dns_domain" {
  description = "Cluster DNS domain"
  type        = string
  default     = "cluster.local"
}

variable "pod_subnets" {
  description = "Pod subnet CIDRs"
  type        = list(string)
  default     = ["10.244.0.0/16"]
}

variable "service_subnets" {
  description = "Service subnet CIDRs"
  type        = list(string)
  default     = ["10.96.0.0/16"]
}

variable "max_pods" {
  description = "Maximum pods per node"
  type        = number
  default     = 512
}

variable "enable_kubeprism" {
  description = "Enable KubePrism"
  type        = bool
  default     = true
}

variable "kubeprism_port" {
  description = "KubePrism port"
  type        = number
  default     = 7445
}

variable "extra_cert_sans" {
  description = "Additional SANs for the API server certificate"
  type        = list(string)
  default     = []
}

variable "sysctls" {
  description = "Sysctl settings"
  type        = map(string)
  default = {
    "net.ipv4.neigh.default.gc_thresh1" = "4096"
    "net.ipv4.neigh.default.gc_thresh2" = "8192"
    "net.ipv4.neigh.default.gc_thresh3" = "16384"
  }
}

variable "kernel_modules" {
  description = "Kernel modules to load"
  type = list(object({
    name       = string
    parameters = optional(list(string), [])
  }))
  default = [
    { name = "openvswitch" },
    { name = "drbd", parameters = ["usermode_helper=disabled"] },
    { name = "zfs" },
    { name = "spl" },
    { name = "vfio_pci" },
    { name = "vfio_iommu_type1" }
  ]
}

variable "machine_files" {
  description = "Files to create on the machine"
  type = list(object({
    content = string
    path    = string
    op      = string
  }))
  default = [
    {
      content = <<-EOT
        [plugins]
          [plugins."io.containerd.cri.v1.runtime"]
            device_ownership_from_security_context = true
      EOT
      path    = "/etc/cri/conf.d/20-customization.part"
      op      = "create"
    }
  ]
}
