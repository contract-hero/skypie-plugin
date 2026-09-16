# skypie

Claude Code plugin for [Sky Pie](https://github.com/alilloig/skypie-core). It
bundles two things:

1. The **`skypie` MCP server**, which sends local files straight to your paired
   Sky Pie devices over a direct, end-to-end encrypted peer-to-peer link.
   Nothing is uploaded to a server.
2. A **SessionStart hook**, which offers device pairing the first time you open
   a Claude Code Remote Control session, so your phone can receive files without
   you having to remember to set it up.

## Install

```
claude plugin marketplace add contract-hero/plugin-marketplace
claude plugin install skypie@contract-hero
```

The server binary is downloaded on first use from this repository's releases,
checked against the SHA-256 pinned in `bin/manifest.json`, and cached under
`~/.cache/skypie-plugin/`. A download that fails the checksum is deleted and
never executed.

> If you already added `skypie` by hand with `claude mcp add`, remove that entry
> first with `claude mcp remove skypie`. Two servers with the same name is one
> too many.

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

`SKYPIE_MCP_ROOTS` is a colon-separated list of directories the server may send
files from. A path outside every root is refused. The plugin leaves it unset, so
it defaults to the directory Claude Code launched the server in. Widen it only
on purpose, in your own MCP settings.

## The pairing hook

`hooks/offer-skypie-pairing.sh` runs on SessionStart and stays completely silent
unless every one of these is true:

| Condition | Why |
|---|---|
| `CLAUDE_CODE_ENVIRONMENT_KIND=bridge` | `claude rc` sets this in every session it spawns for a phone, before the process starts. A plain local session leaves it unset. |
| `CLAUDE_CODE_REMOTE_SESSION_ID` unset | Drops cloud sessions, which run on Anthropic hardware and cannot reach your machine's files. |
| `~/.claude/.skypie-paired` absent | Written once a device is confirmed paired. |
| `~/.claude/.skypie-no-offer` absent | Written if you decline the offer. |

When it does fire, it injects one note asking Claude to call `list_devices` and
offer pairing only when no device is paired. The hook never reads SkyPie state
files, so a change to SkyPie's on-disk format cannot break it.

### Known gap

A session that starts local and turns on Remote Control later with
`/remote-control` is **not** detected. The bridge attaches after SessionStart has
already run, so no SessionStart hook can see it. Sessions started from the phone
against a running `claude rc` are the covered path.

### Re-arm or silence it

```
rm    ~/.claude/.skypie-paired      # offer pairing again
touch ~/.claude/.skypie-no-offer    # never offer again
```

## Binary resolution

The launcher tries these in order, so a maintainer never downloads and a user
never builds:

| Order | Source |
|---|---|
| 1 | `$SKYPIE_MCP_BIN` — explicit override |
| 2 | `~/.cache/skypie-plugin/` — a verified earlier download |
| 3 | `$SKYPIE_SOURCE_REPO/target/{release,debug}/skypie-mcp` — a maintainer's checkout of the private source repo |
| 4 | `skypie-mcp` on `$PATH` |
| 5 | Download from this repo's releases, verify, cache |

## Releasing (maintainers)

The server source is private, so releases are cut from a machine that has both
checkouts:

```
./scripts/publish-release.sh 0.1.0 ~/workspace/skypie-core            # build + pin, no upload
./scripts/publish-release.sh 0.1.0 ~/workspace/skypie-core --publish  # upload the release
```

Then commit the updated `bin/manifest.json`, which is what points the launcher at
the new version.

## License

MIT
