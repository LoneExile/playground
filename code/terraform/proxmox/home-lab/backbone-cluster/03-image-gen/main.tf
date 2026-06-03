# =============================================================================
# Stage 03 — image-gen
# Privileged Debian 13 LXC on `pve` with the Radeon 780M iGPU passed through
# (/dev/dri bind-mount, NOT VM passthrough — that's a dead end on Phoenix, see
# notes/local-llm-radeon-780m.md). Builds leejet/stable-diffusion.cpp with the
# Vulkan backend and runs `sd-server` as a systemd service. Coexists with the
# llama-swap LLM LXC (102) — both share the same iGPU memory pool.
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

locals {
  models_dir = "/opt/sd-cpp/models"

  # Connection to the PVE host for pct push/exec (the provisioning path).
  host_conn = {
    type     = "ssh"
    host     = var.proxmox_host
    user     = "root"
    password = var.proxmox_password
  }

  # Rendered once, used for both the file provisioner and the re-provision
  # trigger hash (so the hash can never drift from what's actually written).
  server_env_content = templatefile("${path.module}/templates/server.env.tftpl", {
    port                = var.sd_port
    mode                = var.sd_default_mode
    models_dir          = local.models_dir
    single_model_file   = var.single_model_file
    flux_diffusion_file = var.flux_diffusion_file
    flux_vae_file       = var.flux_vae_file
    flux_clip_l_file    = var.flux_clip_l_file
    flux_t5xxl_file     = var.flux_t5xxl_file
    extra_flags         = var.sd_extra_flags
  })
}

# --- Debian 13 LXC template ---
resource "proxmox_download_file" "debian13_lxc" {
  content_type = "vztmpl"
  datastore_id = var.template_datastore
  node_name    = var.proxmox_node
  url          = var.template_url
  file_name    = var.template_file_name
  overwrite    = false
}

# --- Container root password (output, for console/SSH fallback) ---
resource "random_password" "ct" {
  length  = 20
  special = false
  keepers = { ct = var.ct_id }
}

# --- The image-gen container ---
resource "proxmox_virtual_environment_container" "image_gen" {
  description = "stable-diffusion.cpp Vulkan image generation (Radeon 780M)"
  node_name   = var.proxmox_node
  vm_id       = var.ct_id

  # Privileged — simplest path for direct iGPU /dev/dri access, matches the
  # proven llama-swap LXC 102. nesting=1 lets you run Docker later (e.g. a UI).
  unprivileged = false

  features {
    nesting = true
  }

  cpu {
    cores = var.ct_cores
  }

  memory {
    dedicated = var.ct_memory_mb
    swap      = var.ct_swap_mb
  }

  disk {
    datastore_id = var.ct_datastore
    size         = var.ct_disk_gb
  }

  network_interface {
    name   = "veth0"
    bridge = var.ct_bridge
  }

  initialization {
    hostname = var.ct_hostname

    dns {
      servers = var.nameservers
    }

    ip_config {
      ipv4 {
        address = "${var.ct_ip}/${var.ct_prefix}"
        gateway = var.ct_gateway
      }
    }

    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = random_password.ct.result
    }
  }

  operating_system {
    template_file_id = proxmox_download_file.debian13_lxc.id
    type             = "debian"
  }

  # iGPU DRM nodes — bind-mounted from the host. The provider creates the dev
  # nodes inside the container and wires the cgroup device allow rules.
  dynamic "device_passthrough" {
    for_each = var.gpu_devices
    content {
      path = device_passthrough.value
    }
  }

  started       = true
  start_on_boot = true

  # console=1 keeps `pct console`/`pct enter` working for debugging.
  console {
    enabled = true
    type    = "tty"
  }
}

# --- Provision: push scripts/config to the host, then pct push + exec into CT ---
resource "null_resource" "provision_sd" {
  depends_on = [proxmox_virtual_environment_container.image_gen]

  triggers = {
    container_id  = proxmox_virtual_environment_container.image_gen.id
    provision_sha = filesha256("${path.module}/scripts/provision-sd.sh")
    runserver_sha = filesha256("${path.module}/scripts/run-server.sh")
    switch_sha    = filesha256("${path.module}/scripts/sd-switch.sh")
    models        = sha256(jsonencode(var.models))
    server_env    = sha256(local.server_env_content)
    frontend      = tostring(var.build_frontend)
    build_jobs    = tostring(var.build_jobs)
  }

  # 1. provision script (static bash — read raw, no templating)
  provisioner "file" {
    content     = file("${path.module}/scripts/provision-sd.sh")
    destination = "/tmp/sd-provision-${var.ct_id}.sh"
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }

  # 2. server launcher (static)
  provisioner "file" {
    content     = file("${path.module}/scripts/run-server.sh")
    destination = "/tmp/sd-run-server-${var.ct_id}.sh"
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }

  # 3. model switcher (static)
  provisioner "file" {
    content     = file("${path.module}/scripts/sd-switch.sh")
    destination = "/tmp/sd-switch-${var.ct_id}.sh"
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }

  # 4. server.env (rendered)
  provisioner "file" {
    content     = local.server_env_content
    destination = "/tmp/sd-server-${var.ct_id}.env"
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }

  # 5. models manifest (rendered, tab-separated)
  provisioner "file" {
    content = templatefile("${path.module}/templates/models.tsv.tftpl", {
      models = var.models
    })
    destination = "/tmp/sd-models-${var.ct_id}.tsv"
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }

  # 6. push everything into the CT and run the installer
  provisioner "remote-exec" {
    inline = [
      "set -e",
      # The container reports 'started' before its init/network are up — wait
      # until `pct exec` actually works before pushing/running anything.
      "for i in $(seq 1 60); do pct exec ${var.ct_id} -- true 2>/dev/null && break; echo 'waiting for CT ${var.ct_id}...'; sleep 2; done",
      "pct exec ${var.ct_id} -- systemctl is-system-running --wait >/dev/null 2>&1 || true",
      "pct push ${var.ct_id} /tmp/sd-provision-${var.ct_id}.sh /root/provision-sd.sh --perms 0755",
      "pct push ${var.ct_id} /tmp/sd-run-server-${var.ct_id}.sh /root/run-server.sh --perms 0755",
      "pct push ${var.ct_id} /tmp/sd-switch-${var.ct_id}.sh /root/sd-switch.sh --perms 0755",
      "pct push ${var.ct_id} /tmp/sd-server-${var.ct_id}.env /root/server.env",
      "pct push ${var.ct_id} /tmp/sd-models-${var.ct_id}.tsv /root/sd-models.tsv",
      "pct exec ${var.ct_id} -- env BUILD_FRONTEND=${var.build_frontend} BUILD_JOBS=${var.build_jobs} bash /root/provision-sd.sh",
    ]
    connection {
      type     = local.host_conn.type
      host     = local.host_conn.host
      user     = local.host_conn.user
      password = local.host_conn.password
    }
  }
}
