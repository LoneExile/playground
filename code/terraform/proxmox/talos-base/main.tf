terraform {
  required_version = ">= 1.1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc03"
    }
    talos = {
      source = "siderolabs/talos"
      version = "0.9.0-alpha.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}

variable "PM_HOST" {
  type        = string
  description = "Proxmox host URL"
}

variable "PM_API_TOKEN_ID" {
  type        = string
  description = "Proxmox API Token ID"
}

variable "PM_API_TOKEN_SECRET" {
  type        = string
  description = "Proxmox API Token Secret"
  sensitive   = true
}

variable "VIP_IP" {
  description = "Virtual IP address for the cluster"
  type        = string
}

variable "IPV4_CIDR" {
  description = "IPv4 CIDR for the network"
  type        = string
}

variable "TALOS_IMAGE_URL" {
  description = "URL of the Talos OS image"
  type        = string
}

variable "TALOS_VERSION" {
  description = "Version of Talos OS to use"
  type        = string
}

variable "CD_ROM" {
  description = "Path to the custom Talos ISO in Proxmox storage"
  type        = string
}

variable "CLUSTER_CIDR" {
  description = "CIDR block for the cluster network"
  type        = string
}

variable "KUBERNETES_VERSION" {
  description = "Version of Kubernetes to deploy"
  type        = string
}

variable "TARGET_NODE" {
  description = "Proxmox target node for VM deployment"
  type        = string
  default     = "pve"
}

variable "CONTROL_PLANE_RAM" {
  description = "RAM allocation for control plane nodes in MB"
  type        = number
  default     = 20480
}

variable "CONTROL_PLANE_CPU_CORE" {
  description = "Number of CPU cores for control plane nodes"
  type        = number
  default     = 4
}

variable "CONTROL_PLANE_CPU_SOCKET" {
  description = "Number of CPU sockets for control plane nodes"
  type        = number
  default     = 1
}

variable "CONTROL_PLANE_OS_DISK_SIZE" {
  description = "OS disk size for control plane nodes"
  type        = string
  default     = "40G"
}

variable "CONTROL_PLANE_PROXMOX_STORAGE" {
  description = "Proxmox storage location for control plane nodes"
  type        = string
  default     = "local-lvm"
}

variable "CONTROL_PLANE_STORAGE_DISK_SIZE" {
  description = "Storage disk size for control plane nodes"
  type        = string
  default     = "300G"
}

variable "WORKER_OS_DISK_SIZE" {
  description = "OS disk size for worker nodes"
  type        = string
  default     = "40G"
}

variable "WORKER_STORAGE_DISK_SIZE" {
  description = "Storage disk size for worker nodes"
  type        = string
  default     = "300G"
}

variable "WORKER_PROXMOX_STORAGE" {
  description = "Proxmox storage location for worker nodes"
  type        = string
  default     = "local-lvm"
}

variable "WORKER_RAM" {
  description = "RAM allocation for worker nodes in MB"
  type        = number
  default     = 20480
}

variable "WORKER_CPU_CORE" {
  description = "Number of CPU cores for worker nodes"
  type        = number
  default     = 4
}

variable "WORKER_CPU_SOCKET" {
  description = "Number of CPU sockets for worker nodes"
  type        = number
  default     = 1
}

provider "proxmox" {
  pm_api_url          = var.PM_HOST
  pm_api_token_id    = var.PM_API_TOKEN_ID
  pm_api_token_secret = var.PM_API_TOKEN_SECRET
  pm_tls_insecure     = true
}

locals {
  talos_master_nodes = {
    "talos-control-01" = {
      target_node = var.TARGET_NODE
    },
    "talos-control-02" = {
      target_node = var.TARGET_NODE
    },
    "talos-control-03" = {
      target_node = var.TARGET_NODE
    },
  }
  talos_worker_nodes = {
    # "talos-worker-01" = {
    #   target_node = var.TARGET_NODE
    # },
    # "talos-worker-02" = {
    #   target_node = var.TARGET_NODE
    # },
    # "talos-worker-03" = {
    #   target_node = var.TARGET_NODE
    # },
  }
  talos_vip_ip = var.VIP_IP
}

resource "proxmox_vm_qemu" "talos" {
  for_each    = local.talos_master_nodes
  cpu {
    cores    = var.CONTROL_PLANE_CPU_CORE
    sockets  = var.CONTROL_PLANE_CPU_SOCKET
    type     = "host"
  }
  agent       = 1
  memory      = var.CONTROL_PLANE_RAM
  boot        = "order=virtio0;net0;ide2"
  name        = each.key
  vm_state    = "running"
  skip_ipv6   = true
  target_node = each.value.target_node

  disks {
    ide {
      ide2 {
        cdrom {
          iso = var.CD_ROM
        }
      }
    }

    virtio {
      virtio0 {
        disk {
          size    = var.CONTROL_PLANE_OS_DISK_SIZE
          storage = var.CONTROL_PLANE_PROXMOX_STORAGE
        }
      }
      virtio1 {
        disk {
          size    = var.CONTROL_PLANE_STORAGE_DISK_SIZE
          storage = var.CONTROL_PLANE_PROXMOX_STORAGE
        }
      }
    }
  }

  network {
    bridge = "vmbr0"
    id     = 0
    model  = "virtio"
  }
}

resource "proxmox_vm_qemu" "talos_workers" {
  for_each    = local.talos_worker_nodes
  cpu {
    cores    = var.WORKER_CPU_CORE
    sockets  = var.WORKER_CPU_SOCKET
    type     = "host"
  }
  agent       = 1
  memory      = var.WORKER_RAM
  boot        = "order=virtio0;net0;ide2"
  name        = each.key
  vm_state    = "running"
  skip_ipv6   = true
  target_node = each.value.target_node

  disks {
    ide {
      ide2 {
        cdrom {
          iso = var.CD_ROM
        }
      }
    }

    virtio {
      virtio0 {
        disk {
          size    = var.WORKER_OS_DISK_SIZE
          storage = var.WORKER_PROXMOX_STORAGE
        }
      }
      virtio1 {
        disk {
          size    = var.WORKER_STORAGE_DISK_SIZE
          storage = var.WORKER_PROXMOX_STORAGE
        }
      }
    }
  }

  network {
    bridge = "vmbr0"
    id     = 0
    model  = "virtio"
  }
}

################################################################

# Generate cluster secrets
resource "talos_machine_secrets" "this" {
  talos_version = "v1.10.6"
}

# Use first control node IP as control plane endpoint
data "talos_machine_configuration" "controlplane" {
  cluster_name       = "talos-proxmox-cluster"
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${proxmox_vm_qemu.talos["talos-control-01"].default_ipv4_address}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.TALOS_VERSION
  kubernetes_version = var.KUBERNETES_VERSION

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
      }
    })
  ]
}

# Worker node configuration
data "talos_machine_configuration" "worker" {
  cluster_name       = "talos-proxmox-cluster"
  machine_type       = "worker"
  cluster_endpoint   = "https://${proxmox_vm_qemu.talos["talos-control-01"].default_ipv4_address}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.TALOS_VERSION
  kubernetes_version = var.KUBERNETES_VERSION

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
      }
    })
  ]
}

module "wait_for_talos_api" {
  source = "../modules/wait_for_talos_api"

  vm_ips = concat(
    [for vm in proxmox_vm_qemu.talos : vm.default_ipv4_address],
    [for vm in proxmox_vm_qemu.talos_workers : vm.default_ipv4_address]
  )
  ipv4_subnet = var.IPV4_CIDR
}

# Apply configuration to each control plane node
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.talos_master_nodes

  depends_on                  = [proxmox_vm_qemu.talos, module.wait_for_talos_api]
  # client_configuration        = talos_machine_secrets.this.client_configuration
  # client_configuration        = data.talos_client_configuration.this.client_configuration
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = proxmox_vm_qemu.talos[each.key].default_ipv4_address
  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
        }
        network = {
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true
              vip = {
                ip = var.VIP_IP
              }
            }
          ]
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        controllerManager = {
          extraArgs = {
            bind-address = "0.0.0.0"
          }
        }
        scheduler = {
          extraArgs = {
            bind-address = "0.0.0.0"
          }
        }
        apiServer = {
          certSANs = [
            "127.0.0.1",
            var.VIP_IP
          ]
        }
        proxy = {
          disabled = true
        }
        discovery = {
          enabled = false
        }
        etcd = {
          advertisedSubnets = [
            "${var.VIP_IP}/24"
          ]
        }
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          nodeIP = {
            validSubnets = [
              var.CLUSTER_CIDR
            ]
          }
          extraConfig = {
            maxPods = 512
          }
        }
        sysctls = {
          "net.ipv4.neigh.default.gc_thresh1" = "4096"
          "net.ipv4.neigh.default.gc_thresh2" = "8192"
          "net.ipv4.neigh.default.gc_thresh3" = "16384"
        }
        kernel = {
          modules = [
            {
              name = "openvswitch"
            },
            {
              name = "drbd"
              parameters = [
                "usermode_helper=disabled"
              ]
            },
            {
              name = "zfs"
            },
            {
              name = "spl"
            },
            {
              name = "vfio_pci"
            },
            {
              name = "vfio_iommu_type1"
            }
          ]
        }
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
        files = [
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
      cluster = {
        network = {
          cni = {
            name = "none"
          }
          dnsDomain = "maxcloud.local"
          podSubnets = [
            "10.244.0.0/16"
          ]
          serviceSubnets = [
            "10.96.0.0/16"
          ]
        }
      }
    }),
    yamlencode({
      cluster = {
        controlPlane = {
          endpoint = "https://${local.talos_vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
      }
    })
  ]
}

# Apply configuration to each worker node
resource "talos_machine_configuration_apply" "worker" {
  for_each = local.talos_worker_nodes

  depends_on = [
    proxmox_vm_qemu.talos_workers,
    talos_machine_configuration_apply.controlplane,
    module.wait_for_talos_api
  ]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = proxmox_vm_qemu.talos_workers[each.key].default_ipv4_address
  config_patches = [
    yamlencode({
      machine = {
        kubelet = {
          nodeIP = {
            validSubnets = [
              var.CLUSTER_CIDR
            ]
          }
          extraConfig = {
            maxPods = 512
          }
        }
        sysctls = {
          "net.ipv4.neigh.default.gc_thresh1" = "4096"
          "net.ipv4.neigh.default.gc_thresh2" = "8192"
          "net.ipv4.neigh.default.gc_thresh3" = "16384"
        }
        kernel = {
          modules = [
            {
              name = "openvswitch"
            },
            {
              name = "drbd"
              parameters = [
                "usermode_helper=disabled"
              ]
            },
            {
              name = "zfs"
            },
            {
              name = "spl"
            },
            {
              name = "vfio_pci"
            },
            {
              name = "vfio_iommu_type1"
            }
          ]
        }
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
        files = [
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
      cluster = {
        network = {
          cni = {
            name = "none"
          }
          dnsDomain = "maxcloud.local"
          podSubnets = [
            "10.244.0.0/16"
          ]
          serviceSubnets = [
            "10.96.0.0/16"
          ]
        }
      }
    }),
    yamlencode({
      cluster = {
        controlPlane = {
          endpoint = "https://${local.talos_vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        install = {
          image = var.TALOS_IMAGE_URL
          disk  = "/dev/vda"
        }
      }
    })
  ]
}

module "wait_for_talos_api_2" {
  source = "../modules/wait_for_talos_api"

  vm_ips = concat(
    [for vm in proxmox_vm_qemu.talos : vm.default_ipv4_address],
    [for vm in proxmox_vm_qemu.talos_workers : vm.default_ipv4_address]
  )
  ipv4_subnet = var.IPV4_CIDR
}

# Bootstrap the cluster on the first control plane node
resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.controlplane
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                = proxmox_vm_qemu.talos["talos-control-01"].default_ipv4_address
}

# Retrieve kubeconfig from the cluster
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                = proxmox_vm_qemu.talos["talos-control-01"].default_ipv4_address
}

# Save kubeconfig to local file
resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/kubeconfig"

  depends_on = [
    talos_cluster_kubeconfig.this
  ]
}

# Save secrets to local file (equivalent to talosctl gen secrets)
resource "local_file" "secrets" {
  content = yamlencode({
    version = "v1alpha1"
    cluster = {
      id     = talos_machine_secrets.this.machine_secrets.cluster.id
      secret = talos_machine_secrets.this.machine_secrets.cluster.secret
    }
    secrets = {
      bootstraptoken           = talos_machine_secrets.this.machine_secrets.secrets.bootstrap_token
      secretboxencryptionsecret = talos_machine_secrets.this.machine_secrets.secrets.secretbox_encryption_secret
      aescbcencryptionsecret   = talos_machine_secrets.this.machine_secrets.secrets.aescbc_encryption_secret
    }
    trustdinfo = {
      token = talos_machine_secrets.this.machine_secrets.trustdinfo.token
    }
    certs = {
      os = {
        crt = talos_machine_secrets.this.machine_secrets.certs.os.cert
        key = talos_machine_secrets.this.machine_secrets.certs.os.key
      }
      k8s = {
        crt = talos_machine_secrets.this.machine_secrets.certs.k8s.cert
        key = talos_machine_secrets.this.machine_secrets.certs.k8s.key
      }
      k8saggregator = {
        crt = talos_machine_secrets.this.machine_secrets.certs.k8s_aggregator.cert
        key = talos_machine_secrets.this.machine_secrets.certs.k8s_aggregator.key
      }
      k8sserviceaccount = {
        key = talos_machine_secrets.this.machine_secrets.certs.k8s_serviceaccount.key
      }
      etcd = {
        crt = talos_machine_secrets.this.machine_secrets.certs.etcd.cert
        key = talos_machine_secrets.this.machine_secrets.certs.etcd.key
      }
    }
  })
  filename = "${path.module}/secrets.yaml"

  depends_on = [
    talos_machine_secrets.this
  ]
}

output "control_plane_ips" {
  description = "IP addresses of all control plane nodes"
  value = {
    for name, vm in proxmox_vm_qemu.talos : name => vm.default_ipv4_address
  }
}

output "worker_node_ips" {
  description = "IP addresses of all worker nodes"
  value = {
    for name, vm in proxmox_vm_qemu.talos_workers : name => vm.default_ipv4_address
  }
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = local_file.kubeconfig.filename
}
