#!/usr/bin/env bash
# Decide what (if anything) needs publishing for the newest upstream plezy release.
#
# Emits GitHub Actions outputs:
#   action  - none | build | retag
#   release - upstream release tag, e.g. 2.19.1
#   sha     - upstream commit sha for that tag
#   tree    - git tree sha of upstream server/ at that tag
#   source  - (retag only) an already-published tag holding the identical build
#   tags    - newline-separated full image refs to publish
#
# Most plezy releases never touch server/. When the server/ tree is byte-identical
# to something already published we add refs to that manifest instead of rebuilding,
# which keeps the digest stable and turns a multi-minute job into a few seconds.
set -euo pipefail

UPSTREAM="${UPSTREAM_REPO:-edde746/plezy}"
IMAGE="${IMAGE_NAME:?IMAGE_NAME must be set}"
STATE="${STATE_FILE:-state/builds.json}"
# server/Dockerfile first appears upstream in 1.24.0; older tags cannot be built.
MIN_RELEASE="${MIN_RELEASE:-1.24.0}"

out() { echo "$1=$2" >>"${GITHUB_OUTPUT:-/dev/stdout}"; }

# Sortable integer key so 2.9.0 < 2.10.0 (plain string sort gets this wrong).
semver_key() {
  awk -F. '{printf "%d\n", ($1*1000000)+($2*1000)+$3}' <<<"${1//[^0-9.]/}"
}

release="${FORCE_RELEASE:-}"
if [[ -z "$release" ]]; then
  release=$(gh api "repos/${UPSTREAM}/releases/latest" --jq '.tag_name')
fi
echo "newest upstream release: ${release}"

if (( $(semver_key "$release") < $(semver_key "$MIN_RELEASE") )); then
  echo "release ${release} predates ${MIN_RELEASE} (no server/ directory) - nothing to do"
  out action none; exit 0
fi

[[ -f "$STATE" ]] || echo '{"processed":[],"trees":{}}' >"$STATE"

if [[ "${FORCE_REBUILD:-false}" != "true" ]] \
   && jq -e --arg r "$release" '.processed | index($r)' "$STATE" >/dev/null; then
  echo "release ${release} already published - nothing to do"
  out action none; exit 0
fi

sha=$(gh api "repos/${UPSTREAM}/commits/${release}" --jq '.sha')
tree=$(gh api "repos/${UPSTREAM}/git/trees/${release}" --jq '.tree[] | select(.path=="server") | .sha')
if [[ -z "$tree" ]]; then
  echo "::error::no server/ directory at ${release}"; exit 1
fi
echo "commit=${sha} server-tree=${tree}"

major="${release%%.*}"
minor="${release%.*}"

# Moving tags only advance; they must never regress to an older release.
newest_processed=$(jq -r '.processed[]? ' "$STATE" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
tags="${IMAGE}:${release}"$'\n'"${IMAGE}:sha-${sha:0:7}"
if [[ -z "$newest_processed" ]] || (( $(semver_key "$release") >= $(semver_key "$newest_processed") )); then
  tags+=$'\n'"${IMAGE}:${minor}"$'\n'"${IMAGE}:${major}"$'\n'"${IMAGE}:latest"
else
  echo "note: ${release} is older than ${newest_processed}; not moving latest/${major}/${minor}"
fi

out release "$release"
out sha "$sha"
out tree "$tree"
{ echo "tags<<__EOF__"; echo "$tags"; echo "__EOF__"; } >>"${GITHUB_OUTPUT:-/dev/stdout}"

source_tag=$(jq -r --arg t "$tree" '.trees[$t] // empty' "$STATE")
if [[ -n "$source_tag" && "${FORCE_REBUILD:-false}" != "true" ]]; then
  echo "server/ unchanged since ${source_tag} - re-tagging instead of rebuilding"
  out action retag
  out source "$source_tag"
else
  echo "server/ changed (or rebuild forced) - full build required"
  out action build
fi
