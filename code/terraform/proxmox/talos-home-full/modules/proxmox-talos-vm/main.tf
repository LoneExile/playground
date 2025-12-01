resource "proxmox_vm_qemu" "this" {
  for_each = var.nodes

  name        = each.key
  target_node = each.value.target_node
  vm_state    = var.vm_state
  agent       = var.agent
  skip_ipv6   = var.skip_ipv6
  boot        = var.boot_order

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory = var.memory

  disks {
    ide {
      ide2 {
        cdrom {
          iso = var.cdrom_iso
        }
      }
    }

    virtio {
      virtio0 {
        disk {
          size    = var.os_disk_size
          storage = var.storage
        }
      }
      virtio1 {
        disk {
          size    = var.storage_disk_size
          storage = var.storage
        }
      }
    }
  }

  network {
    bridge = var.network_bridge
    id     = 0
    model  = var.network_model
  }
}
