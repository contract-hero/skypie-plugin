#!/usr/bin/env bash
#
# publish-release.sh — build skypie-mcp, package it, record its checksum in
# bin/manifest.json, and publish the assets as a GitHub release on this repo.
#
# The server source is private. This script is the bridge: a maintainer runs it
# from a machine that has both checkouts, and it produces the public artifacts
# the launcher downloads.
#
#   ./scripts/publish-release.sh 0.1.0 ~/workspace/skypie
#
# It stops before uploading unless you pass --publish, so you can inspect the
# packaged assets and the manifest diff first.
set -euo pipefail

VERSION="${1:-}"
SOURCE_REPO="${2:-}"
PUBLISH=0
for arg in "$@"; do [ "$arg" = "--publish" ] && PUBLISH=1; done

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${PLUGIN_ROOT}/bin/manifest.json"
DIST="${PLUGIN_ROOT}/dist"

die() { echo "error: $*" >&2; exit 1; }

[ -n "${VERSION}" ]     || die "usage: $0 <version> <path-to-skypie-source-repo> [--publish]"
[ -n "${SOURCE_REPO}" ] || die "usage: $0 <version> <path-to-skypie-source-repo> [--publish]"
[ -d "${SOURCE_REPO}/crates/skypie-mcp" ] \
  || die "'${SOURCE_REPO}' does not look like the skypie source repo (no crates/skypie-mcp)."
command -v gh >/dev/null || die "the gh CLI is required."

REPO="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['repo'])" "${MANIFEST}")"

rm -rf "${DIST}"; mkdir -p "${DIST}"

# macOS only for now. Add linux targets here when the server is built for them.
TARGETS="aarch64-apple-darwin:darwin-arm64 x86_64-apple-darwin:darwin-x86_64"

built=()
for pair in ${TARGETS}; do
  target="${pair%%:*}"
  platform="${pair##*:}"

  if ! rustup target list --installed 2>/dev/null | grep -qx "${target}"; then
    echo "skip ${platform}: rust target ${target} is not installed" >&2
    echo "     add it with: rustup target add ${target}" >&2
    continue
  fi

  echo "building ${platform}..."
  ( cd "${SOURCE_REPO}" && cargo build --release -p skypie-mcp --target "${target}" )

  binary="${SOURCE_REPO}/target/${target}/release/skypie-mcp"
  [ -x "${binary}" ] || die "expected a binary at ${binary}."

  asset="skypie-mcp-${VERSION}-${platform}.tar.gz"
  tar -czf "${DIST}/${asset}" -C "$(dirname "${binary}")" skypie-mcp
  sha="$(shasum -a 256 "${DIST}/${asset}" | awk '{print $1}')"
  echo "  ${asset}  ${sha}"
  built+=("${platform}:${asset}:${sha}")
done

[ "${#built[@]}" -gt 0 ] || die "nothing was built; install at least one rust target."

python3 - "${MANIFEST}" "${VERSION}" "${built[@]}" <<'PY'
import json, sys
manifest_path, version, *entries = sys.argv[1:]
m = json.load(open(manifest_path))
m["version"] = version
m["assets"] = {}
for e in entries:
    platform, name, sha = e.split(":")
    m["assets"][platform] = {"name": name, "sha256": sha}
json.dump(m, open(manifest_path, "w"), indent=2)
open(manifest_path, "a").write("\n")
print(f"manifest pinned to {version} with {len(m['assets'])} asset(s)")
PY

if [ "${PUBLISH}" != 1 ]; then
  cat >&2 <<MSG

Built into ${DIST} and updated bin/manifest.json. Nothing was uploaded.
Review the manifest diff, then re-run with --publish to create the release.
MSG
  exit 0
fi

echo "creating release v${VERSION} on ${REPO}..."
gh release create "v${VERSION}" "${DIST}"/*.tar.gz \
  --repo "${REPO}" \
  --title "v${VERSION}" \
  --notes "skypie-mcp ${VERSION}. Checksums are pinned in bin/manifest.json."

echo "done. Commit the updated bin/manifest.json so the launcher points at this release."
