#!/usr/bin/env bash
#
# skypies-mcp-launch.sh — find the skypies app and exec the MCP server it ships.
#
# The plugin is a companion to the skypies Mac app. The app bundles the
# server at skypies.app/Contents/MacOS/skypies-mcp, signed with the app, so the
# server and the app always come from the same build. Nothing is downloaded.
#
# Resolution order:
#
#   1. $SKYPIES_MCP_BIN              — explicit override (a dev build).
#   2. /Applications, ~/Applications — the usual install places.
#   3. Spotlight, by bundle id       — the app installed somewhere else.
#
# Anything on stdout would corrupt the MCP stdio stream, so every message goes
# to stderr, which the MCP host captures as MCP server logs.
#
# `skypies-mcp-launch.sh hook <event>` runs the server's hook subcommand for
# hooks/hooks.json. A hook fires on every Read in every session, so in hook
# mode the launcher never logs and a missing app means silence and exit 0.
set -euo pipefail

BUNDLE_ID="ai.skypies.skypies"
DOWNLOAD_URL="https://github.com/contract-hero/skypies-releases/releases/latest/download/skypies-universal.dmg"
SERVER="Contents/MacOS/skypies-mcp"

HOOK_MODE=false
[ "${1:-}" = "hook" ] && HOOK_MODE=true

log() { [ "${HOOK_MODE}" = true ] || echo "skypies: $*" >&2; }

die() {
  [ "${HOOK_MODE}" = true ] && exit 0
  log "$*"
  exit 1
}

# --- 1. explicit override ---------------------------------------------------
if [ -n "${SKYPIES_MCP_BIN:-}" ]; then
  [ -f "${SKYPIES_MCP_BIN}" ] && [ -x "${SKYPIES_MCP_BIN}" ] \
    || die "SKYPIES_MCP_BIN is set to '${SKYPIES_MCP_BIN}', but that is not an executable file."
  log "using SKYPIES_MCP_BIN=${SKYPIES_MCP_BIN}"
  exec "${SKYPIES_MCP_BIN}" "$@"
fi

[ "$(uname -s)" = "Darwin" ] || die "skypies runs on macOS only."

# Mac bundles that exist but ship no server (an app older than the plugin).
# A string, not an array: an empty "${arr[@]}" fails under set -u in bash 3.2.
stale=""
HOME_APP="${HOME:+${HOME}/Applications/skypies.app}"

try_app() {
  if [ -f "$1/${SERVER}" ] && [ -x "$1/${SERVER}" ]; then
    log "using $1/${SERVER}"
    exec "$1/${SERVER}" "${@:2}" 3<&-
  fi
  [ -d "$1/Contents/MacOS" ] && stale="${stale}  $1"$'\n'
  return 0
}

# --- 2. usual install places ------------------------------------------------
try_app "/Applications/skypies.app" "$@"
[ -n "${HOME_APP}" ] && try_app "${HOME_APP}" "$@"

# --- 3. Spotlight -----------------------------------------------------------
# Skip build trees (a bundle under `target/` is a dev build) and the places
# step 2 checked. mdfind's stderr stays visible: it is the MCP log.
spotlight="$(mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'")" \
  || log "Spotlight search failed; only /Applications and ~/Applications were checked."
# The list comes in on fd 3: stdin must reach the server untouched, since it
# carries the MCP stream or the hook JSON.
while IFS= read -r app <&3; do
  case "${app}" in ''|*/target/*|/Applications/skypies.app) continue ;; esac
  [ "${app}" = "${HOME_APP}" ] && continue
  try_app "${app}" "$@"
done 3<<< "${spotlight}"

if [ -n "${stale}" ]; then
  die "found the skypies app, but it has no MCP server at ${SERVER}:
${stale}This app is older than the plugin. Update it from ${DOWNLOAD_URL},
replace the old copy, open it once, then restart your MCP host."
fi
die "the skypies app is not installed.
This plugin runs the MCP server that ships inside the app.
Download it from ${DOWNLOAD_URL}, drag skypies to Applications, and open it once.
Then restart your MCP host."
