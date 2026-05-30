# Self-Hosted Local LLM on AMD Radeon 780M iGPU

Reproduction guide for the LLM stack at `https://llm.home.0dl.me` (API) and
`https://chat.home.0dl.me` (Open WebUI).

End state: a privileged LXC on the Proxmox host (`pve`, Minisforum UM780 XTX,
Ryzen 7 7840HS + Radeon 780M) runs `llama-swap` in front of multiple `llama.cpp`
Vulkan instances, with Open WebUI as the front-end. Both URLs route through the
Cilium / Envoy gateway via a selector-less Service + hand-maintained
EndpointSlice. No VM-level GPU passthrough — that path is a dead end on this
hardware, see "Why not VM passthrough" below.

---

## TL;DR architecture

```
client → https://{llm,chat}.home.0dl.me (TLS, wildcard *.home.0dl.me)
       → MetalLB ext IP 10.0.10.212 (backbone-gateway)
       → HTTPRoute (llm | llm-ui in namespace llm)
       → Service (llm | llm-ui, selector-less)
       → EndpointSlice → 10.0.10.79:11434 | :8080
       → LXC 102 "ollama-llm" on pve
         ├── llama-swap            :11434 (proxy)
         │   └── spawns llama-server on ${PORT} per requested model
         │       └── llama.cpp Vulkan b9415 → Mesa RADV → 780M iGPU
         └── open-webui (Docker)  :8080
             └── OPENAI_API_BASE_URL=http://127.0.0.1:11434/v1
```

GPU pool: UMA 16 GB (BIOS-reserved VRAM) + ~39 GB GTT (dynamic system-RAM
borrowed via amdgpu) = **~55 GB total addressable by Vulkan**.

---

## Why not VM passthrough

Tried first. Don't redo it.

- VM 101 (`hermes`, Ubuntu 24.04) was converted to OVMF + q35 with
  `hostpci0: 0000:c5:00.0,pcie=1,romfile=vbios_780m.bin` and
  `hostpci1: 0000:c5:00.1,pcie=1`.
- Phoenix1 iGPU appeared in guest `lspci`, but `amdgpu` failed with
  `get invalid ip discovery binary signature` and `discovery failed: -22`.
- Root cause: Phoenix iGPU sizes its BAR via AGESA UMA carve-out at PEI/DXE,
  **not** via PCIe Resizable BAR negotiation. Host `lspci -vvs c5:00.0` shows
  `Region 0` stuck at `size=256M` and `/sys/bus/pci/.../resource0_resize` does
  not exist — firmware never advertises the rebar capability.
- UM780 XTX stock BIOS 1.06 (and Smokeless UMAF AMD-CBS / Setup → Advanced
  → Onboard Devices) shows `Re-Size BAR Support = Enabled` + `Above 4G
  Decoding = Enabled`, but the toggles are **cosmetic** for the iGPU. No
  newer BIOS is available from Minisforum; no community-modded BIOS for
  F7BSD exists with a working patch.
- Cross-reference: same wall hit by `jeenam` on identical UM780 XTX
  (https://github.com/isc30/ryzen-7000-series-proxmox) and BD795i (Raphael)
  Proxmox forum reports. Zero working Phoenix-iGPU-on-Linux-VM reports exist
  in `xCuri0/ReBarUEFI` or the Proxmox forums.

**Working alternative**: load `amdgpu` on the host itself and bind-mount
`/dev/dri/*` into a privileged LXC. The LXC sees the iGPU directly through
Mesa RADV, no firmware fight.

---

## Hardware / starting state

| Item | Value |
|---|---|
| Proxmox host (`pve`) | Minisforum UM780 XTX (Venus series, board F7BSD) |
| CPU | AMD Ryzen 7 7840HS (8C/16T) |
| iGPU | Radeon 780M (Phoenix1, `1002:15bf`) |
| HDMI audio | `1002:1640` (paired with iGPU) |
| RAM | 96 GB |
| Proxmox VE | 8.4.11, kernel 6.8.12-13-pve |
| Storage | `local-lvm` thin pool, ~1.6 TB free |
| Gateway IP | 10.0.10.212 (MetalLB, `backbone-gateway` in `gateway-system`) |
| LXC IP (this guide) | 10.0.10.79 (DHCP — see "DHCP gotcha" below) |

BIOS settings to verify before starting (Del at POST):
`Advanced` →
- `Above 4G Decoding` = Enabled
- `Re-Size BAR Support` = Enabled
- `SR-IOV Support` = Enabled
- `IOMMU` and `SVM` = Enabled (already on by default)

These don't make iGPU passthrough work, but `Above 4G` is required for the
host kernel to map the iGPU's BAR sanely and not affect normal use.

`Advanced` → `AMD CBS` → `NBIO Common Options` → `GFX Configuration`:
- `iGPU Configuration` = `UMA_SPECIFIED`
- `UMA Frame buffer Size` = `16G` (max). This is the static VRAM carve-out.
  Tradeoff: locks 16 GB away from the OS forever. Pick lower (4–8 GB) if you
  need that RAM for VMs — LLM models will spill to GTT anyway.

---

## Step-by-step reproduction

Assumes a fresh Proxmox host with `amdgpu` currently blacklisted (because some
previous attempt at VFIO passthrough). If that's not your state, skip the
"undo VFIO" step.

### 1. Undo VFIO binding on the host (if applicable)

```bash
ssh root@<pve-ip>

# Stop any VM that holds the iGPU
qm config 101 | grep hostpci   # check
qm shutdown 101 --timeout 60
qm set 101 -delete hostpci0,hostpci1

# Drop the amdgpu/radeon/snd_hda_intel blacklist
sed -i '/^blacklist amdgpu$/d; /^blacklist radeon$/d; /^blacklist snd_hda_intel$/d' \
  /etc/modprobe.d/pve-blacklist.conf

# Disable the vfio.conf that forced vfio-pci on AMD ids
mv /etc/modprobe.d/vfio.conf /etc/modprobe.d/vfio.conf.disabled 2>/dev/null

update-initramfs -u -k all
reboot
```

After reboot, verify:

```bash
lspci -nnk -s c5:00.0 | grep "Kernel driver"
#   Kernel driver in use: amdgpu     ← required
ls /dev/dri/
#   by-path  card0  renderD128       ← required
cat /sys/class/drm/card*/device/mem_info_vram_total
#   17179869184                      ← 16 GB UMA (matches BIOS)
cat /sys/class/drm/card*/device/mem_info_gtt_total
#   ~42000000000                     ← ~39 GB GTT, half of system RAM minus UMA
```

### 2. Create the privileged LXC

```bash
# Available template
pveam list local | grep debian-13

# Create privileged container (unprivileged=0). nesting=1 lets us run Docker
# inside for Open WebUI. 100 GB rootfs is enough for ~4 models; expand later
# with `pct resize` if you pull more.
pct create 102 local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst \
  --hostname ollama-llm \
  --memory 4096 --cores 8 \
  --rootfs local-lvm:100 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 0 \
  --onboot 1 --start 0
```

Bind the host's `/dev/dri` into the container. Edit
`/etc/pve/lxc/102.conf` and append:

```
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri/card0 dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
```

(`226:*` is the DRM character-device major. Stable on Linux.)

Start and bump memory. Models stream through GTT mappings that page into the
LXC's process address space, so the cgroup limit caps usable model size — set
high enough for the biggest model you'll load plus headroom.

```bash
pct start 102
pct set 102 -memory 65536 -swap 4096
```

### 3. Resize disk if pulling many models

```bash
# +150 GB → 250 GB total, online (no reboot)
pct resize 102 rootfs +150G
pct exec 102 -- df -h /
```

### 4. Install Mesa Vulkan in the LXC

```bash
pct exec 102 -- bash -c '
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    mesa-vulkan-drivers vulkan-tools libvulkan1 curl ca-certificates pciutils zstd
'
# Verify
pct exec 102 -- vulkaninfo 2>&1 | grep -E "deviceName|driverName" | head -4
#   deviceName        = AMD Radeon 780M (RADV PHOENIX)
#   driverName        = radv
#   deviceName        = llvmpipe ...
#   driverName        = llvmpipe
```

### 5. Install llama.cpp Vulkan binary

Pull a recent prebuilt release (Vulkan flavour, Ubuntu x64). Replace
`b9415` with whatever's current in https://github.com/ggml-org/llama.cpp/releases.

```bash
pct exec 102 -- bash -c '
  apt-get install -y -qq libgomp1 libcurl4t64
  mkdir -p /opt/llama-cpp && cd /opt/llama-cpp
  curl -sL -o llama.tgz \
    https://github.com/ggml-org/llama.cpp/releases/download/b9415/llama-b9415-bin-ubuntu-vulkan-x64.tar.gz
  tar xzf llama.tgz && rm llama.tgz
  cd llama-b9415
  LD_LIBRARY_PATH=. ./llama-cli --list-devices
'
# Expected:
#   Vulkan0: AMD Radeon 780M (RADV PHOENIX) (56496 MiB, 56414 MiB free)
```

### 6. Pull models

Models live in `/opt/llama-cpp/models/`. Picked via `llmfit`
(github.com/AlexsJones/llmfit) targeting ~55 GB GPU memory with the
`llama.cpp` runtime. MoE models with small active-param count are the right
choice on a slow iGPU — total quality of 30B+, inference cost of ~3B.

| Model | Quant | Size | Best for | Notes |
|---|---|---|---|---|
| Qwen3-30B-A3B-Instruct-2507 | Q6_K | 24 GB | general / reasoning | 3B active / 30B total, 32K ctx |
| Qwen3-Coder-30B-A3B-Instruct | Q6_K | 24 GB | coding | same arch as above, coder fine-tune |
| LFM2-24B-A2B | Q8_0 | 24 GB | fast general | 2B active, fastest TG (~29 tok/s) |
| DeepSeek-Coder-V2-Lite-Instruct | Q8_0 | 16 GB | lightweight code | 2.4B active, fast pp |

Sources used (single-file GGUFs):

```bash
pct exec 102 -- bash -c '
  cd /opt/llama-cpp/models
  curl -L --progress-bar -o qwen3-30b-a3b-q6.gguf \
    https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/main/Qwen3-30B-A3B-Instruct-2507-Q6_K.gguf
  curl -L --progress-bar -o qwen3-coder-30b-a3b-q6.gguf \
    https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf
  curl -L --progress-bar -o lfm2-24b-q8.gguf \
    https://huggingface.co/LiquidAI/LFM2-24B-A2B-GGUF/resolve/main/LFM2-24B-A2B-Q8_0.gguf
  curl -L --progress-bar -o deepseek-coder-v2-lite-q8.gguf \
    https://huggingface.co/bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/DeepSeek-Coder-V2-Lite-Instruct-Q8_0.gguf
'
```

### 7. Install llama-swap

`llama-swap` (https://github.com/mostlygeek/llama-swap) is a thin proxy that
listens on one port and spawns the right `llama-server` on demand per request,
killing idle ones after a TTL. Single binary, no deps.

```bash
pct exec 102 -- bash -c '
  mkdir -p /opt/llama-swap && cd /opt/llama-swap
  curl -sL -o llama-swap.tgz \
    https://github.com/mostlygeek/llama-swap/releases/download/v219/llama-swap_219_linux_amd64.tar.gz
  tar xzf llama-swap.tgz && rm llama-swap.tgz
  ./llama-swap --version
'
```

Drop the config at `/opt/llama-swap/config.yaml`:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json
healthCheckTimeout: 300
logLevel: info
startPort: 10001
globalTTL: 1800              # 30 min idle unload
sendLoadingState: true       # UI sees "loading..." during swap
includeAliasesInList: false  # keep dropdown clean — aliases still resolve in API calls

macros:
  "llama-bin":  "/opt/llama-cpp/llama-b9415/llama-server --host 127.0.0.1 --port ${PORT}"
  "vulkan-env": "LD_LIBRARY_PATH=/opt/llama-cpp/llama-b9415"
  "models":     "/opt/llama-cpp/models"
  "shared":     "-ngl 99 --threads 8 --jinja --flash-attn auto"

models:
  "qwen3-30b":
    name: "Qwen3 30B-A3B Instruct"
    description: "General-purpose MoE · 3B active · 32K ctx · ~27 tok/s"
    cmd: |
      ${llama-bin}
      --model ${models}/qwen3-30b-a3b-q6.gguf
      -c 32768
      ${shared}
    env: ["${vulkan-env}"]
    aliases: ["qwen3", "default"]

  "qwen3-coder":
    name: "Qwen3 Coder 30B-A3B"
    description: "Coding-specialized MoE · 3B active · 32K ctx"
    cmd: |
      ${llama-bin}
      --model ${models}/qwen3-coder-30b-a3b-q6.gguf
      -c 32768
      ${shared}
    env: ["${vulkan-env}"]
    aliases: ["coder"]

  "lfm2-24b":
    name: "Liquid LFM2 24B-A2B"
    description: "Fast MoE · 2B active · 16K ctx · ~29 tok/s"
    cmd: |
      ${llama-bin}
      --model ${models}/lfm2-24b-q8.gguf
      -c 16384
      ${shared}
    env: ["${vulkan-env}"]
    aliases: ["fast"]

  "deepseek-coder":
    name: "DeepSeek Coder V2 Lite"
    description: "Lightweight code MoE · 2.4B active · 16K ctx · fast prompt"
    cmd: |
      ${llama-bin}
      --model ${models}/deepseek-coder-v2-lite-q8.gguf
      -c 16384
      ${shared}
    env: ["${vulkan-env}"]
    aliases: ["dscoder"]
```

Critical: the `env: ["${vulkan-env}"]` line. Without `LD_LIBRARY_PATH`,
`llama-server` cannot find `libggml-vulkan.so` and silently falls back to CPU.

systemd unit at `/etc/systemd/system/llama-swap.service`:

```ini
[Unit]
Description=llama-swap proxy (multi-model llama.cpp Vulkan)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/llama-swap
ExecStart=/opt/llama-swap/llama-swap --config /opt/llama-swap/config.yaml --listen 0.0.0.0:11434
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
pct exec 102 -- systemctl daemon-reload
pct exec 102 -- systemctl enable --now llama-swap
pct exec 102 -- curl -s http://localhost:11434/v1/models | python3 -m json.tool
```

### 8. Install Open WebUI (Docker)

```bash
pct exec 102 -- bash -c '
  apt-get install -y -qq docker.io
  systemctl enable --now docker
  docker --version
'

pct exec 102 -- bash -c '
  mkdir -p /opt/open-webui/data
  docker run -d --name open-webui --restart always \
    --network host \
    -v /opt/open-webui/data:/app/backend/data \
    -e OPENAI_API_BASE_URL=http://127.0.0.1:11434/v1 \
    -e OPENAI_API_KEY=sk-no-auth \
    -e ENABLE_OLLAMA_API=false \
    -e WEBUI_PORT=8080 \
    -e DEFAULT_USER_ROLE=admin \
    ghcr.io/open-webui/open-webui:main
'
```

`--network host` is the simplest path — Open WebUI talks to `llama-swap` on
`127.0.0.1:11434` inside the LXC's netns and exposes its own UI on `:8080`.
First signup becomes admin because `DEFAULT_USER_ROLE=admin` is set.

### 9. K8s gateway routing

Manifest: `02-helm-stack/manifests/llm.yaml` (see repo). The pattern is
selector-less Service + hand-maintained EndpointSlice — required because the
backend (LXC) is off-cluster.

Registered in `02-helm-stack/apps.tf` under `app_files = { ..., llm = "..." }`.

Apply via Terraform:

```bash
cd 02-helm-stack
terraform apply -var-file=../terraform.tfvars
```

Two HTTPRoutes are created:

- `llm.home.0dl.me` → Service `llm:11434` → llama-swap API
- `chat.home.0dl.me` → Service `llm-ui:8080` → Open WebUI

TLS is terminated at the Envoy gateway via the wildcard `*.home.0dl.me`
cert. Same `parentRefs: backbone-gateway` as every other app in the stack.

### 10. Verify end-to-end

```bash
# DNS
dig +short llm.home.0dl.me
#   10.0.10.212

# Models endpoint
curl -s https://llm.home.0dl.me/v1/models | python3 -m json.tool | head -30

# Inference (will cold-load the model on first call)
curl -s https://llm.home.0dl.me/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"default","messages":[{"role":"user","content":"hi"}],"max_tokens":20}'

# Open WebUI
curl -s -o /dev/null -w "%{http_code}\n" https://chat.home.0dl.me/
#   200
```

Browser: open `https://chat.home.0dl.me`, create the admin account, the
model dropdown auto-populates from `/v1/models`.

---

## Benchmark numbers (for reference)

`llama-bench` on this exact hardware, all layers offloaded (`-ngl 99`),
prompt=128, gen=64, 8 CPU threads:

| Model | pp (tok/s) | tg (tok/s) |
|---|---|---|
| Qwen3-30B-A3B-Instruct Q6_K | 158 | 27.2 |
| Qwen3-Coder-30B-A3B Q6_K | 154 | 27.1 |
| LiquidAI LFM2-24B-A2B Q8_0 | 189 | **29.3** |
| DeepSeek-Coder-V2-Lite Q8_0 | **244** | 27.5 |

These are real numbers, not vendor estimates. The 780M Vulkan stack is
roughly half the speed of an M5 Metal stack on the same model.

---

## Operations cheatsheet

```bash
# SSH to host then LXC
ssh root@<pve-ip>
pct enter 102

# Check llama-swap state
systemctl status llama-swap
journalctl -u llama-swap -n 50 --no-pager

# Models loaded right now
curl -s http://localhost:11434/v1/models | jq '.data[].id'

# Force-unload everything (free VRAM immediately)
curl -X POST http://localhost:11434/unload

# Restart Open WebUI (e.g. after upgrading the image)
docker pull ghcr.io/open-webui/open-webui:main
docker rm -f open-webui
# (then re-run the `docker run` from step 8)

# Add a new model
# 1. drop the .gguf into /opt/llama-cpp/models/
# 2. add a block to /opt/llama-swap/config.yaml (mirror an existing one)
# 3. systemctl restart llama-swap

# Expand LXC disk
pct resize 102 rootfs +50G
```

---

## DHCP gotcha

The LXC currently gets `10.0.10.79` via DHCP. The EndpointSlice in
`manifests/llm.yaml` hard-codes this IP. If the lease renews to a different
address, both routes break.

Fix: reserve the IP. On the UDM-SE at 10.0.10.1: Settings → Devices →
ollama-llm → assign static IP `10.0.10.79`. Or set a static IP on the LXC
side (`pct set 102 -net0 ...,ip=10.0.10.79/24,gw=10.0.10.1`).

If the address ever changes anyway, update the
`endpoints[0].addresses[0]` field in `llm.yaml` and `terraform apply`.

---

## Troubleshooting

### Open WebUI dropdown is empty / shows no models

- `curl http://10.0.10.79:11434/v1/models` from the host — must return
  the four model entries with aliases.
- `docker logs open-webui` — should show successful startup, not connection
  errors to the API base URL.
- Check `OPENAI_API_BASE_URL` env on the container; needs the `/v1` suffix.

### Inference falls back to CPU (very slow, ~5 tok/s on a 30B)

- `journalctl -u llama-swap` — search for `Vulkan` in the spawn logs.
  Should see `Found 1 Vulkan devices: AMD Radeon 780M`.
- Check `env: ["${vulkan-env}"]` is present in every model block. Missing
  `LD_LIBRARY_PATH` is the #1 cause.
- Inside the LXC: `LD_LIBRARY_PATH=/opt/llama-cpp/llama-b9415 \
   /opt/llama-cpp/llama-b9415/llama-cli --list-devices` should list
  `Vulkan0: AMD Radeon 780M`.

### `vulkaninfo` works in LXC but ollama / llama.cpp finds no GPU

- The bundled Vulkan loader in some binaries doesn't search the system
  ICD dirs. For ollama specifically, Vulkan iGPU detection is broken
  as of 0.24 — use `llama.cpp` directly (the path this guide takes).

### Host crashed when starting VM 101 with `hostpci0: 0000:c5:00`

- The catch-all PCI address grabs every function under `c5:00.*`,
  including `c5:00.6` (Realtek ALC256 onboard audio) which the host's
  `snd_hda_intel` is holding. Yanking it triggers a kernel oops.
- Use `0000:c5:00.0,...` (GPU only) or pair with `0000:c5:00.1,...`
  (HDMI audio). Never the bare prefix.

### Smokeless UMAF won't boot after one use, asserts in `BootOption.c(242)`

- Known bug: opening UMAF's `BootManager` writes a malformed `Misc` boot
  entry to NVRAM, and on next boot the CR() macro asserts.
- Recover by powering off, unplugging USB, booting normally, then entering
  vendor BIOS Setup (Del) → Boot Maintenance Manager → delete the `Misc`
  entry. Or CMOS-clear via the white 2-pin connector on the UM780 board
  edge (no jumper or coin cell on this board).
- Never reopen UMAF's BootManager — that's the trigger. Edit AMD CBS /
  Setup forms only.

---

## File map

In this repo:

| File | What |
|---|---|
| `02-helm-stack/manifests/llm.yaml` | Namespace, Services, EndpointSlices, HTTPRoutes |
| `02-helm-stack/apps.tf` | Registers `llm` under `app_files` |
| `notes/local-llm-radeon-780m.md` | This guide |

On the LXC:

| Path | What |
|---|---|
| `/opt/llama-cpp/llama-b9415/` | Vulkan llama.cpp binary release |
| `/opt/llama-cpp/models/*.gguf` | Model weights |
| `/opt/llama-swap/` | llama-swap binary + `config.yaml` |
| `/opt/open-webui/data/` | Open WebUI database / uploads |
| `/etc/systemd/system/llama-swap.service` | systemd unit |
| `/etc/pve/lxc/102.conf` (on the **host**) | `lxc.mount.entry` for /dev/dri |

---

## References

- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- llama-swap: https://github.com/mostlygeek/llama-swap
- Open WebUI: https://github.com/open-webui/open-webui
- llmfit (model picker for given hardware): https://github.com/AlexsJones/llmfit
- Why iGPU passthrough fails on Phoenix:
  - https://github.com/xCuri0/ReBarUEFI
  - https://github.com/isc30/ryzen-7000-series-proxmox
- Smokeless_UMAF (BIOS hidden settings): https://github.com/DavidS95/Smokeless_UMAF
