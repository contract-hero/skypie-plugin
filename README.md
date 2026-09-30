# skypies

Claude Code and Codex plugin for [skypies](https://contracthero.dev/skypies/),
the companion that lets your agents make links to the Mac app. Both hosts get
the MCP server (item 1) and the `artifact-links` skill, which makes the agent
mint a link for every deliverable it creates for you. Both hosts also get the
Stop hook (item 4); only Claude Code gets items 2 and 3 (see [Codex](#codex)):

1. The **`skypies` MCP server**, which ships inside the skypies app. It sends
   local files straight to your paired skypies devices over a direct,
   end-to-end encrypted peer-to-peer link. Nothing is uploaded to a server.
2. A **SessionStart hook**, which offers device pairing the first time you open
   a Claude Code Remote Control session, so your phone can receive files without
   you having to remember to set it up.
3. **Feedback hooks**, which put the comments you left on a file in skypies into
   the agent's context.
4. A **Stop hook**, which refuses to end a turn with a typed skypies link, or
   with a new deliverable that has no link.

## Install

The plugin needs the skypies app on your Mac.
[Download the DMG](https://github.com/contract-hero/skypies-releases/releases/latest/download/skypies-universal.dmg)
(universal, macOS 11+). Then install the plugin:

```
claude plugin marketplace add contract-hero/plugin-marketplace
claude plugin install skypies@contract-hero
```

The plugin downloads nothing. It runs the server at
`skypies.app/Contents/MacOS/skypies-mcp`, so the server and the app always come
from the same build. Update the app to update the server.

> If you already added `skypies` by hand with `claude mcp add`, remove that entry
> first with `claude mcp remove skypies`. Two servers with the same name is one
> too many.

## Codex

With the skypies Mac app installed, use Codex 0.153 or later:

```sh
codex plugin marketplace add contract-hero/plugin-marketplace
codex plugin add skypies@contract-hero
```

Start a new Codex thread to load the MCP server and `artifact-links` skill.
The Codex marketplace installs this repository's `main` branch.
Codex gets the MCP server, the link skill and the [Stop hook](#the-stop-hook).
Its manifest declares only the Stop hook, so Codex does not load
`hooks/hooks.json` and its Claude Code hooks.

Codex runs a plugin hook only after you trust it; until then it lists the hook
as untrusted and skips it, silently in `codex exec`. To trust it, run `/hooks`
in a Codex thread and trust the skypies Stop hook. Codex then writes this entry
to `~/.codex/config.toml`, with the hash it reports for the hook (app-server
`hooks/list`, field `currentHash`):

```toml
[hooks.state."skypies@contract-hero:plugin.json#hooks[0]:stop:0:0"]
trusted_hash = "sha256:…"
```

A plugin update that changes the hook command changes the hash, so the hook
must be trusted again.

`.codex-plugin/mcp.json` pre-approves four tools: `share_link`, `add_to_pie`,
`list_devices` and `server_status`. So Codex can send you a link even with
`approval_policy = "never"`. Every other tool (pairing, `forget_device`,
`beam_artifact`, `stop_beam`, `list_feedback`, `resolve_feedback`) still asks
for approval; with `approval_policy = "never"`, Codex refuses them.

## Tools

| Tool | Use it for |
|---|---|
| `share_link` | A link for the user's own paired devices; the device that opens it pulls the file from this Mac. |
| `beam_artifact` | A shareable link, or a recipient that is not paired. |
| `list_devices` | Which devices are paired, and whether each is online. |
| `list_feedback`, `resolve_feedback` | The comments the user left on an artifact, and marking one addressed. |
| `pair_device`, `pair_status`, `confirm_pairing` | Pairing a new device. |
| `server_status`, `stop_beam` | Diagnosing a failed send, and retiring a link. |

Pairing always needs a person: six words appear on both screens and the human
compares them before `confirm_pairing` runs.

## Send boundary

`SKYPIES_MCP_ROOTS` is a colon-separated list of directories from which
`beam_artifact` may send files. A path outside every root is refused.
`share_link` is **not confined to these roots**: it reaches only your own paired
devices, so links to your project files still work.

The plugin leaves the variable unset, so roots default to the server's launch
directory. In Codex, `.codex-plugin/mcp.json` sets `cwd` to `.`, which is the
installed plugin directory (`~/.codex/plugins/cache/contract-hero/skypies/<version>/`),
not your project. So by default `beam_artifact` in Codex cannot send your
project files; use `share_link` for your own devices. In Claude Code, set
`SKYPIES_MCP_ROOTS` deliberately in your MCP settings if you need broader beam
access. The launcher does not change directories or widen access.

## The feedback hooks

After a `Read`, `Write`, `Edit` or `MultiEdit`, the open comments on that file
go into the session, with the line and the quoted text. On each prompt, one
line names up to three files that have comments waiting. The agent fixes the
file and calls `resolve_feedback`, and you see your comment resolve.

These hooks run `skypies-mcp hook <event>` from the app. They are silent when a
file has no comments, and they never launch the app: a hook fires on every
`Read` in every session. If the app is not installed or not running, the hooks
do nothing.

## The Stop hook

A typed `skypies://open?path=…` link opens on the Mac and fails on every other
device, because it does not name the Mac that holds the file. When the agent
ends a turn, `skypies-mcp hook stop` reads the session transcript (a Claude Code
transcript or a Codex rollout) and blocks the stop in two cases:

| Case | What the agent must do |
|---|---|
| A skypies link in the turn's text is not exactly a `link` or `web_link` that `share_link` returned in this session | Call `share_link` and replace the link |
| The turn created a `.html`, `.htm`, `.pdf` or `.md` file (`Write` in Claude Code, an added file in a Codex patch), and the text has no minted link for it | Call `share_link` and put the `web_link` in the reply |

Housekeeping files are not deliverables: `README.md`, `CLAUDE.md`, `AGENTS.md`,
`SKILL.md`, `CHANGELOG.md` and similar, anything under `.claude/`, `.codex/`,
`.github/` or `.agents/`, and files deleted before the turn ends.

The hook blocks at most once per stop: when the agent continues because of a
block, the next stop is not checked again, so the hook cannot loop. It never
launches the app. It needs skypies 0.1.3 or later; an older app has no `stop`
event and stays silent.

## The pairing hook

`hooks/offer-skypies-pairing.sh` runs on SessionStart and stays completely silent
unless every one of these is true:

| Condition | Why |
|---|---|
| `CLAUDE_CODE_ENVIRONMENT_KIND=bridge` | `claude rc` sets this in every session it spawns for a phone, before the process starts. A plain local session leaves it unset. |
| `CLAUDE_CODE_REMOTE_SESSION_ID` unset | Drops cloud sessions, which run on Anthropic hardware and cannot reach your machine's files. |
| `~/.claude/.skypies-paired` absent | Written once a device is confirmed paired. |
| `~/.claude/.skypies-no-offer` absent | Written if you decline the offer. |

When it does fire, it injects one note asking Claude to call `list_devices` and
offer pairing only when no device is paired. The hook never reads skypies state
files, so a change to skypies's on-disk format cannot break it.

### Known gap

A session that starts local and turns on Remote Control later with
`/remote-control` is **not** detected. The bridge attaches after SessionStart has
already run, so no SessionStart hook can see it. Sessions started from the phone
against a running `claude rc` are the covered path.

### Re-arm or silence it

```
rm    ~/.claude/.skypies-paired      # offer pairing again
touch ~/.claude/.skypies-no-offer    # never offer again
```

## Server resolution

The launcher, `bin/skypies-mcp-launch.sh`, tries these in order:

| Order | Source |
|---|---|
| 1 | `$SKYPIES_MCP_BIN` — explicit override, for a dev build |
| 2 | `/Applications/skypies.app`, then `~/Applications/skypies.app` |
| 3 | Spotlight, by the bundle id `ai.skypies.skypies` (build trees under `target/` are skipped) |

If it finds no app, or only an app older than the plugin (one without
`skypies-mcp`), the server fails to start, and the MCP log says which case
applies and where to download the app.

## License

Apache-2.0
