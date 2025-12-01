# Generate cluster secrets
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Control plane machine configuration
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = "https://${var.initial_control_plane_ip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
      }
    })
  ]
}

# Worker node configuration
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = "https://${var.initial_control_plane_ip}:6443"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
      }
    })
  ]
}

# Apply configuration to control plane nodes
resource "talos_machine_configuration_apply" "controlplane" {
  for_each = var.control_plane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
          "arc" = each.value.arc
        }
        network = {
          interfaces = [
            {
              interface = var.network_interface
              dhcp      = true
              vip = {
                ip = var.vip_ip
              }
            }
          ]
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = var.allow_scheduling_on_control_planes
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
          certSANs = concat(["127.0.0.1", var.vip_ip], var.extra_cert_sans)
        }
        proxy = {
          disabled = var.disable_kube_proxy
        }
        discovery = {
          enabled = var.enable_discovery
        }
        etcd = {
          advertisedSubnets = [
            "${var.vip_ip}/24"
          ]
        }
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          nodeIP = {
            validSubnets = [var.cluster_cidr]
          }
          extraConfig = {
            maxPods = var.max_pods
          }
        }
        sysctls = var.sysctls
        kernel = {
          modules = var.kernel_modules
        }
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
        files = var.machine_files
      }
      cluster = {
        network = {
          cni = {
            name = var.cni_name
          }
          dnsDomain = var.dns_domain
          podSubnets = var.pod_subnets
          serviceSubnets = var.service_subnets
        }
      }
    }),
    yamlencode({
      cluster = {
        controlPlane = {
          endpoint = "https://${var.vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
        }
        features = {
          kubePrism = {
            enabled = var.enable_kubeprism
            port    = var.kubeprism_port
          }
        }
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
      }
    })
  ]
}

# Apply configuration to worker nodes
resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "arc" = each.value.arc
        }
        kubelet = {
          nodeIP = {
            validSubnets = [var.cluster_cidr]
          }
          extraConfig = {
            maxPods = var.max_pods
          }
        }
        sysctls = var.sysctls
        kernel = {
          modules = var.kernel_modules
        }
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
        files = var.machine_files
      }
      cluster = {
        network = {
          cni = {
            name = var.cni_name
          }
          dnsDomain = var.dns_domain
          podSubnets = var.pod_subnets
          serviceSubnets = var.service_subnets
        }
      }
    }),
    yamlencode({
      cluster = {
        controlPlane = {
          endpoint = "https://${var.vip_ip}:6443"
        }
      }
      machine = {
        network = {
          hostname = each.key
        }
        features = {
          kubePrism = {
            enabled = var.enable_kubeprism
            port    = var.kubeprism_port
          }
        }
        install = {
          image = var.talos_image_url
          disk  = var.install_disk
        }
      }
    })
  ]
}

# Bootstrap the cluster on the first control plane node
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.initial_control_plane_ip
}

# Retrieve kubeconfig from the cluster
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.initial_control_plane_ip
}
