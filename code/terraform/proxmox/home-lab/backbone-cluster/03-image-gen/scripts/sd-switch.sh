#!/usr/bin/env bash
# Pick the image model the sd-swap proxy serves (loads on next generation),
# or list what's available.
#   sd-switch                 # list models + which is desired/running
#   sd-switch list            # list model titles
#   sd-switch <title>         # set desired model (swaps on next image)
set -euo pipefail

PORT="${SDSWAP_PORT:-7860}"
BASE="http://127.0.0.1:${PORT}"

case "${1:-status}" in
  status)
    echo "available:"
    curl -s "${BASE}/sdapi/v1/sd-models" | python3 -c 'import sys,json;[print("  ",m["title"]) for m in json.load(sys.stdin)]'
    curl -s "${BASE}/" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("desired:",d.get("desired"),"| running:",d.get("running"))'
    ;;
  list)
    curl -s "${BASE}/sdapi/v1/sd-models" | python3 -c 'import sys,json;[print(m["title"]) for m in json.load(sys.stdin)]'
    ;;
  *)
    curl -s -X POST "${BASE}/sdapi/v1/options" -H 'Content-Type: application/json' \
      -d "{\"sd_model_checkpoint\":\"$1\"}" >/dev/null
    echo "image model -> $1 (loads on next generation)"
    ;;
esac
