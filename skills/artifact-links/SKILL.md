---
name: artifact-links
description: >-
  Mint a skypies link to a local file that opens on ANY of the user's paired
  devices, not just this Mac. Use proactively whenever you create a document
  or any file for the user — a report, an audit, an explainer, any
  deliverable — or when they ask to share, send or open a file on their phone,
  tablet or other Mac.
  Also use when a link failed on a device with "canonicalize failed", "No such
  file or directory", or a path that plainly exists on the Mac, or when a link
  looked clickable in the agent app but did nothing.
---

# Writing skypies:// links that work everywhere

## Every user deliverable gets a link

For EVERY document or file you create for the user — reports, HTML, markdown,
spreadsheets, presentations, PDFs, images, or any other deliverable — proactively
call the skypies MCP `share_link` tool with its absolute path after saving it.
Put the returned `https` URL in your reply as a clickable markdown link for
each file. Do not wait for the user to ask to share it. If the tool is
unavailable or fails, explain the blocker;
never invent a URL or claim a link was minted.

## The mistake this prevents

A hand-written link names a path and nothing else:

```
skypies://open?path=%2FUsers%2Fyou%2Fworkspace%2Freport.html      ← BROKEN on the phone
```

It opens on the Mac and fails on every other device, because the path names a
file on a machine **the link never identifies**. The phone looks on itself,
does not find it, and shows:

```
Deep link rejected: canonicalize failed at "/Users/you/workspace/report.html":
No such file or directory (os error 2)
```

Nothing is wrong with the file. The link was incomplete.

## The fix: mint it, never type it

Call `share_link` with the absolute path. It returns two forms of one link,
both carrying `from=<this Mac's node id>`. If it fails saying the app and the
plugin are out of step, ask the user to update skypies; never hand-write
a link to recover.

```
https://contracthero.dev/skypiesai/l#open?path=%2FUsers%2Fyou%2Fworkspace%2Freport.html&from=e35eb3e489…
skypies://open?path=%2FUsers%2Fyou%2Fworkspace%2Freport.html&from=e35eb3e489…
```

**Put the `https` form in chat**, as a markdown link: `[report.html](https://…)`.
Agent chat clients can reject custom schemes (Claude Desktop accepts only
`http(s)`), and iOS does not
linkify a custom scheme in plain text, so the raw `skypies://` form is inert in
those clients even when it looks like a link. The `https` page hands the
fragment straight back to skypies; the path travels in the fragment, so
the web host never receives it.

The raw `skypies://` form is for a QR code, the macOS share sheet and the CLI.
The app's address bar takes either form. Only `open` links have an https twin;
a `pair` or `receive` link is always the raw form.

## One link, both places

There is no separate "local version" to also produce:

| Opened on | Behaviour |
|---|---|
| The Mac that minted it | `from` matches this install, so it is dropped — an ordinary **local open** |
| A paired device | `from` names a peer — the device **pulls** the file from that Mac |
| An unpaired device | "not paired with the device this link comes from", pointing at Settings → Devices |

A minted link is a superset of a hand-written one, so there is no judgement
call. **Always mint.**

## Tell the user when it matters

**skypies must be running on the Mac when the link is opened.** The pull
is peer-to-peer with nothing uploaded and nothing queued. If the Mac is closed
the other device says "Device unreachable / Try again", which is accurate.

**The `https` form is a redirect page.** It is served at `https://contracthero.dev/skypiesai/l` (a stand-in until `skypies.ai` is live) and hands the fragment to the `skypies://` handler. The macOS
share sheet (Share ▾ → *Share link…*) and a QR code take the raw form.

## If the device is not paired yet

`share_link` reaches only devices the user has already paired. To pair one:
`pair_device` mints a `skypies://pair?ticket=…` link, the user opens it on the
device, then six words appear on both screens. **Show the words from
`pair_status` verbatim and ask the user to compare them** — that comparison is
the only thing standing between them and a machine in the middle. Finish with
`confirm_pairing { accept: true }`, and never confirm on their behalf.

## Someone who is not the user

`share_link` is for the user's own devices. For anyone else use
`beam_artifact`, which stages the bytes and mints a `skypies://receive?ticket=…`
link anyone holding it can fetch while the app runs. Different trust shape: a
beam link is a bearer capability for one file. `beam_artifact` is confined to
`SKYPIES_MCP_ROOTS`; `share_link` is not, because it reaches only the user's own
machines.

## Before you send a link

1. Did `share_link` produce it? If you typed `skypies://open?path=` yourself, stop.
2. Is it the `https` form? Use it in Codex and Claude chat; custom schemes may not open.
3. Is it for the user's own device? If not, `beam_artifact`.
4. Will the Mac be running when they open it? If not, say so.
