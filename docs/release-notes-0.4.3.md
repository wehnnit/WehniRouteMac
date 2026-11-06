# WehniRoute 0.4.3

WehniRoute 0.4.3 adds the TalkNova desktop app as a harness and fixes the Routing lab's overflowing task picker. Auto-update, harnesses, the gateway, and the routing engine are otherwise unchanged.

The public release is [WehniRoute 0.4.3](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.4.3). The assets are `WehniRoute-0.4.3.zip` and `WehniRoute-0.4.3.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Additions

- **TalkNova harness** — TalkNova is a desktop coding app whose backend honors `TALKNOVA_CHAT_URL` and `TALKNOVA_MODELS_URL` environment overrides instead of its `talknova.site` defaults. The new launch pad detects `/Applications/TalkNova.app` (or `~/Applications/TalkNova.app`), launches the app binary directly with both overrides pointed at the local gateway, and installs a `talknova-wehniroute` command for Terminal launches. TalkNova keeps using its own stored key for the Bearer header, so the gateway's **Require API key** toggle should stay off while using it. TalkNova's account and local data are untouched.

## Fixes

- **Routing lab task picker** — the Candidate preview's segmented task picker was an `NSSegmentedControl`, which keeps a large minimum width and overflowed the fixed-width card at common window sizes, spilling past the card border on both sides. It is replaced with a compressible button-based segmented control that always fits, shrinking labels as needed.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live in 0.4.0 | `CLAUDE_WEHNI_OK`, HTTP 200 |
| Hermes Agent | Verified live in 0.4.0 | `HERMES_WEHNI_OK`, HTTP 200 |
| Pi | Verified live in 0.4.0 | `PI_WEHNI_OK`, HTTP 200 |
| DeepSeek Harness | Fixed in 0.4.1 | Gateway accepts `/chat/completions` without the `/v1` prefix |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime |
| TalkNova | Wired in 0.4.3 | Endpoint overrides verified against the bundled backend; desktop launch routed at the gateway |

## Updating

Existing 0.4.x installations update in place from this repository. The release assets are `WehniRoute-0.4.3.zip` and `WehniRoute-0.4.3.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
