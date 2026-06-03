# Self-Hosted Local LLM on AMD Radeon 780M iGPU

Reproduction guide for the LLM stack at:

- `https://llm.home.0dl.me` — llama-swap OpenAI-compatible API (LAN only)
- `https://chat.home.0dl.me` — Open WebUI (LAN only)
- `https://chat.0dl.me` — Open WebUI (public, via Cloudflare Tunnel)

The llama-swap API itself is intentionally LAN-only — exposing raw inference
to the public internet is not the goal. Only the chat UI is on the public
bare domain.

End state: a privileged LXC on the Proxmox host (`pve`, Minisforum UM780 XTX,
Ryzen 7 7840HS + Radeon 780M) runs `llama-swap` in front of multiple `llama.cpp`
Vulkan instances, with Open WebUI as the front-end. Both URLs route through the
Cilium / Envoy gateway via a selector-less Service + hand-maintained
EndpointSlice. No VM-level GPU passthrough — that path is a dead end on this
hardware, see "Why not VM passthrough" below.

---

## TL;DR architecture

```
LAN clients:
  client → https://{llm,chat}.home.0dl.me  (TLS, wildcard *.home.0dl.me)
         → MetalLB ext IP 10.0.10.212:443  (backbone-gateway, :https listener)

Public clients (chat UI only):
  client → https://chat.0dl.me            (TLS terminated at CF edge)
         → Cloudflare Tunnel
         → 10.0.10.212:80                  (gateway :http listener)

both paths from here on:
  → HTTPRoute (llm | llm-ui | llm-ui-tunnel in namespace llm)
  → Service (llm | llm-ui, selector-less)
  → EndpointSlice → 10.0.10.79:11434 | :8080
  → LXC 102 "ollama-llm" on pve
    ├── llama-swap            :11434 (proxy)
    │   └── spawns llama-server on ${PORT} per requested model
    │       └── llama.cpp Vulkan b9415 → Mesa RADV → 780M iGPU
    ├── open-webui (Docker)  :8080
    │   ├── OPENAI_API_BASE_URL=http://127.0.0.1:11434/v1
    │   ├── SEARXNG_QUERY_URL=http://127.0.0.1:8888/search?q=<query>&format=json
    │   ├── PLAYWRIGHT_WS_URL=http://127.0.0.1:9222  ← CDP, see CloakBrowser patch below
    │   └── patched utils.py mounted over /app/backend/open_webui/retrieval/web/utils.py
    ├── searxng      (Docker) :8888  ← meta-search backend, fans out to 8 engines
    └── cloakbrowser (Docker) :9222  ← stealth Chromium (CDP) for JS-heavy + bot-walled pages
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
| Qwen3-30B-A3B-Instruct-2507 | Q6_K | 24 GB | general / reasoning | 3B active / 30B total, 64K ctx (bumped from 32K for web-search headroom; ~32 GB total VRAM+GTT) |
| Qwen3-8B (dense) | Q6_K | 6.3 GB | daily / tool use / Hermes-style heavy system prompts | **1.5x faster prompt processing** than 30B-A3B (234 vs 158 tok/s); slower TG (12 vs 27); two variants registered: `qwen3-8b` (`--reasoning off`) for fast daily, `qwen3-8b-think` (`--reasoning on`) for chain-of-thought |
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
  "shared":     "-ngl 99 --threads 8 --jinja --flash-attn auto --cache-reuse 64"

models:
  "qwen3-30b":
    name: "Qwen3 30B-A3B Instruct"
    description: "General-purpose MoE · 3B active · 64K ctx · ~27 tok/s"
    cmd: |
      ${llama-bin}
      --model ${models}/qwen3-30b-a3b-q6.gguf
      -c 65536               # bumped from 32K — web search w/ 5-7 sources overflows 32K
      ${shared}
    env: ["${vulkan-env}"]
    aliases: ["qwen3", "default"]

  "qwen3-8b":
    name: "Qwen3 8B (no-think, fast)"
    description: "Daily, tool use · 8B dense · 64K ctx · reasoning disabled"
    cmd: |
      ${llama-bin}
      --model ${models}/qwen3-8b-q6.gguf
      -c 65536
      ${shared}
      --reasoning off
    env: ["${vulkan-env}"]
    aliases: ["qwen8", "small", "daily"]

  "qwen3-8b-think":
    name: "Qwen3 8B (thinking)"
    description: "Reasoning mode · 8B dense · 64K ctx · reasoning_content split"
    cmd: |
      ${llama-bin}
      --model ${models}/qwen3-8b-q6.gguf
      -c 65536
      ${shared}
      --reasoning on
    env: ["${vulkan-env}"]
    aliases: ["qwen8-think", "reasoning"]

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
    -e ENABLE_RAG_WEB_SEARCH=true \
    -e RAG_WEB_SEARCH_ENGINE=searxng \
    -e SEARXNG_QUERY_URL="http://127.0.0.1:8888/search?q=<query>&format=json" \
    -e RAG_WEB_SEARCH_RESULT_COUNT=5 \
    -e RAG_WEB_SEARCH_CONCURRENT_REQUESTS=10 \
    -e ENABLE_RAG_WEB_SEARCH_BYPASS_EMBEDDING_AND_RETRIEVAL=true \
    -e ENABLE_SEARCH_QUERY_GENERATION=true \
    -e TASK_MODEL=qwen3-30b \
    -e RAG_WEB_LOADER_ENGINE=playwright \
    -e PLAYWRIGHT_WS_URL=http://127.0.0.1:9222 \
    -e PLAYWRIGHT_TIMEOUT=60000 \
    -v /opt/open-webui/patches/utils.py:/app/backend/open_webui/retrieval/web/utils.py:ro \
    ghcr.io/open-webui/open-webui:main
'
```

`PLAYWRIGHT_WS_URL` is **http://** (not ws://) because CloakBrowser uses CDP,
not the Playwright WS protocol. The patched `utils.py` auto-detects by
scheme — see step 8c.

`--network host` is the simplest path — Open WebUI talks to `llama-swap` on
`127.0.0.1:11434` and to `searxng` on `127.0.0.1:8888`, all inside the LXC's
netns, and exposes its own UI on `:8080`. First signup becomes admin because
`DEFAULT_USER_ROLE=admin` is set.

Web-search env vars:

| Var | Purpose |
|---|---|
| `ENABLE_RAG_WEB_SEARCH=true` | Master toggle for web search RAG. |
| `RAG_WEB_SEARCH_ENGINE=searxng` | Pick the backend. Self-hosted SearXNG = no API key, no rate limit, full control. |
| `SEARXNG_QUERY_URL` | Endpoint template. The literal `<query>` is substituted server-side. `format=json` is mandatory — Open WebUI doesn't scrape HTML. |
| `RAG_WEB_SEARCH_RESULT_COUNT=5` | Top-N search results scraped per query. Each scrape is then chunked + (optionally) embedded. |
| `RAG_WEB_SEARCH_CONCURRENT_REQUESTS=10` | Parallel fetches when scraping result pages. |
| `ENABLE_RAG_WEB_SEARCH_BYPASS_EMBEDDING_AND_RETRIEVAL=true` | Skip the local embedding step — feed scraped chunks directly as context. Faster on a Vulkan-only box where embedding runs CPU-only. Tradeoff: longer prompts. |
| `ENABLE_SEARCH_QUERY_GENERATION=true` | Let the model rewrite the user's message into a tighter search query before hitting SearXNG. Higher result quality. |
| `TASK_MODEL=qwen3-30b` | Pin the query-rewriting / title-gen / tag-gen calls to a specific model. Without this, Open WebUI uses the current chat model — fine if you only chat with one model, but causes `llama-swap` to thrash if you switch models per chat (every web search would force an unload/reload). Pinning to `qwen3-30b` (the default chat model) means web search reuses the already-loaded weights — zero swap penalty. Change to `fast` if you usually chat with LFM2 instead. |
| `RAG_WEB_LOADER_ENGINE=playwright` | Use headless Chromium to fetch SearXNG result URLs instead of `requests+BeautifulSoup`. Required for JS-heavy SPAs like Yahoo Finance, Bloomberg, anything React/Vue/Angular. Without this, the default loader gets back an empty `<div id="root"></div>` shell and the model sees nothing useful — leads to "Retrieved N sources" but model saying "sources are generic search queries". |
| `PLAYWRIGHT_WS_URL=http://127.0.0.1:9222` | Remote browser endpoint. **CDP URL, not Playwright WS** — points at the CloakBrowser sidecar (see step 8c). The patched `utils.py` auto-detects scheme: `http(s)://` → `connect_over_cdp` (CloakBrowser, raw Chrome), `ws(s)://` → `connect` (browserless/Playwright server). |
| `PLAYWRIGHT_TIMEOUT=60000` | Per-page nav timeout in **ms** (not seconds — older versions used seconds). 60s is generous; news sites are slow on first hit and Cloudflare challenges can add 5–10s. |

### 8b. Install SearXNG (web search backend)

SearXNG (https://github.com/searxng/searxng) is a self-hosted meta-search
proxy. We run it next to Open WebUI on the same LXC, also `--network host`,
listening on `:8888`. No API key, no rate limit, fully private.

Config lives at `/opt/searxng/`:

```bash
pct exec 102 -- mkdir -p /opt/searxng
```

`/opt/searxng/settings.yml` — minimum required, **JSON format must be on**:

```yaml
# JSON format MUST be enabled — Open WebUI reads JSON, not HTML.
use_default_settings: true

general:
  debug: false
  instance_name: "searxng-llm"

server:
  bind_address: "0.0.0.0"
  port: 8888
  secret_key: "REPLACE_WITH_openssl_rand_hex_32"
  base_url: "http://127.0.0.1:8888/"
  limiter: false
  image_proxy: false
  method: "GET"

ui:
  static_use_hash: true

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "auto"
  formats:
    - html
    - json
```

Generate the secret:

```bash
SECRET=$(openssl rand -hex 32)
sed -i "s|REPLACE_WITH_openssl_rand_hex_32|${SECRET}|" /opt/searxng/settings.yml
```

Optional limiter override (`/opt/searxng/limiter.toml`) — keep limiter off
for LAN-only use:

```toml
[botdetection.ip_limit]
link_token = false
```

Add an explicit `engines:` block in `settings.yml` so a single rate-limit
(Brave) or CAPTCHA (DDG) doesn't starve the result set — fan out to many:

```yaml
engines:
  - name: google
    disabled: false
  - name: bing
    disabled: false
  - name: duckduckgo
    disabled: false
  - name: brave
    disabled: false
  - name: qwant
    disabled: false
  - name: startpage
    disabled: false
  - name: wikipedia
    disabled: false
  - name: mojeek
    disabled: false
  - name: yep
    disabled: false
  - name: presearch
    disabled: false

# Default 3s + 0 retries is brittle for slow engines:
outgoing:
  request_timeout: 6.0
  max_request_timeout: 10.0
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: true
```

(All ten are technically default-enabled in SearXNG, but explicit entries
make it obvious which fanout the instance is configured for and easy to flip
individual ones off.)

Run the container:

```bash
pct exec 102 -- bash -c '
  docker run -d --name searxng --restart always \
    --network host \
    -v /opt/searxng:/etc/searxng:rw \
    -e BASE_URL=http://127.0.0.1:8888/ \
    -e INSTANCE_NAME=searxng-llm \
    -e GRANIAN_PORT=8888 \
    -e GRANIAN_HOST=0.0.0.0 \
    docker.io/searxng/searxng:latest
'
```

**Critical**: `GRANIAN_PORT=8888` is mandatory. The image's default port is
`8080` — without the override, with `--network host`, SearXNG collides with
Open WebUI on `:8080` and crash-loops with `RuntimeError: Address already
in use (os error 98)`.

Verify:

```bash
pct exec 102 -- curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  "http://127.0.0.1:8888/search?q=test&format=json"
#   HTTP 200
```

In Open WebUI, click the `+` icon in the chat input → toggle **Web Search**.
Model gets the top-N SearXNG results scraped and injected as context.

⚠️ **The toggle is per-message.** Setting "Default Features → Web Search" on
the model only flips it ON for **new** chats — it does not retroactively
enable web search on pre-existing chats. If you ask the model a current-events
question and it replies with "I can't search the web" / a stale knowledge
cutoff, the per-message toggle was almost certainly OFF. Tail
`docker logs -f open-webui | grep -iE "searxng|web_search"` while sending a
test message — outbound SearXNG hit should appear within ~1s, otherwise the
backend never entered the web-search branch.

### 8c. Install CloakBrowser (stealth Chromium for JS-heavy + bot-walled pages)

Without a real browser, Open WebUI's default loader (`requests` +
`BeautifulSoup`) sees an empty React shell when fetching pages like Yahoo
Finance, Bloomberg, Google Finance. UI shows "Retrieved N sources" but the
model says the sources contain no usable info. A real headless Chromium fixes
that — and **CloakBrowser** (https://github.com/CloakHQ/CloakBrowser) goes
further: 58 C++-level fingerprint patches make Cloudflare Turnstile,
FingerprintJS, BrowserScan all score it as a normal browser. No more "blocked
by Cloudflare" / empty body responses.

History: we first ran `browserless/chromium` which worked for most sites but
kept hitting Cloudflare/Turnstile on news/finance pages and timed out at 30s.
CloakBrowser replaces it.

```bash
pct exec 102 -- bash -c '
  docker rm -f browserless cloakbrowser 2>/dev/null
  docker run -d --name cloakbrowser --restart always \
    --network host \
    cloakhq/cloakbrowser cloakserve
'
```

Verify CDP responds:

```bash
pct exec 102 -- curl -s http://127.0.0.1:9222/json/version | python3 -m json.tool
# Expected: Browser=Chrome/146.x, real-looking UA, webSocketDebuggerUrl present
```

#### Patching Open WebUI for CDP (CloakBrowser doesn't speak Playwright WS)

Open WebUI's loader calls `p.chromium.connect(playwright_ws_url)` which
speaks the **Playwright WS protocol** (what `browserless` exposes at
`ws://host:3000/chromium/playwright`). CloakBrowser only exposes **CDP** at
`http://host:9222`. Different protocols, no handshake.

Fix: bind-mount a two-line-patched `utils.py` into the container that
(a) auto-detects scheme and dispatches `connect_over_cdp` for `http(s)://`
URLs, `connect` for `ws(s)://` URLs, AND (b) calls `page.goto` with
`wait_until="domcontentloaded"` instead of Playwright's default `"load"`.
Both patches apply to BOTH branches of the loader (sync `lazy_load` and
async `alazy_load`).

The `wait_until` change is critical. Default `"load"` waits for every
sub-resource (ads, trackers, web fonts, analytics beacons). News sites like
CNN, Bloomberg, Reuters, even Yahoo Finance fire trackers indefinitely and
never reach `"load"`, so a 60s timeout fires on EVERY page and the whole
batch fails. `domcontentloaded` fires when the HTML parser finishes — text
content is already in the DOM. Measured: CNN markets/NVDA dropped from 60s
timeout to **1.2s success**.

Download + patch + push:

```bash
# On a workstation:
gh api -H "Accept: application/vnd.github.v3.raw" \
  /repos/open-webui/open-webui/contents/backend/open_webui/retrieval/web/utils.py \
  > /tmp/utils.py
# Apply two patches to BOTH `lazy_load` AND `alazy_load`:
#
# (1) Scheme-aware connect:
#   if self.playwright_ws_url:
#       if self.playwright_ws_url.startswith(('http://', 'https://')):
#           browser = p.chromium.connect_over_cdp(self.playwright_ws_url)
#       else:
#           browser = p.chromium.connect(self.playwright_ws_url)
#
# (2) wait_until=domcontentloaded (so news/ad-heavy sites don't time out):
#   sed -i "s|page.goto(url, timeout=self.playwright_timeout)|page.goto(url, timeout=self.playwright_timeout, wait_until='domcontentloaded')|g" /tmp/utils.py

scp /tmp/utils.py root@<pve>:/tmp/
ssh root@<pve> 'pct exec 102 -- mkdir -p /opt/open-webui/patches && pct push 102 /tmp/utils.py /opt/open-webui/patches/utils.py'
```

Then mount in the `docker run` (see step 8):

```
-v /opt/open-webui/patches/utils.py:/app/backend/open_webui/retrieval/web/utils.py:ro
```

And flip `PLAYWRIGHT_WS_URL` from `ws://...:3000/chromium/playwright` to
`http://127.0.0.1:9222`.

Verify end-to-end — fetches finance.yahoo.com through CDP and confirms
`navigator.webdriver` is false (proving CloakBrowser's stealth applies):

```bash
pct exec 102 -- docker exec open-webui python3 -c '
import asyncio
from playwright.async_api import async_playwright
async def run():
  async with async_playwright() as p:
    browser = await p.chromium.connect_over_cdp("http://127.0.0.1:9222")
    ctx = browser.contexts[0] if browser.contexts else await browser.new_context()
    page = await ctx.new_page()
    await page.goto("https://finance.yahoo.com/quote/NVDA/",
                    wait_until="domcontentloaded", timeout=45000)
    print("title:", await page.title())
    print("webdriver:", await page.evaluate("navigator.webdriver"))
    print("UA:", (await page.evaluate("navigator.userAgent"))[:80])
    await browser.close()
asyncio.run(run())
'
# Expected:
#   title: NVIDIA Corporation (NVDA) Stock Price, News, Quote & History - ...
#   webdriver: False                  ← stealth working
#   UA: Mozilla/5.0 (Windows NT 10.0; Win64; x64) ... Chrome/146 Safari/...
```

⚠️ **On every OWUI image upgrade, re-pull `utils.py` and re-apply the
patch.** The bind-mount overlays whatever the new image ships; if the
upstream file structure changes (different function name, signature, etc.),
the mount will silently break web search. Watch for "Retrieved N sources"
turning into "No sources found" after `docker pull` + restart — that's the
signal to re-patch.

⚠️ **Open WebUI persists admin settings in `webui.db` and DB overrides env
vars on subsequent restarts.** Env vars only apply on first run or when the
DB has no value for that field. Implications:

- If you previously opened Admin → Settings → Web Search and clicked Save,
  the DB has values that ignore `RAG_WEB_LOADER_ENGINE` etc. forever after.
- To make Playwright stick, ALSO go to Admin → Settings → Web Search → Loader
  section → **Web Loader Engine = playwright**, **Playwright WebSocket URL =
  http://127.0.0.1:9222** (the CDP endpoint — not a ws://), **Playwright
  Timeout (ms) = 60000**, and Save.
- Or: stop the container, `sqlite3 /opt/open-webui/data/webui.db "DELETE FROM config WHERE ..."` to null out the field and let env take over again
  (riskier — clears OTHER settings if the schema is one-row JSON-blob).

Symptom of this gotcha: `docker inspect open-webui | grep RAG_WEB_*` shows
your env values, but the admin UI panel shows different values. UI wins.

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

Three HTTPRoutes are created:

- `llm.home.0dl.me` → Service `llm:11434` → llama-swap API (LAN, :https)
- `chat.home.0dl.me` → Service `llm-ui:8080` → Open WebUI (LAN, :https)
- `chat.0dl.me` → Service `llm-ui:8080` → Open WebUI (public, :http via CF Tunnel)

LAN routes terminate TLS at the Envoy gateway via the wildcard `*.home.0dl.me`
cert. The bare-domain tunnel route uses `parentRefs.sectionName: http` to bind
to the gateway's plaintext listener — Cloudflare terminates TLS at the edge
and speaks HTTP back through the tunnel.

### Cloudflare side (manual, can't be terraformed)

After `terraform apply` creates the `llm-ui-tunnel` HTTPRoute, set up the
Cloudflare side (same shape as the existing siyuan/dashy/jellyfin tunnel
entries — reuse the existing tunnel, don't create a new one):

1. Cloudflare DNS: add `CNAME` record
   - Name: `chat`
   - Target: `<tunnel-id>.cfargotunnel.com` (look up the tunnel ID used by
     the other bare-domain apps)
   - Proxy status: Proxied (orange cloud)

2. Cloudflare → Zero Trust → Networks → Tunnels → (your tunnel) →
   Public Hostnames → "Add a public hostname":
   - Subdomain: `chat`
   - Domain: `0dl.me`
   - Path: **empty** (match all paths — don't put `/`)
   - Service: `HTTP`
   - URL: `10.0.10.212` (the gateway external IP, **not** the LXC IP —
     the gateway does host-header routing)

⚠️ The empty Path is critical. Putting `/` or a regex like `^/chat` will
break it — see the immich incident where a leftover regex blocked everything
but matching paths.

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

# Open WebUI (LAN)
curl -s -o /dev/null -w "%{http_code}\n" https://chat.home.0dl.me/
#   200

# Open WebUI (public via Cloudflare Tunnel — only after CF DNS + tunnel mapping)
curl -s -o /dev/null -w "%{http_code}\n" https://chat.0dl.me/
#   200

# Simulate the CF Tunnel hop directly (bypass CF, hit the gateway HTTP listener
# with the Host header it would forward). Useful when public URL fails — proves
# whether the gateway/HTTPRoute or the CF side is at fault.
curl -s -H "Host: chat.0dl.me" -o /dev/null -w "%{http_code}\n" http://10.0.10.212/
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
| **Qwen3-8B Q6_K (dense)** | **234** | 12.3 |
| LiquidAI LFM2-24B-A2B Q8_0 | 189 | **29.3** |
| DeepSeek-Coder-V2-Lite Q8_0 | **244** | 27.5 |

These are real numbers, not vendor estimates. The 780M Vulkan stack is
roughly half the speed of an M5 Metal stack on the same model.

### Hitting the iGPU ceiling — what makes it faster, what doesn't

Phoenix1 iGPU on Vulkan is fundamentally **memory-bandwidth bound for TG**
and **compute / kernel-launch bound for PP**. DDR5-5600 dual-channel ≈ 90
GB/s, shared with CPU. We tested every knob:

- **`echo high > .../power_dpm_force_performance_level`** (force max SCLK
  2700 MHz): zero throughput change. AMD's `gpu_busy_percent` shows 99%
  but compute units are starved waiting on memory.
- **`-b 2048 --ubatch-size 512`** (bigger prompt batch): zero change.
  Kernel launch is the choke, not batch.
- **`--cache-reuse 64`** (prefix KV reuse): only helps on repeat turns
  where the system prompt + tools is identical; massive win for Hermes-style
  agents that re-send the same 18K+-token preamble every turn.

What actually moves the needle:

| Path | Realistic TG speedup | Notes |
|---|---|---|
| External dGPU (RTX 3090, 7900 XTX) over oculink/eGPU | **10-15x** | bandwidth jumps to ~950 GB/s |
| Mac Mini M4 Pro (~270 GB/s unified) | 3-4x | better wattage too |
| DDR5-7200 sticks (if UM780 XTX BIOS supports) | ~1.3x | cheapest hardware tweak |
| Smaller dense model | wins PP, loses TG | dense 8B reads 6 GB/token; MoE 30B-A3B reads ~3 GB/token (active params), so MoE wins TG, dense wins PP |

### Picking between qwen3-8b and qwen3-30b

| Workload shape | Use |
|---|---|
| Short prompt + long reply (chat, story, code completion) | **qwen3-30b** (2x TG) |
| Long prompt + short reply (agentic tool calls, RAG, code review) | **qwen3-8b** (1.5x PP) |
| Hermes Agent (18K system prompt, terse replies) | **qwen3-8b** by default; switch via `hermes config set model.default qwen3-30b` for prose |

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

# Restart SearXNG
docker pull docker.io/searxng/searxng:latest
docker rm -f searxng
# (then re-run the `docker run` from step 8b)

# Restart CloakBrowser
docker pull cloakhq/cloakbrowser:latest
docker rm -f cloakbrowser
# (then re-run the `docker run` from step 8c)

# Test Playwright path end-to-end (see step 8c verify block)

# Sanity-check web search wiring from the host
pct exec 102 -- curl -s "http://127.0.0.1:8888/search?q=anthropic&format=json" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d["results"]),"results")'

# Add a new model
# 1. drop the .gguf into /opt/llama-cpp/models/
# 2. add a block to /opt/llama-swap/config.yaml (mirror an existing one)
# 3. systemctl restart llama-swap

# Expand LXC disk
pct resize 102 rootfs +50G

# Point an OpenAI-SDK client (e.g. Hermes Agent) at the local stack.
# Use the direct LXC IP, NOT the gateway — Cilium HTTPRoute defaults to a 15s
# upstream timeout and big prompts will 504. Direct path has no such cap.
hermes config set model.provider custom
hermes config set model.default qwen3-8b
hermes config set model.base_url http://10.0.10.79:11434/v1
hermes config set model.context_length 64000

# Switch model on the fly (no restart) — all in the same chat:
hermes config set model.default qwen3-30b    # prose / long-form
hermes config set model.default qwen3-8b     # tool calls / RAG
hermes config set model.default fast         # LFM2 for snappy chat
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

### Gateway 504 on big-prompt requests (Hermes / RAG)

- Cilium HTTPRoute default upstream timeout = **15 s**. llama-swap journal
  shows `proxy error: context canceled` + `status=502 ... 15.000s` —
  gateway dropped the connection before llama-server finished prompt
  processing.
- Quick fix: client points at the LXC IP directly
  (`http://10.0.10.79:11434/v1`) instead of `https://llm.home.0dl.me/v1`.
  Skips the gateway. Used for Hermes per the ops cheatsheet above.
- Proper fix (when you want HTTPS LAN for all clients): add
  `spec.rules[].timeouts.request: 5m` to the llm HTTPRoute in
  `manifests/llm.yaml` (Gateway API v1.1+, Cilium supports it).
- DON'T pile on retries from the client — every retry restarts the cold
  load. One client retry with `--no-retry` style flag is fine; three is a
  death spiral.

### llama-server hung after a client disconnect (zero CPU, ESTAB conn but no progress)

- Happens after Hermes/curl times out mid-prompt and bails. llama-server
  keeps the half-processed request slot busy and subsequent requests queue
  forever.
- Fix: `systemctl restart llama-swap` on the LXC. Brutal but immediate.
- Prevention: cap client timeout at less than llama-server's
  `healthCheckTimeout` (300s in our config). Most OpenAI SDKs default 600s
  which is far too long for this hardware.

### Inference falls back to CPU (very slow, ~5 tok/s on a 30B)

- `journalctl -u llama-swap` — search for `Vulkan` in the spawn logs.
  Should see `Found 1 Vulkan devices: AMD Radeon 780M`.
- Check `env: ["${vulkan-env}"]` is present in every model block. Missing
  `LD_LIBRARY_PATH` is the #1 cause.
- Inside the LXC: `LD_LIBRARY_PATH=/opt/llama-cpp/llama-b9415 \
   /opt/llama-cpp/llama-b9415/llama-cli --list-devices` should list
  `Vulkan0: AMD Radeon 780M`.

### SearXNG container crash-loops with `Address already in use (os error 98)`

- SearXNG image default port is `8080` via `granian`. With `--network host`,
  this collides with Open WebUI (also `:8080`).
- Fix: `-e GRANIAN_PORT=8888` on the `docker run`. Don't rely on
  `server.port` in `settings.yml` alone — granian reads the env first.

### Open WebUI "Web Search" toggle is missing or greyed out

- Verify env: `docker inspect open-webui --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE "RAG|SEARX"`.
  Must show `ENABLE_RAG_WEB_SEARCH=true` and a valid `SEARXNG_QUERY_URL`.
- The toggle lives in the chat input `+` menu, **not** the model picker.
  Admin → Settings → Web Search controls the backend; per-chat toggle is
  what actually arms it for a given message.
- Network reach test: `docker exec open-webui curl -s -o /dev/null -w "%{http_code}\n" \
  "http://127.0.0.1:8888/search?q=ping&format=json"` must return `200`.
  Anything else means SearXNG isn't on `127.0.0.1:8888` from Open WebUI's
  netns (check both containers are `--network host`).

### Web search hangs ~60s then errors — `Page.goto: Timeout 60000ms exceeded`

- One slow URL in the result set (usually CNN markets, Bloomberg, Reuters)
  blocks `loader.aload()` for the whole batch. Cause: default Playwright
  `wait_until="load"` waits for every sub-resource; ad/tracker JS on news
  sites never finishes loading.
- Fix: ensure the `domcontentloaded` patch is applied (step 8c). Verify:
  `docker exec open-webui grep -c domcontentloaded /app/backend/open_webui/retrieval/web/utils.py` — must be 2.
- Workaround if patch missing: add the noisy domain to
  Admin → Web Search → Domain Filter List with `!cnn.com,!bloomberg.com,!reuters.com` to skip them entirely.

### Web search returns "request (N tokens) exceeds the available context size"

- Playwright fetches full HTML for 5–7 result pages and Open WebUI injects
  the lot. Easily breaches a 32K window. Three knobs to balance:
  - **Admin → Web Search → Fetch URL Content Length Limit** = `4000` (chars
    per page). Truncates extracted text. Cheapest fix.
  - **Admin → Web Search → Search Result Count** = `3` (fewer pages). Also
    cheap.
  - **`-c` in `/opt/llama-swap/config.yaml`** = bump model context window.
    Qwen3-30B-A3B is currently at `65536` (64K). Can go higher with YaRN but
    costs more VRAM+GTT (KV cache scales linearly with context). After
    edit: `systemctl restart llama-swap`.

### "Retrieved N sources" but model says "sources are generic search queries"

- Means SearXNG returned URLs but the content loader didn't fetch (or
  fetched but extracted nothing). Model sees URL strings, no page text.
- Most likely cause: **Bypass Web Loader is ON** in admin → Web Search.
  Toggle it OFF and Save. Then `docker restart open-webui`.
- Second cause: **Default loader on JS-heavy pages.** Yahoo Finance and
  similar SPAs render to empty `<div id="root"></div>` shells from a plain
  `requests` GET. Switch to Playwright (step 8c).
- Verify in Open WebUI logs: `docker logs -f open-webui | grep -iE "loader|fetch|playwright"` while sending a test message. Should see fetch+extract entries per URL.

### Playwright loader fails with "browser closed unexpectedly" / "connection refused"

- `cloakbrowser` container died or didn't start. Check
  `docker ps | grep cloakbrowser` — must be Up. If exited,
  `docker logs cloakbrowser` for the reason.
- Connection refused: `PLAYWRIGHT_WS_URL` is wrong. With CloakBrowser must
  be exactly `http://127.0.0.1:9222` (CDP). With browserless it was
  `ws://127.0.0.1:3000/chromium/playwright` (Playwright WS). Schemes are
  load-bearing — the patched `utils.py` dispatches on `http://` vs `ws://`.
- "Connection failed" but smoke test in step 8c works → patched `utils.py`
  isn't actually mounted. Verify with:
  ```bash
  docker exec open-webui grep -c connect_over_cdp /app/backend/open_webui/retrieval/web/utils.py  # expect ≥ 2
  docker exec open-webui grep -c domcontentloaded   /app/backend/open_webui/retrieval/web/utils.py  # expect 2
  ```
- After `docker pull ghcr.io/open-webui/open-webui:main` the patched file
  may need re-derivation if upstream `utils.py` structure drifted.

### SearXNG returns HTML instead of JSON / Open WebUI sees no results

- `search.formats` in `settings.yml` must include `json`. Default is HTML only.
- Quick test: `curl 'http://127.0.0.1:8888/search?q=x&format=json'`. If you
  get an HTML page, JSON is disabled and you need to edit `settings.yml` +
  `docker restart searxng`.

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

## Image generation (companion stack)

Local text-to-image on the **same 780M iGPU**, in a separate privileged LXC
(`103`, `image-gen`) running [`stable-diffusion.cpp`](https://github.com/leejet/stable-diffusion.cpp)
— Vulkan / Mesa RADV, the same path as llama.cpp here (no ROCm, no VM
passthrough). Provisioned by the `03-image-gen` Terraform stage (sibling of
this LLM stack). Both LXCs share the same ~55 GB iGPU memory pool, so **don't
keep a big LLM and a diffusion model resident at once** — VRAM+GTT will exhaust.

- Backend: `sd-server` (built `-DSD_VULKAN=ON`) on `10.0.10.78:7860`.
- API: A1111-compatible at `/sdapi/v1` (plus native `/sdcpp/v1`).
- Default model: **SDXL-Turbo** (single-file, 1–4 steps, cfg 1.0). FLUX.1-schnell
  also pulled; switch live with `pct exec 103 -- sd-switch flux`.
- Gateway: `img.home.0dl.me` (LAN-only — `02-helm-stack/manifests/image-gen.yaml`).
- Mitigations on by default: `--clip-on-cpu --vae-on-cpu --vae-tiling --diffusion-fa`.
  Output on the 780M (gfx1103) is **clean** — the RDNA3 Vulkan distortion bug
  reported on 890M/680M does NOT manifest here.
- Measured: **~131 s/image** at 768×768, 4 steps (bandwidth-bound, not compute).

### Wiring sd-server into Open WebUI (this LXC)

Open WebUI's built-in image generation can drive sd-server via the A1111 engine.
**Use the direct LXC URL, not the gateway** — a single image takes ~131 s and
the Cilium HTTPRoute caps upstream at 15 s, so `img.home.0dl.me` would 504. Same
gotcha as the llama-swap 504 above.

On a fresh `webui.db`, set these env vars on the `docker run` (step 8):

| Var | Value |
|---|---|
| `ENABLE_IMAGE_GENERATION` | `true` |
| `IMAGE_GENERATION_ENGINE` | `automatic1111` |
| `AUTOMATIC1111_BASE_URL` | `http://10.0.10.78:7860` |
| `IMAGE_GENERATION_MODEL` | `sd_xl_turbo_1.0_fp16` (match the `title` from `/sdapi/v1/sd-models`) |
| `IMAGE_SIZE` | `768x768` |
| `IMAGE_STEPS` | `4` |

⚠️ If `webui.db` already exists, **the DB overrides env** (see the web-search
gotcha above) — env changes are ignored. Either set it in Admin → Settings →
Images, or patch the DB directly. The persisted form is an `image_generation`
block in the single-row `config` table:

```json
"image_generation": {
  "enable": true, "engine": "automatic1111",
  "model": "sd_xl_turbo_1.0_fp16", "size": "768x768", "steps": 4,
  "automatic1111": {"base_url": "http://10.0.10.78:7860", "api_auth": ""}
}
```

The LXC has no `sqlite3` CLI, but the OWUI container bundles python+sqlite —
patch through it, then restart:

```bash
pct exec 102 -- docker exec -i open-webui python3 - <<'PY'
import sqlite3, json
con = sqlite3.connect('/app/backend/data/webui.db'); cur = con.cursor()
cid, data = cur.execute('select id, data from config order by id desc limit 1').fetchone()
d = json.loads(data)
d['image_generation'] = {
  "enable": True, "engine": "automatic1111",
  "model": "sd_xl_turbo_1.0_fp16", "size": "768x768", "steps": 4,
  "automatic1111": {"base_url": "http://10.0.10.78:7860", "api_auth": ""},
}
cur.execute('update config set data=? where id=?', (json.dumps(d), cid)); con.commit()
print("patched config row", cid)
PY
pct exec 102 -- docker restart open-webui
```

In OWUI chat: send a prompt, click the image icon on the response. First image
~2 min; if OWUI times out, drop to 512×512 or fewer steps.

---

## File map

In this repo:

| File | What |
|---|---|
| `02-helm-stack/manifests/llm.yaml` | Namespace, Services, EndpointSlices, HTTPRoutes |
| `02-helm-stack/apps.tf` | Registers `llm` under `app_files` |
| `02-helm-stack/manifests/image-gen.yaml` | `img.home.0dl.me` route → sd-server LXC 103 |
| `03-image-gen/` | Companion stage — sd.cpp Vulkan image-gen LXC (own README) |
| `notes/local-llm-radeon-780m.md` | This guide |

On the LXC:

| Path | What |
|---|---|
| `/opt/llama-cpp/llama-b9415/` | Vulkan llama.cpp binary release |
| `/opt/llama-cpp/models/*.gguf` | Model weights |
| `/opt/llama-swap/` | llama-swap binary + `config.yaml` |
| `/opt/open-webui/data/` | Open WebUI database / uploads |
| `/opt/searxng/{settings.yml,limiter.toml}` | SearXNG config (JSON format on, secret key, fanout engines) |
| `/opt/open-webui/patches/utils.py` | Patched OWUI loader (CDP-aware), bind-mounted into the container |
| `cloakbrowser` container (no host paths) | Stealth Chromium via CDP on :9222 for JS-heavy / bot-walled pages |
| `/etc/systemd/system/llama-swap.service` | systemd unit |
| `/etc/pve/lxc/102.conf` (on the **host**) | `lxc.mount.entry` for /dev/dri |

---

## References

- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- llama-swap: https://github.com/mostlygeek/llama-swap
- Open WebUI: https://github.com/open-webui/open-webui
- Open WebUI web search docs: https://docs.openwebui.com/category/-web-search
- SearXNG: https://github.com/searxng/searxng
- SearXNG settings reference: https://docs.searxng.org/admin/settings/index.html
- CloakBrowser: https://github.com/CloakHQ/CloakBrowser (stealth Chromium, CDP, drop-in Playwright via patched loader)
- Open WebUI Playwright loader: https://docs.openwebui.com/category/-web-search (Loader Engine section)
- Open WebUI loader source: https://github.com/open-webui/open-webui/blob/main/backend/open_webui/retrieval/web/utils.py (track upstream changes when re-patching)
- llmfit (model picker for given hardware): https://github.com/AlexsJones/llmfit
- Why iGPU passthrough fails on Phoenix:
  - https://github.com/xCuri0/ReBarUEFI
  - https://github.com/isc30/ryzen-7000-series-proxmox
- Smokeless_UMAF (BIOS hidden settings): https://github.com/DavidS95/Smokeless_UMAF
