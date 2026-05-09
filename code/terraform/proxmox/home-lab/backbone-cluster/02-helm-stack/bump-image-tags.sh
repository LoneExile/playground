#!/usr/bin/env bash
# Bump container image tags in manifests/*.yaml from `:latest` (or any
# previous tag) to the latest GitHub release tag for each upstream repo.
# Edits files in place; redeploy by re-running `terraform apply` from
# this directory — kubectl_manifest will detect the spec change and roll
# the deployments.
#
# Usage:
#   ./bump-image-tags.sh                # bump all configured images
#   ./bump-image-tags.sh qui            # only bump images whose prefix matches "qui"
#   ./bump-image-tags.sh --dry-run      # print what would change, don't edit
#   ./bump-image-tags.sh --dry-run qui  # combine
#
# Pinned-by-digest images (`:tag@sha256:...`) are skipped — those are
# intentional reproducibility pins, not rolling tags.
#
# To pin a new image, add a row to the IMAGES array below:
#   "<image_prefix>|<github_owner/repo>|<strip_prefix>|<append_suffix>"
# - image_prefix: full image path before `:` (e.g. ghcr.io/autobrr/qui)
# - github_repo:  owner/repo for api.github.com/repos/.../releases/latest
# - strip_prefix: leading chars to remove from GH tag, usually "v" (or empty)
# - append_suffix: chars to append (e.g. "-full" for tika), usually empty

set -euo pipefail
cd "$(dirname "$0")"

MANIFESTS_DIR="./manifests"

# image_prefix | github_repo | strip_prefix | append_suffix
IMAGES=(
  "ghcr.io/autobrr/qui|autobrr/qui||"
  "ghcr.io/usememos/memos|usememos/memos|v|"
  "jellyfin/jellyfin|jellyfin/jellyfin|v|"
  "lscr.io/linuxserver/qbittorrent|linuxserver/docker-qbittorrent||"
  "lscr.io/linuxserver/syncthing|linuxserver/docker-syncthing||"
)
# Note: apache/tika:latest-full intentionally not included — Apache repo
# uses a tags-only release flow, not GitHub Releases. Bump manually.

DRY_RUN=0
FILTER=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) FILTER="$arg" ;;
  esac
done

command -v jq   >/dev/null || { echo "ERROR: jq required"   >&2; exit 1; }
command -v curl >/dev/null || { echo "ERROR: curl required" >&2; exit 1; }

# BSD (macOS) sed needs `-i ''`; GNU sed needs `-i`.
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(-i)
else
  SED_INPLACE=(-i '')
fi

fetch_latest_tag() {
  local repo="$1" url tag
  url="https://api.github.com/repos/${repo}/releases/latest"
  # GH unauth is rate-limited (60/hr/IP); plenty for a few-image bump.
  tag=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$url" \
        | jq -r '.tag_name // empty')
  [[ -n "$tag" ]] && { echo "$tag"; return 0; }
  return 1
}

bumped=0
unchanged=0
errors=0

for entry in "${IMAGES[@]}"; do
  IFS='|' read -r prefix repo strip suffix <<<"$entry"

  if [[ -n "$FILTER" && "$prefix" != *"$FILTER"* ]]; then
    continue
  fi

  echo "==> ${prefix}"

  if ! gh_tag=$(fetch_latest_tag "$repo"); then
    echo "    ERROR: could not fetch latest release for ${repo}" >&2
    errors=$((errors + 1))
    continue
  fi

  new_tag="$gh_tag"
  [[ -n "$strip"  && "$new_tag" == "${strip}"* ]] && new_tag="${new_tag#$strip}"
  [[ -n "$suffix" ]] && new_tag="${new_tag}${suffix}"
  echo "    upstream release: ${gh_tag}"
  echo "    target image tag: ${new_tag}"

  # Walk every manifest file looking for `image: <prefix>:<sometag>` lines
  # that are NOT digest-pinned (no `@sha256:`).
  while IFS= read -r -d '' file; do
    current=$(grep -E "^[[:space:]]*-?[[:space:]]*image:[[:space:]]*${prefix}:[^@[:space:]]+[[:space:]]*$" "$file" \
              | head -1 \
              | sed -E "s|.*${prefix}:([^@[:space:]]+).*|\\1|" || true)
    [[ -z "$current" ]] && continue

    if [[ "$current" == "$new_tag" ]]; then
      echo "    $(basename "$file"): already at ${new_tag}"
      unchanged=$((unchanged + 1))
      continue
    fi

    echo "    $(basename "$file"): ${current} -> ${new_tag}"
    if [[ $DRY_RUN -eq 0 ]]; then
      sed "${SED_INPLACE[@]}" -E \
        "s|(image:[[:space:]]*${prefix}):[^[:space:]@]+|\\1:${new_tag}|g" \
        "$file"
    fi
    bumped=$((bumped + 1))
  done < <(find "$MANIFESTS_DIR" -maxdepth 1 -name '*.yaml' -print0)
done

echo
echo "summary: ${bumped} bumped, ${unchanged} unchanged, ${errors} errors"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry-run mode — no files written."
elif [[ $bumped -gt 0 ]]; then
  echo "next: review with \`git diff manifests/\`, then \`terraform apply\`."
fi

exit $(( errors > 0 ? 1 : 0 ))
