#!/usr/bin/env bash
# Copy the Unraid template into the separate templates repo, following its
# folder-per-app layout. Requires GH_TOKEN with write access to that repo.
set -euo pipefail

TARGET_REPO="${TARGET_REPO:-BBergle/unraid-templates}"
TARGET_PATH="${TARGET_PATH:-plezy-relay/plezy-relay.xml}"
TARGET_ICON="${TARGET_ICON:-plezy-relay/plezy.png}"
TEMPLATE="${TEMPLATE_FILE:-templates/plezy-relay.xml}"
ICON="${ICON_FILE:-templates/plezy-relay-icon.png}"
RELEASE="${RELEASE:-}"

put() { # path local-file message
  local remote="$1" local_file="$2" message="$3" sha
  sha=$(gh api "repos/${TARGET_REPO}/contents/${remote}" --jq '.sha' 2>/dev/null || true)
  local args=(
    --method PUT "repos/${TARGET_REPO}/contents/${remote}"
    -f message="$message"
    -f content="$(base64 < "$local_file" | tr -d '\n')"
  )
  [[ -n "$sha" ]] && args+=(-f sha="$sha")
  if gh api "${args[@]}" >/dev/null; then
    echo "mirrored ${remote}"
  else
    echo "::warning::failed to mirror ${remote}"; return 1
  fi
}

# The mirrored copy must advertise its own location, or Unraid/CA would re-fetch
# the canonical repo's file and the two would silently diverge.
mirrored=$(mktemp)
sed "s|https://raw.githubusercontent.com/BBergle/plezy-relay/main/templates/plezy-relay.xml|https://raw.githubusercontent.com/${TARGET_REPO}/main/${TARGET_PATH}|; \
      s|https://raw.githubusercontent.com/BBergle/plezy-relay/main/templates/plezy-relay-icon.png|https://raw.githubusercontent.com/${TARGET_REPO}/main/${TARGET_ICON}|" \
  "$TEMPLATE" > "$mirrored"

put "$TARGET_PATH" "$mirrored" "plezy-relay: sync template${RELEASE:+ for }${RELEASE}"
put "$TARGET_ICON" "$ICON"     "plezy-relay: sync icon" || true
rm -f "$mirrored"
