#!/usr/bin/env bash
# Switch the running model mode and restart the service.
#   sd-switch single   # one-file checkpoint (SDXL-Turbo)
#   sd-switch flux      # multi-file FLUX.1-schnell
set -euo pipefail

mode="${1:-}"
case "$mode" in
  single|flux) ;;
  *) echo "usage: sd-switch single|flux" >&2; exit 1 ;;
esac

env_file=/opt/sd-cpp/server.env
[ -f "$env_file" ] || { echo "missing $env_file" >&2; exit 1; }

if grep -q '^SD_MODE=' "$env_file"; then
  sed -i "s/^SD_MODE=.*/SD_MODE=$mode/" "$env_file"
else
  echo "SD_MODE=$mode" >> "$env_file"
fi

echo "SD_MODE -> $mode; restarting sd-server"
systemctl restart sd-server
echo "follow: journalctl -u sd-server -f"
