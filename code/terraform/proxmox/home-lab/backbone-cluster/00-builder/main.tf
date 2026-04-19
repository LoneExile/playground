# --- Provider ---
provider "proxmox" {
  endpoint = "https://${var.proxmox_host}:8006/"
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure = true

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

# --- Ubuntu Noble cloud image ---
resource "proxmox_download_file" "ubuntu_noble" {
  content_type = "import"
  datastore_id = "local"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
  node_name    = var.proxmox_node
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  overwrite    = false
}

# --- Cloud-init user-data ---
resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data = <<-EOF
#cloud-config
hostname: bb-builder-01

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${var.ssh_public_key}
    lock_passwd: false

package_update: true

write_files:
  - path: /opt/rustfs/docker-compose.yml
    content: |
      services:
        rustfs:
          image: rustfs/rustfs:latest
          container_name: rustfs
          restart: unless-stopped
          ports:
            - "9000:9000"
            - "9001:9001"
          environment:
            RUSTFS_ROOT_USER: ${var.rustfs_root_user}
            RUSTFS_ROOT_PASSWORD: ${var.rustfs_root_password}
          volumes:
            - /data:/data
            - /logs:/logs
          command: server /data --console-address ":9001"

runcmd:
  - apt-get update
  - apt-get install -y ca-certificates curl gnupg lsb-release qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
  - chmod a+r /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  - systemctl enable docker
  - systemctl start docker
  - mkdir -p /data /logs
  - chown -R 10001:10001 /data /logs
  - cd /opt/rustfs && docker compose up -d
    EOF
    file_name = "builder-cloud-init.yaml"
  }
}

# --- Builder VM ---
resource "proxmox_virtual_environment_vm" "builder" {
  name        = "bb-builder-01"
  description = "RustFS S3 backend for Terraform state"
  node_name   = var.proxmox_node
  vm_id       = var.vm_id

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.ubuntu_noble.id
    interface    = "scsi0"
    size         = var.os_disk_size
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge   = var.builder_bridge
    firewall = false
  }

  initialization {
    interface = "ide2"

    dns {
      servers = var.nameservers
    }

    ip_config {
      ipv4 {
        address = "${var.builder_ip}/${var.builder_prefix}"
        gateway = var.builder_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  agent {
    enabled = true
  }

  on_boot         = true
  started         = true
  stop_on_destroy = true
}
