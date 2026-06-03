#!/usr/bin/env bash
# Provisions stable-diffusion.cpp (Vulkan) inside the image-gen LXC.
# Idempotent: safe to re-run (skips existing models, rebuilds from latest source).
# Pushed + executed by Terraform (null_resource.provision_sd). Inputs:
#   /root/server.env       — SD_* config (rendered by TF)
#   /root/sd-models.tsv     — <filename>\t<url> per line (rendered by TF)
#   /root/run-server.sh     — service launcher (static)
#   /root/sd-switch.sh      — model switcher (static)
#   env BUILD_FRONTEND=true|false
set -euo pipefail

SD_DIR=/opt/sd-cpp
SRC_DIR="$SD_DIR/src"
BUILD_DIR="$SRC_DIR/build"
MODELS_DIR="$SD_DIR/models"
BUILD_FRONTEND="${BUILD_FRONTEND:-false}"

log() { echo "[provision-sd] $*"; }

# ---------------------------------------------------------------------------
# 0. Wait for network/DNS (container just booted)
# ---------------------------------------------------------------------------
for _ in $(seq 1 30); do
  getent hosts huggingface.co >/dev/null 2>&1 && break
  log "waiting for DNS/network..."; sleep 2
done

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. Build + runtime dependencies
#    mesa-vulkan-drivers = RADV ICD (the actual GPU driver userspace)
#    libvulkan1 = loader, vulkan-tools = vulkaninfo
#    glslc/spirv = shader compilation for the ggml-vulkan backend
# ---------------------------------------------------------------------------
log "installing apt packages"
apt-get update -qq
apt-get install -y -qq \
  build-essential cmake git pkg-config ca-certificates curl \
  mesa-vulkan-drivers libvulkan1 libvulkan-dev vulkan-tools \
  spirv-headers libgomp1 python3
# shader compiler — package name differs across releases; try both. Don't mask
# total absence: warn loudly so a build failure later is easy to trace.
apt-get install -y -qq glslc || apt-get install -y -qq glslang-tools || \
  log "WARNING: no glslc/glslang-tools package installed — Vulkan shader build may fail"

# Optional web UI frontend toolchain (Node 20 + pnpm)
if [ "$BUILD_FRONTEND" = "true" ]; then
  log "installing Node 20 + pnpm for the server frontend"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
  npm install -g pnpm
fi

# ---------------------------------------------------------------------------
# 2. Confirm the iGPU is visible via Vulkan/RADV (non-fatal — log only)
# ---------------------------------------------------------------------------
log "vulkan device check:"
vulkaninfo 2>/dev/null | grep -E "deviceName|driverName" | head -4 || \
  log "WARNING: vulkaninfo found no device — check /dev/dri passthrough"

# ---------------------------------------------------------------------------
# 3. Build stable-diffusion.cpp with the Vulkan backend
# ---------------------------------------------------------------------------
mkdir -p "$SD_DIR"
if [ ! -d "$SRC_DIR/.git" ]; then
  log "cloning stable-diffusion.cpp"
  git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$SRC_DIR"
else
  log "updating stable-diffusion.cpp"
  git -C "$SRC_DIR" pull --recurse-submodules
  git -C "$SRC_DIR" submodule update --init --recursive
fi

FRONTEND_FLAG="-DSD_SERVER_BUILD_FRONTEND=OFF"
[ "$BUILD_FRONTEND" = "true" ] && FRONTEND_FLAG="-DSD_SERVER_BUILD_FRONTEND=ON"

log "configuring cmake (Vulkan, Release, frontend=$BUILD_FRONTEND)"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -DSD_VULKAN=ON -DCMAKE_BUILD_TYPE=Release $FRONTEND_FLAG

# ggml/Vulkan translation units are RAM-heavy; an unbounded -j$(nproc) can OOM
# the container mid-build (shared host RAM with the LLM LXC). Cap jobs: honor
# BUILD_JOBS if set, else min(nproc, MemAvailable/2GB), floor 1.
JOBS="${BUILD_JOBS:-0}"
if [ "$JOBS" -le 0 ] 2>/dev/null || [ "$JOBS" = "0" ]; then
  mem_jobs=$(awk '/MemAvailable/{j=int($2/2000000); print (j<1?1:j)}' /proc/meminfo)
  ncpu=$(nproc)
  JOBS=$(( mem_jobs < ncpu ? mem_jobs : ncpu ))
fi
log "building with -j$JOBS (this takes a while on the 780M box)"
cmake --build "$BUILD_DIR" --config Release -j"$JOBS"

if [ ! -x "$BUILD_DIR/bin/sd-server" ]; then
  log "ERROR: sd-server not produced. Contents of build/bin:"
  ls -la "$BUILD_DIR/bin" || true
  exit 1
fi
log "built: $("$BUILD_DIR/bin/sd-server" --help 2>&1 | head -1 || echo sd-server)"

# ---------------------------------------------------------------------------
# 4. Download models (resumable, skip existing)
# ---------------------------------------------------------------------------
mkdir -p "$MODELS_DIR"
if [ -f /root/sd-models.tsv ]; then
  while IFS=$'\t' read -r file url; do
    [ -z "${file:-}" ] && continue
    case "$file" in \#*) continue ;; esac
    dest="$MODELS_DIR/$file"
    meta="$dest.url"
    # Skip only if the file exists AND was fetched from this exact URL. A
    # changed URL (same basename) must re-download — otherwise stale weights
    # are silently kept and the apply falsely reports success.
    if [ -f "$dest" ] && [ -f "$meta" ] && [ "$(cat "$meta")" = "$url" ]; then
      log "model up-to-date: $file"; continue
    fi
    # A leftover .part from a different URL can't be safely resumed — drop it.
    if [ -f "$dest.part" ] && { [ ! -f "$meta" ] || [ "$(cat "$meta")" != "$url" ]; }; then
      rm -f "$dest.part"
    fi
    log "downloading $file"
    curl -L --fail --retry 5 --retry-delay 5 -C - -o "$dest.part" "$url"
    # Guard against a short/partial body curl exited 0 on.
    sz=$(stat -c%s "$dest.part" 2>/dev/null || echo 0)
    if [ "$sz" -lt 100000 ]; then
      log "ERROR: $file is only $sz bytes — treating as failed download"
      rm -f "$dest.part"; exit 1
    fi
    mv "$dest.part" "$dest"
    printf '%s' "$url" > "$meta"
  done < /root/sd-models.tsv
fi

# ---------------------------------------------------------------------------
# 5. Install the sd-swap proxy, model registry, switcher, env
# ---------------------------------------------------------------------------
install -m 0755 /root/sd-swap.py "$SD_DIR/sd-swap.py"
install -m 0755 /root/sd-switch.sh /usr/local/bin/sd-switch
install -m 0644 /root/models.json "$SD_DIR/models.json"
install -m 0644 /root/sd-swap.env "$SD_DIR/sd-swap.env"

# Pull the two ports out of the env file WITHOUT sourcing it — SDSWAP_EXTRA_FLAGS
# holds space-separated flags that a bash `source` would try to execute.
SDSWAP_PORT=$(grep -E '^SDSWAP_PORT=' "$SD_DIR/sd-swap.env" | cut -d= -f2)
SDSWAP_BACKEND_PORT=$(grep -E '^SDSWAP_BACKEND_PORT=' "$SD_DIR/sd-swap.env" | cut -d= -f2)
SDSWAP_PORT=${SDSWAP_PORT:-7860}
SDSWAP_BACKEND_PORT=${SDSWAP_BACKEND_PORT:-17860}

# ---------------------------------------------------------------------------
# 6. systemd service — sd-swap (replaces the old direct sd-server unit)
# ---------------------------------------------------------------------------
# Retire the pre-proxy unit if an earlier apply installed it.
if systemctl list-unit-files 2>/dev/null | grep -q '^sd-server\.service'; then
  log "removing legacy sd-server.service (superseded by sd-swap)"
  systemctl disable --now sd-server.service 2>/dev/null || true
  rm -f /etc/systemd/system/sd-server.service
fi

cat > /etc/systemd/system/sd-swap.service <<UNIT
[Unit]
Description=sd-swap proxy (model-swapping front end for stable-diffusion.cpp)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SD_DIR
EnvironmentFile=$SD_DIR/sd-swap.env
# Reap an orphaned backend from a previous proxy crash before (re)starting.
ExecStartPre=-/usr/bin/pkill -f "sd-server --listen-ip 127.0.0.1 --listen-port $SDSWAP_BACKEND_PORT"
ExecStart=/usr/bin/python3 $SD_DIR/sd-swap.py
Restart=on-failure
RestartSec=5
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT

log "enabling sd-swap"
systemctl daemon-reload
systemctl enable --now sd-swap

# ---------------------------------------------------------------------------
# 7. Smoke check — the proxy lists the full model registry (no backend loaded yet)
# ---------------------------------------------------------------------------
sleep 3
systemctl --no-pager --full status sd-swap | head -12 || true
if curl -fsS "http://127.0.0.1:${SDSWAP_PORT}/sdapi/v1/sd-models" > /tmp/sdmodels.json 2>/dev/null; then
  log "sd-swap up; models: $(python3 -c 'import json;print([m["title"] for m in json.load(open("/tmp/sdmodels.json"))])')"
else
  log "sd-swap not answering on :${SDSWAP_PORT} yet (check journalctl -u sd-swap)"
fi
log "done."
