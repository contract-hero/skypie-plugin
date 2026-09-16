#!/usr/bin/env bash
#
# skypie-mcp-launch.sh — resolve, verify and exec the skypie-mcp stdio server.
#
# The skypie-mcp source lives in a PRIVATE repository, so this public plugin
# cannot build it. Instead it downloads a pinned release asset from the plugin
# repository, checks the asset against the SHA-256 recorded in bin/manifest.json,
# and caches the result. A binary that fails the checksum is deleted, never run.
#
# Resolution order:
#
#   1. $SKYPIE_MCP_BIN                 — explicit override, wins over everything.
#   2. cache                          — a verified download from an earlier run.
#   3. $SKYPIE_SOURCE_REPO/target/...  — a maintainer's local checkout of the
#                                       private source repo. Never downloads.
#   4. $PATH                          — a system-wide install.
#   5. download                       — fetch, verify, cache, exec.
#
# Anything on stdout would corrupt the MCP stdio stream, so every message goes
# to stderr, which Claude Code captures as MCP server logs.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="${PLUGIN_ROOT}/bin/manifest.json"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/skypie-plugin"

log() { echo "skypie: $*" >&2; }

die() { log "$*"; exit 1; }

# --- 1. explicit override ---------------------------------------------------
if [ -n "${SKYPIE_MCP_BIN:-}" ]; then
  [ -x "${SKYPIE_MCP_BIN}" ] \
    || die "SKYPIE_MCP_BIN is set to '${SKYPIE_MCP_BIN}' but that file is not executable."
  exec "${SKYPIE_MCP_BIN}" "$@"
fi

# --- platform key -----------------------------------------------------------
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *)      die "unsupported operating system: $(uname -s)" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64)  arch=x86_64 ;;
  *)             die "unsupported architecture: $(uname -m)" ;;
esac
PLATFORM="${os}-${arch}"

# --- manifest ---------------------------------------------------------------
[ -f "${MANIFEST}" ] || die "missing ${MANIFEST}."

read -r VERSION REPO ASSET SHA256 <<EOF
$(python3 - "$MANIFEST" "$PLATFORM" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
a = m.get("assets", {}).get(sys.argv[2], {})
print(m.get("version", ""), m.get("repo", ""), a.get("name", ""), a.get("sha256", ""))
PY
)
EOF

CACHED="${CACHE_DIR}/skypie-mcp-${VERSION}-${PLATFORM}"

# --- 2. verified cache ------------------------------------------------------
[ -x "${CACHED}" ] && exec "${CACHED}" "$@"

# --- 3. maintainer's local source checkout ----------------------------------
if [ -n "${SKYPIE_SOURCE_REPO:-}" ]; then
  for build in release debug; do
    candidate="${SKYPIE_SOURCE_REPO}/target/${build}/skypie-mcp"
    [ -x "${candidate}" ] && exec "${candidate}" "$@"
  done
  log "SKYPIE_SOURCE_REPO is set but no skypie-mcp build was found under it; continuing."
fi

# --- 4. system install ------------------------------------------------------
if command -v skypie-mcp >/dev/null 2>&1; then
  exec skypie-mcp "$@"
fi

# --- 5. download ------------------------------------------------------------
if [ -z "${ASSET}" ] || [ -z "${SHA256}" ]; then
  die "no published release for ${PLATFORM} in bin/manifest.json.
Maintainers: build the server, then run scripts/publish-release.sh.
Everyone else: install skypie-mcp on your PATH, or set SKYPIE_MCP_BIN."
fi

URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"
mkdir -p "${CACHE_DIR}"

# Thirty-two Remote Control sessions can start at once. A mkdir lock is atomic,
# so exactly one of them downloads and the rest wait and then hit the cache.
LOCK="${CACHE_DIR}/.lock-${VERSION}-${PLATFORM}"
acquired=0
for _ in $(seq 1 120); do
  if mkdir "${LOCK}" 2>/dev/null; then acquired=1; break; fi
  [ -x "${CACHED}" ] && exec "${CACHED}" "$@"
  sleep 1
done
[ "${acquired}" = 1 ] || die "timed out waiting for another session to finish downloading skypie-mcp.
If no download is running, remove the stale lock: rm -rf '${LOCK}'"
# shellcheck disable=SC2064
trap "rmdir '${LOCK}' 2>/dev/null || true" EXIT

# Another session may have finished while we waited for the lock.
[ -x "${CACHED}" ] && exec "${CACHED}" "$@"

TMP="$(mktemp -d "${CACHE_DIR}/dl.XXXXXX")"
trap "rm -rf '${TMP}'; rmdir '${LOCK}' 2>/dev/null || true" EXIT

log "downloading skypie-mcp ${VERSION} for ${PLATFORM}..."
curl -fsSL --retry 3 --retry-delay 2 -o "${TMP}/${ASSET}" "${URL}" \
  || die "download failed: ${URL}"

actual="$(shasum -a 256 "${TMP}/${ASSET}" | awk '{print $1}')"
if [ "${actual}" != "${SHA256}" ]; then
  die "CHECKSUM MISMATCH for ${ASSET}.
  expected ${SHA256}
  actual   ${actual}
The download was discarded and nothing was executed."
fi

tar -xzf "${TMP}/${ASSET}" -C "${TMP}" \
  || die "cannot unpack ${ASSET}."
[ -f "${TMP}/skypie-mcp" ] || die "${ASSET} does not contain a skypie-mcp binary."

chmod +x "${TMP}/skypie-mcp"
# Rename inside the same filesystem, so the cache never holds a partial file.
mv -f "${TMP}/skypie-mcp" "${CACHED}"
log "installed ${CACHED}"

rm -rf "${TMP}"; rmdir "${LOCK}" 2>/dev/null || true
trap - EXIT
exec "${CACHED}" "$@"
