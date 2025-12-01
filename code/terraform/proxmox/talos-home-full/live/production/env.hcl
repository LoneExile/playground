# Production environment configuration
locals {
  environment = "production"

  # Proxmox Configuration
  pm_host             = "https://10.0.10.10:8006/api2/json"
  pm_api_token_id     = "terraform-prov@pve!mytoken"
  pm_api_token_secret = get_env("PM_API_TOKEN_SECRET", "")

  # Proxmox Target
  target_node = "pve"

  # Talos Configuration
  talos_image_url    = "factory.talos.dev/nocloud-installer/01e24756d738067f536497ff4d9c6a3dd78f267886a2790ed0be43f61a7d328f:v1.11.5"
  talos_version      = "v1.11.5"
  kubernetes_version = "v1.33.3"
  cdrom_iso          = "local:iso/cozy-nocloud-amd64-1.11.5-agent.iso"

  # Network Configuration
  vip_ip       = "10.0.10.100"
  ipv4_cidr    = "10.0.10.0/24"
  cluster_cidr = "10.0.10.0/24"
  dns_domain   = "maxcloud.local"

  # Control Plane Configuration
  control_plane_ram               = 20480
  control_plane_cpu_core          = 4
  control_plane_cpu_socket        = 1
  control_plane_os_disk_size      = "40G"
  control_plane_storage_disk_size = "500G"
  control_plane_proxmox_storage   = "local-lvm"

  # Worker Configuration
  worker_ram               = 20480
  worker_cpu_core          = 4
  worker_cpu_socket        = 1
  worker_os_disk_size      = "40G"
  worker_storage_disk_size = "500G"
  worker_proxmox_storage   = "local-lvm"

  # Node Definitions
  control_plane_nodes = {
    "talos-control-px-01" = {
      target_node = local.target_node
      arc         = "amd64"
    }
    "talos-control-px-02" = {
      target_node = local.target_node
      arc         = "amd64"
    }
    "talos-control-px-03" = {
      target_node = local.target_node
      arc         = "amd64"
    }
  }

  # Uncomment to add worker nodes
  worker_nodes = {
    # "talos-worker-01" = {
    #   target_node = local.target_node
    #   arc         = "amd64"
    # }
    # "talos-worker-02" = {
    #   target_node = local.target_node
    #   arc         = "amd64"
    # }
    # "talos-worker-03" = {
    #   target_node = local.target_node
    #   arc         = "amd64"
    # }
  }
}
