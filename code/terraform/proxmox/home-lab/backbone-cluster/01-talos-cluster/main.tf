# Stage 01: Talos Kubernetes Cluster on Proxmox VMs
# Creates 3 controlplane VMs, configures Talos, bootstraps etcd.
#
# Each node gets a dedicated Talos ISO with the static IP baked into
# the kernel command line via Talos Image Factory extraKernelArgs.
# This eliminates the DHCP dependency during initial boot.

# =============================================================================
# Providers
# =============================================================================

provider "proxmox" {
  endpoint  = "https://${var.proxmox_host}:8006/"
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_password

    node {
      name    = var.proxmox_node
      address = var.proxmox_host
    }
  }
}

# Second Proxmox host — NAS with Intel iGPU for media workers.
provider "proxmox" {
  alias     = "nas"
  endpoint  = "https://${var.proxmox_host_nas}:8006/"
  api_token = "${var.proxmox_api_token_id_nas}=${var.proxmox_api_token_secret_nas}"
  insecure  = true

  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_password_nas

    node {
      name    = var.proxmox_node_nas
      address = var.proxmox_host_nas
    }
  }
}

# =============================================================================
# Locals
# =============================================================================

locals {
  cluster_endpoint = "https://${var.vip}:6443"
  subnet_base      = join(".", slice(split(".", var.vip), 0, 3))

  # Single shared schematic for ISO and installer. Static IPs are delivered by
  # UniFi DHCP reservations (keyed on MAC) + reasserted permanently via machineconfig.
  talos_installer_image        = "factory.talos.dev/metal-installer/${var.talos_schematic_id}:${var.talos_version}"
  talos_installer_image_worker = "factory.talos.dev/metal-installer/${var.worker_schematic_id}:${var.talos_version}"
}

# =============================================================================
# 1. Download Talos ISO (shared across all nodes)
# =============================================================================

resource "proxmox_download_file" "talos_iso" {
  content_type        = "iso"
  datastore_id        = "local"
  node_name           = var.proxmox_node
  url                 = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-amd64.iso"
  file_name           = "talos-${var.talos_version}-${substr(var.talos_schematic_id, 0, 8)}-amd64.iso"
  overwrite           = false
  overwrite_unmanaged = false
}

# =============================================================================
# 2. Create Proxmox VMs
# =============================================================================

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  name      = each.key
  node_name = var.proxmox_node
  vm_id     = var.vm_id_base + index(sort(keys(var.nodes)), each.key)

  description     = "Backbone cluster controlplane node. Managed by Terraform."
  stop_on_destroy = true
  started         = true
  on_boot         = true

  agent {
    enabled = false
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.os_disk_size
    file_format  = "raw"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = each.value.mac_address
  }

  serial_device {}

  boot_order = ["virtio0", "net0", "ide2"]
}

# =============================================================================
# 3. Wait for Talos API (port 50000) on all nodes
# =============================================================================

resource "null_resource" "wait_for_talos" {
  for_each = var.nodes

  depends_on = [proxmox_virtual_environment_vm.node]

  triggers = {
    node_ip = each.value.ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Talos API on ${each.key} (${each.value.ip}:50000)..."
      for i in $(seq 1 60); do
        if nc -z -w 2 ${each.value.ip} 50000 2>/dev/null; then
          echo "${each.key} (${each.value.ip}:50000) is ready!"
          exit 0
        fi
        echo "  Attempt $i/60 — waiting 10s..."
        sleep 10
      done
      echo "TIMEOUT: ${each.key} (${each.value.ip}) did not become ready"
      exit 1
    EOT
  }
}

# =============================================================================
# 4. Talos Machine Secrets
# =============================================================================

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# =============================================================================
# 5. Machine Configuration (controlplane)
# =============================================================================

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

# =============================================================================
# 6. Apply Configuration to Each Node
# =============================================================================

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  depends_on = [null_resource.wait_for_talos]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value.ip

  config_patches = [
    # Minimal bird2 ExtensionServiceConfig so the extension can start.
    # The siderolabs/bird2 extension ships in the schematic but requires a
    # config file or boot fails after ~1h10m and the node reboots in a loop.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "bird2"
      configFiles = [{
        content   = <<-BIRD
          log syslog all;
          router id 0.0.0.1;
          protocol device {}
          protocol direct { disabled; }
          protocol kernel kernel4 {
            ipv4 { export none; import none; };
            disabled;
          }
        BIRD
        mountPath = "/usr/local/etc/bird.conf"
      }]
    }),
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/vda"
          image = local.talos_installer_image
          wipe  = true
        }
        # The zfs + drbd extensions ship the kernel modules but Talos does NOT
        # auto-load them. Without this, ext-zfs-service blocks on /dev/zfs and the
        # node hangs in "booting" (startAllServices never completes) — same failure
        # class as the bird2 config-file requirement above.
        kernel = {
          modules = [
            { name = "zfs" },
            { name = "drbd" },
          ]
        }
        network = {
          hostname = each.key
          interfaces = [
            {
              interface = "ens18"
              addresses = ["${each.value.ip}/${var.network_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
              vip = {
                ip = var.vip
              }
            }
          ]
          nameservers = var.nameservers
        }
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = {
            "$patch" = "delete"
          }
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        kubelet = {
          nodeIP = {
            validSubnets = ["${local.subnet_base}.0/24"]
          }
          extraConfig = {
            maxPods = 512
            # Graceful Node Shutdown: kubelet cleanly terminates pods on reboot/
            # shutdown instead of leaving orphaned Failed/Completed pods behind.
            shutdownGracePeriod             = "30s"
            shutdownGracePeriodCriticalPods = "10s"
          }
        }
        sysctls = {
          "net.ipv4.neigh.default.gc_thresh1" = "4096"
          "net.ipv4.neigh.default.gc_thresh2" = "8192"
          "net.ipv4.neigh.default.gc_thresh3" = "16384"
        }
      }
      cluster = {
        allowSchedulingOnControlPlanes = true
        controllerManager = {
          extraArgs = {
            bind-address = "0.0.0.0"
            # Auto-GC terminated (Failed/Succeeded) pods once >100 exist.
            # Default is 12500, so orphaned pods left by node reboots/shutdowns
            # linger indefinitely in a small cluster. Keeps ghost "Error" pods clean.
            terminated-pod-gc-threshold = "100"
          }
        }
        scheduler = {
          extraArgs = {
            bind-address = "0.0.0.0"
          }
        }
        apiServer = {
          certSANs = ["127.0.0.1", var.vip]
        }
        controlPlane = {
          endpoint = local.cluster_endpoint
        }
        proxy = {
          disabled = true
        }
        discovery = {
          enabled = false
        }
        etcd = {
          advertisedSubnets = ["${local.subnet_base}.0/24"]
        }
        network = {
          cni = {
            name = "none"
          }
          podSubnets     = ["100.124.0.0/16"]
          serviceSubnets = ["100.125.0.0/16"]
        }
      }
    })
  ]
}

# =============================================================================
# 7. Bootstrap etcd
# =============================================================================

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.node]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[var.bootstrap_node].ip
}

# =============================================================================
# 8. Retrieve Kubeconfig
# =============================================================================

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[var.bootstrap_node].ip
}

# =============================================================================
# 9. Talos Client Configuration
# =============================================================================

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for name, node in var.nodes : node.ip]
  endpoints            = [for name, node in var.nodes : node.ip]
}

# =============================================================================
# 10. Write Kubeconfig + Talosconfig to Disk
# =============================================================================

resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/talosconfig"
  file_permission = "0600"
}

# =============================================================================
# 11. Worker nodes (optional) — hosted on the NAS Proxmox with Intel iGPU
# =============================================================================
# Workers join the existing cluster; no new bootstrap. VLAN 2 tag on the NIC
# carries them onto 10.0.10.0/24 even though the NAS uplink is untagged.

resource "proxmox_download_file" "talos_iso_worker" {
  provider = proxmox.nas
  count    = length(var.worker_nodes) > 0 ? 1 : 0

  content_type        = "iso"
  datastore_id        = var.proxmox_iso_storage_nas
  node_name           = var.proxmox_node_nas
  url                 = "https://factory.talos.dev/image/${var.worker_schematic_id}/${var.talos_version}/metal-amd64.iso"
  file_name           = "talos-${var.talos_version}-${substr(var.worker_schematic_id, 0, 8)}-worker-amd64.iso"
  overwrite           = false
  overwrite_unmanaged = false
}

resource "proxmox_virtual_environment_vm" "worker" {
  provider = proxmox.nas
  for_each = var.worker_nodes

  name      = each.key
  node_name = var.proxmox_node_nas
  vm_id     = each.value.vm_id

  description     = "Backbone cluster worker node. Managed by Terraform."
  stop_on_destroy = true
  started         = true
  on_boot         = true

  # q35 is required for PCIe passthrough (iGPU hostpci).
  machine = each.value.gpu_pci != "" ? "q35" : null
  bios    = "seabios"

  agent { enabled = false }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_memory_mb
  }

  disk {
    datastore_id = var.proxmox_storage_nas
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.os_disk_size
    file_format  = "raw"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso_worker[0].id
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = each.value.mac_address
    vlan_id     = 2
  }

  # API tokens can't set raw hostpci 'id'; references a cluster-level PCI
  # resource mapping instead. Mapping 'intel-igpu' is created out-of-band.
  dynamic "hostpci" {
    for_each = each.value.gpu_pci != "" ? [each.value.gpu_pci] : []
    content {
      device  = "hostpci0"
      mapping = "intel-igpu"
      pcie    = true
    }
  }

  serial_device {}

  boot_order = ["virtio0", "net0", "ide2"]
}

resource "null_resource" "wait_for_talos_worker" {
  for_each = var.worker_nodes

  depends_on = [proxmox_virtual_environment_vm.worker]

  triggers = {
    node_ip = each.value.ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Talos API on ${each.value.ip}:50000..."
      for i in $(seq 1 60); do
        nc -z -w 2 ${each.value.ip} 50000 && exit 0
        sleep 5
      done
      echo "timeout waiting for Talos API on ${each.value.ip}"
      exit 1
    EOT
  }
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = var.worker_nodes

  depends_on = [null_resource.wait_for_talos_worker, talos_machine_bootstrap.this]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip

  config_patches = [
    # See note above on controlplane node apply — bird2 needs a config file
    # or Talos reboots the node after startAllServices times out (~1h10m).
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "bird2"
      configFiles = [{
        content   = <<-BIRD
          log syslog all;
          router id 0.0.0.1;
          protocol device {}
          protocol direct { disabled; }
          protocol kernel kernel4 {
            ipv4 { export none; import none; };
            disabled;
          }
        BIRD
        mountPath = "/usr/local/etc/bird.conf"
      }]
    }),
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/vda"
          image = local.talos_installer_image_worker
          wipe  = true
        }
        # See controlplane note: zfs + drbd modules must be loaded explicitly or
        # ext-zfs-service hangs the boot waiting for /dev/zfs.
        kernel = {
          modules = [
            { name = "zfs" },
            { name = "drbd" },
          ]
        }
        network = {
          hostname = each.key
          interfaces = [
            {
              interface = "ens18"
              addresses = ["${each.value.ip}/${var.network_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
          nameservers = var.nameservers
        }
        # Pin Jellyfin (and other GPU workloads) here via nodeSelector.
        nodeLabels = {
          "accelerator" = each.value.gpu_pci != "" ? "intel-quicksync" : ""
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        kubelet = {
          nodeIP = {
            validSubnets = ["${local.subnet_base}.0/24"]
          }
          # Worker machineconfig doesn't inherit cluster.network.serviceSubnets
          # like controlplane does, so clusterDNS defaults to 10.96.0.10 —
          # wrong for our 100.125.0.0/16 service CIDR. Set it explicitly.
          clusterDNS = ["100.125.0.10"]
          extraConfig = {
            maxPods = 512
            # Graceful Node Shutdown: kubelet cleanly terminates pods on reboot/
            # shutdown instead of leaving orphaned Failed/Completed pods behind.
            shutdownGracePeriod             = "30s"
            shutdownGracePeriodCriticalPods = "10s"
          }
        }
        sysctls = {
          "net.ipv4.neigh.default.gc_thresh1" = "4096"
          "net.ipv4.neigh.default.gc_thresh2" = "8192"
          "net.ipv4.neigh.default.gc_thresh3" = "16384"
        }
      }
    })
  ]
}

# =============================================================================
# 12. Raspberry Pi 4 worker (physical, arm64) — NOT a Proxmox VM
# =============================================================================
# Booted from a factory SBC image (rpi_generic overlay) flashed to a USB SSD.
# Joins the existing cluster over the maintenance API; no new bootstrap.
# Schematic 7eced002… = binfmt-misc, bird2, nfs-utils, nfsd, nfsrahead PLUS the
# siderolabs/sbc-raspberrypi overlay (rpi_generic). No zfs/drbd (RAM-limited),
# no x86 ucode/NIC firmware. Disk is the USB SSD (/dev/sda), NIC is end0.
locals {
  pi_worker_installer = "factory.talos.dev/metal-installer/7eced002b21eec49a420a36a4c31df7a4552cacc5052f2edfc8887e5e0da98d4:v1.13.4"
}

resource "talos_machine_configuration_apply" "pi_worker" {
  # No depends_on the bootstrap: the cluster is already running, so this worker
  # just joins. Avoids dragging the whole CP/VM/ISO chain into a -target apply.
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration

  # node = the Pi's static IP (set in the patch below). The very first apply used
  # a temporary `endpoint` pointing at the Pi's DHCP/maintenance IP (10.0.10.51);
  # now that it's configured it answers on the static IP, so no override is needed.
  # If you ever re-flash, add a UniFi DHCP reservation (MAC e4:5f:01:f4:c9:e3 ->
  # 10.0.10.206) so maintenance and static IPs match, then re-apply.
  node = "10.0.10.206"

  config_patches = [
    # bird2 needs a config file or startAllServices hangs (~1h10m) — same as the
    # other nodes. The Pi schematic ships the bird2 extension.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "bird2"
      configFiles = [{
        content   = <<-BIRD
          log syslog all;
          router id 0.0.0.1;
          protocol device {}
          protocol direct { disabled; }
          protocol kernel kernel4 {
            ipv4 { export none; import none; };
            disabled;
          }
        BIRD
        mountPath = "/usr/local/etc/bird.conf"
      }]
    }),
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda" # USB SSD (no SD card present)
          image = local.pi_worker_installer
          # no wipe — the SBC image is already on this disk
        }
        # NOTE: no kernel.modules here — the Pi schematic has no zfs/drbd.
        network = {
          hostname = "bb-worker-02"
          interfaces = [
            {
              interface = "end0" # Pi NIC (not ens18)
              addresses = ["10.0.10.206/${var.network_prefix}"]
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.gateway
                }
              ]
            }
          ]
          nameservers = var.nameservers
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        kubelet = {
          nodeIP = {
            validSubnets = ["${local.subnet_base}.0/24"]
          }
          clusterDNS = ["100.125.0.10"]
          extraConfig = {
            maxPods = 512
            # Graceful Node Shutdown: kubelet cleanly terminates pods on reboot/
            # shutdown instead of leaving orphaned Failed/Completed pods behind.
            shutdownGracePeriod             = "30s"
            shutdownGracePeriodCriticalPods = "10s"
          }
        }
        sysctls = {
          "net.ipv4.neigh.default.gc_thresh1" = "4096"
          "net.ipv4.neigh.default.gc_thresh2" = "8192"
          "net.ipv4.neigh.default.gc_thresh3" = "16384"
        }
      }
    })
  ]
}
