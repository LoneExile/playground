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

variable "sdswap_backend_port" {
  description = "Internal port the sd-swap proxy runs the sd-server backend on (loopback only)"
  type        = number
  default     = 17860
}

variable "sdswap_ttl" {
  description = "Idle seconds before sd-swap unloads the backend to free iGPU memory. 0 = never unload."
  type        = number
  default     = 1800
}

variable "sdswap_load_timeout" {
  description = "Seconds sd-swap waits for a backend model to become healthy after a (cold) swap. FLUX is slow to load — keep generous."
  type        = number
  default     = 600
}

variable "sdswap_gen_timeout" {
  description = "Seconds sd-swap allows a single txt2img/img2img generation to run before giving up (separate from the model-load timeout)."
  type        = number
  default     = 1800
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

# Model registry the sd-swap proxy serves. Each `title` shows up in Open WebUI's
# image-model dropdown (Admin -> Settings -> Images). Filenames are relative to
# the models dir. `mode` is "single" (one-file checkpoint) or "flux" (multi-file).
# Titles must correspond to files pulled by `models` above.
variable "model_registry" {
  description = "Image models the proxy exposes + how to launch each"
  type = list(object({
    title           = string
    mode            = string
    model           = optional(string) # mode=single
    diffusion_model = optional(string) # mode=flux
    vae             = optional(string) # mode=flux
    clip_l          = optional(string) # mode=flux
    t5xxl           = optional(string) # mode=flux
  }))
  default = [
    {
      title = "sd_xl_turbo_1.0_fp16"
      mode  = "single"
      model = "sd_xl_turbo_1.0_fp16.safetensors"
    },
    {
      title           = "flux1-schnell"
      mode            = "flux"
      diffusion_model = "flux1-schnell-Q4_1.gguf"
      vae             = "ae.safetensors"
      clip_l          = "clip_l.safetensors"
      t5xxl           = "t5xxl_fp8_e4m3fn.safetensors"
    },
  ]

  validation {
    condition     = alltrue([for m in var.model_registry : contains(["single", "flux"], m.mode)])
    error_message = "Each model_registry[*].mode must be 'single' or 'flux'."
  }
  validation {
    condition     = length(distinct([for m in var.model_registry : m.title])) == length(var.model_registry)
    error_message = "model_registry titles must be unique (they key the proxy's model map)."
  }
  validation {
    condition = alltrue([
      for m in var.model_registry :
      m.mode == "single" ? m.model != null : (
        m.diffusion_model != null && m.vae != null && m.clip_l != null && m.t5xxl != null
      )
    ])
    error_message = "single needs `model`; flux needs `diffusion_model`, `vae`, `clip_l`, `t5xxl`."
  }
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
      # black-forest-labs/FLUX.1-schnell is gated (401); second-state mirrors
      # the same VAE ungated.
      file = "ae.safetensors"
      url  = "https://huggingface.co/second-state/FLUX.1-schnell-GGUF/resolve/main/ae.safetensors"
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
