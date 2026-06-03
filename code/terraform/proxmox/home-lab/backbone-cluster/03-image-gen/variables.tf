# =============================================================================
# Proxmox connection (shared schema with stages 00/01/02)
# =============================================================================
variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (e.g. root@pam!terraform)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox root password (SSH provisioner — used for pct push/exec)"
  type        = string
  sensitive   = true
}

variable "proxmox_host" {
  description = "Proxmox host IP (API + SSH)"
  type        = string
  default     = "10.0.10.10"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "ssh_public_key" {
  description = "SSH public key injected into the container's root account"
  type        = string
}

# =============================================================================
# Container (LXC 103 — image-gen)
# =============================================================================
variable "ct_id" {
  description = "Container VMID"
  type        = number
  default     = 103
}

variable "ct_hostname" {
  description = "Container hostname"
  type        = string
  default     = "image-gen"
}

variable "ct_ip" {
  description = "Static IPv4 for the container (no CIDR). Reserve it on the UDM-SE."
  type        = string
  default     = "10.0.10.78"
}

variable "ct_prefix" {
  description = "Network prefix length"
  type        = number
  default     = 24
}

variable "ct_gateway" {
  description = "Default gateway"
  type        = string
  default     = "10.0.10.1"
}

variable "ct_bridge" {
  description = "Proxmox bridge"
  type        = string
  default     = "vmbr0"
}

variable "nameservers" {
  description = "DNS servers for the container"
  type        = list(string)
  default     = ["10.0.10.1", "1.1.1.1"]
}

variable "ct_cores" {
  description = "CPU cores (also caps CLIP/VAE/T5 CPU-offload work)"
  type        = number
  default     = 8
}

variable "ct_memory_mb" {
  description = "Dedicated RAM in MB. Caps container CPU-side RAM (T5-XXL + CLIP + VAE offload + latents). GPU VRAM/GTT is NOT bounded by this — it draws from the host amdgpu pool."
  type        = number
  default     = 24576
}

variable "ct_swap_mb" {
  description = "Swap in MB"
  type        = number
  default     = 8192
}

variable "ct_disk_gb" {
  description = "rootfs size in GB (build + models). SDXL-Turbo + FLUX.1-schnell set ~ 22 GB."
  type        = number
  default     = 80
}

variable "ct_datastore" {
  description = "Datastore for the container rootfs"
  type        = string
  default     = "local-lvm"
}

# =============================================================================
# OS template (Debian 13 LXC)
# =============================================================================
variable "template_datastore" {
  description = "Datastore holding the vztmpl"
  type        = string
  default     = "local"
}

variable "template_url" {
  description = "URL of the Debian 13 LXC template. Proxmox mirrors them at download.proxmox.com."
  type        = string
  default     = "http://download.proxmox.com/images/system/debian-13-standard_13.1-2_amd64.tar.zst"
}

variable "template_file_name" {
  description = "Local filename for the downloaded template"
  type        = string
  default     = "debian-13-standard_13.1-2_amd64.tar.zst"
}

# =============================================================================
# GPU passthrough — the iGPU DRM nodes bind-mounted into the container.
# Same /dev/dri the host's amdgpu exposes (see notes/local-llm-radeon-780m.md).
# renderD128 = compute node (what Vulkan/RADV uses). card0 = primary node.
# =============================================================================
variable "gpu_devices" {
  description = "Host /dev/dri device paths to pass through"
  type        = list(string)
  default     = ["/dev/dri/card0", "/dev/dri/renderD128"]
}

# =============================================================================
# stable-diffusion.cpp server
# =============================================================================
variable "sd_port" {
  description = "Port the sd-server listens on"
  type        = number
  default     = 7860
}

variable "sd_default_mode" {
  description = "Which model the service runs at boot: 'single' (one-file checkpoint, e.g. SDXL-Turbo) or 'flux' (multi-file FLUX.1-schnell). Switch live with `sd-switch single|flux`."
  type        = string
  default     = "single"

  validation {
    condition     = contains(["single", "flux"], var.sd_default_mode)
    error_message = "sd_default_mode must be 'single' or 'flux'."
  }
}

variable "sd_extra_flags" {
  description = "Extra sd-server flags. Defaults mitigate documented AMD RDNA3 Vulkan distortion + VAE OOM (CLIP/VAE on CPU, VAE tiling) and enable flash-attn in the diffusion model."
  type        = string
  default     = "--diffusion-fa --vae-tiling --clip-on-cpu --vae-on-cpu"

  validation {
    # Rendered single-quoted into server.env; an embedded single quote would
    # break the sourcing.
    condition     = !can(regex("'", var.sd_extra_flags))
    error_message = "sd_extra_flags must not contain single-quote characters."
  }
}

variable "build_jobs" {
  description = "Parallel build jobs for stable-diffusion.cpp. 0 = auto (min of nproc and MemAvailable/2GB). Keep modest — ggml/Vulkan TUs are RAM-heavy and can OOM the container."
  type        = number
  default     = 0
}

variable "build_frontend" {
  description = "Build the sd-server web UI frontend (needs Node 20 + pnpm in the container). false = API-only (lighter, more reliable first build)."
  type        = bool
  default     = false
}

# Filenames the service points at (must match basenames in `models` below).
variable "single_model_file" {
  description = "Single-file checkpoint for 'single' mode"
  type        = string
  default     = "sd_xl_turbo_1.0_fp16.safetensors"
}

variable "flux_diffusion_file" {
  description = "FLUX diffusion GGUF for 'flux' mode"
  type        = string
  default     = "flux1-schnell-Q4_1.gguf"
}

variable "flux_vae_file" {
  description = "FLUX VAE"
  type        = string
  default     = "ae.safetensors"
}

variable "flux_clip_l_file" {
  description = "FLUX CLIP-L encoder"
  type        = string
  default     = "clip_l.safetensors"
}

variable "flux_t5xxl_file" {
  description = "FLUX T5-XXL encoder"
  type        = string
  default     = "t5xxl_fp8_e4m3fn.safetensors"
}

# Models to download into /opt/sd-cpp/models. All defaults are open (no HF auth).
# Verified mid-2026. Add SD 3.5 Medium / FLUX.2-klein here (see terraform.tfvars.example).
variable "models" {
  description = "List of { file, url } to fetch into the models dir"
  type = list(object({
    file = string
    url  = string
  }))

  validation {
    # file/url are written into a TAB-separated manifest with no escaping —
    # whitespace would corrupt the parse loop in provision-sd.sh.
    condition = alltrue([
      for m in var.models :
      can(regex("^[^[:space:]]+$", m.file)) && can(regex("^[^[:space:]]+$", m.url))
    ])
    error_message = "Each models[*].file and .url must contain no whitespace."
  }

  default = [
    # --- single-file fast default (SDXL-Turbo, 1-4 steps, ~6.94 GB) ---
    {
      file = "sd_xl_turbo_1.0_fp16.safetensors"
      url  = "https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors"
    },
    # --- quality option: FLUX.1-schnell GGUF + encoders (~13 GB total) ---
    {
      file = "flux1-schnell-Q4_1.gguf"
      url  = "https://huggingface.co/city96/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q4_1.gguf"
    },
    {
      file = "ae.safetensors"
      url  = "https://huggingface.co/black-forest-labs/FLUX.1-schnell/resolve/main/ae.safetensors"
    },
    {
      file = "clip_l.safetensors"
      url  = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"
    },
    {
      file = "t5xxl_fp8_e4m3fn.safetensors"
      url  = "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp8_e4m3fn.safetensors"
    },
  ]
}
