#!/usr/bin/env bash
# Launches sd-server from the model config in /opt/sd-cpp/server.env.
# Called by the sd-server systemd unit. Edit server.env (or use `sd-switch`)
# and `systemctl restart sd-server` to change models.
set -euo pipefail

SD_DIR=/opt/sd-cpp
BIN_DIR="$SD_DIR/src/build/bin"

# shellcheck disable=SC1091
[ -f "$SD_DIR/server.env" ] && . "$SD_DIR/server.env"

# llama.cpp/sd.cpp Vulkan libs sit next to the binary
export LD_LIBRARY_PATH="$BIN_DIR:${LD_LIBRARY_PATH:-}"

BIN="$BIN_DIR/sd-server"
if [ ! -x "$BIN" ]; then
  echo "sd-server not found at $BIN" >&2
  ls -la "$BIN_DIR" >&2 || true
  exit 1
fi

ARGS=( --listen-ip 0.0.0.0 --listen-port "${SD_PORT:-7860}" )

case "${SD_MODE:-single}" in
  single)
    : "${SD_MODEL:?SD_MODEL unset in server.env}"
    ARGS+=( --model "$SD_MODEL" )
    ;;
  flux)
    : "${SD_DIFFUSION_MODEL:?unset in server.env (flux mode)}" \
      "${SD_VAE:?unset in server.env (flux mode)}" \
      "${SD_CLIP_L:?unset in server.env (flux mode)}" \
      "${SD_T5XXL:?unset in server.env (flux mode)}"
    ARGS+=( --diffusion-model "$SD_DIFFUSION_MODEL"
            --vae "$SD_VAE"
            --clip_l "$SD_CLIP_L"
            --t5xxl "$SD_T5XXL" )
    ;;
  *)
    echo "bad SD_MODE='$SD_MODE' (want single|flux)" >&2
    exit 1
    ;;
esac

# word-split extra flags intentionally
# shellcheck disable=SC2206
ARGS+=( ${SD_EXTRA_FLAGS:-} )

echo "exec sd-server (mode=${SD_MODE:-single}): ${ARGS[*]}"
exec "$BIN" "${ARGS[@]}"
