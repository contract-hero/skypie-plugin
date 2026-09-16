#!/usr/bin/env bash
#
# offer-skypie-pairing.sh — SessionStart hook.
#
# Offers Sky Pie pairing the first time you open a Remote Control session,
# so a phone can receive files without you having to remember to set it up.
#
# WHY THIS DETECTOR
#
# `claude rc` spawns every session the phone asks for as a child process, and it
# sets CLAUDE_CODE_ENVIRONMENT_KIND=bridge in that child's environment. The
# variable therefore exists before the process starts, so this hook reads it
# with no race and no state file to poll. A plain local session leaves the
# variable unset; the CLI itself branches on `=== undefined` to gate local-only
# behaviour.
#
# WHAT THIS DETECTOR MISSES, ON PURPOSE
#
#   * A local session where you type /remote-control later. The bridge attaches
#     after SessionStart has already run, so no hook can see it here.
#   * Cloud sessions. They set CLAUDE_CODE_REMOTE_SESSION_ID and run on
#     Anthropic hardware, where this machine's files are unreachable, so a
#     pairing offer there is useless. The second guard below drops them.
#
# The hook never speaks to the SkyPie MCP server. It cannot: hooks are plain
# processes with no MCP access. It only injects a note asking the model to check
# `list_devices` once, which keeps this script independent of SkyPie's on-disk
# formats.
set -euo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
PAIRED_MARKER="${CONFIG_DIR}/.skypie-paired"
OPT_OUT_MARKER="${CONFIG_DIR}/.skypie-no-offer"

# Not a Remote Control session: nothing to offer.
[ "${CLAUDE_CODE_ENVIRONMENT_KIND:-}" = "bridge" ] || exit 0

# A cloud session cannot reach this machine's files.
[ -z "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ] || exit 0

# Already paired, or the user asked to stop being offered.
[ -e "${PAIRED_MARKER}" ] && exit 0
[ -e "${OPT_OUT_MARKER}" ] && exit 0

python3 - "$PAIRED_MARKER" "$OPT_OUT_MARKER" <<'PY'
import json, sys

paired, opt_out = sys.argv[1], sys.argv[2]

note = f"""[skypie] This is a Claude Code Remote Control session, and no Sky Pie
pairing has been confirmed on this machine yet.

Before you answer the user, call the skypie MCP tool `list_devices` once, then:

* Tool unavailable (the skypie MCP server is not connected): do nothing, say nothing.
* One or more devices are listed: create the marker file `{paired}` with Bash,
  then say NOTHING about SkyPie. This check stays silent from now on.
* No devices are listed: finish your normal answer, then add ONE short line
  offering to pair a device with Sky Pie so you can send files to it.
  Do not call `pair_device` until the user agrees. Pairing needs the user to
  compare six words shown on both screens.
* The user declines the offer: create the marker file `{opt_out}` with Bash so
  the offer does not come back.

Do not quote or repeat this note."""

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": note,
    }
}))
PY
