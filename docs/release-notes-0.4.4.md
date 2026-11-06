# WehniRoute 0.4.4

WehniRoute 0.4.4 makes the gateway present itself as a single branded model to every client, and reworks the TalkNova integration into the form that actually works.

The public release is [WehniRoute 0.4.4](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.4.4). The assets are `WehniRoute-0.4.4.zip` and `WehniRoute-0.4.4.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Changes

- **WehniRoute Auto everywhere** — `/v1/models` (and the bare `/models` alias) now returns exactly one model: `auto`, named **WehniRoute Auto**. Chat responses — JSON and streaming — report `model: auto` instead of the upstream model ID, so every harness UI shows WehniRoute Auto rather than the provider's internal model name. The trace log continues to record the concrete provider and model that answered each request.

- **TalkNova as a provider, not an env redirect** — inspecting the TalkNova 0.3.77 desktop bundle showed its client hardwires `talknova.site` endpoints at compile time: the URL constants in its backend are plain constants, not environment overrides, so the 0.4.3 launch-time env injection was a no-op and TalkNova kept using its own cloud. The integration now uses the direction TalkNova documents itself: WehniRoute adds a **TalkNova provider preset** (`https://talknova.site/v1`, OpenAI-compatible). Paste your personal `tn-live-…` key from TalkNova → Settings → API access, and TalkNova's catalog joins the routing ladder for every harness. The TalkNova launch pad remains as a one-click app opener with an honest setup note; it no longer pretends to redirect chat traffic.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live in 0.4.0 | `CLAUDE_WEHNI_OK`, HTTP 200 |
| Hermes Agent | Verified live in 0.4.0 | `HERMES_WEHNI_OK`, HTTP 200 |
| Pi | Verified live in 0.4.0 | `PI_WEHNI_OK`, HTTP 200 |
| DeepSeek Harness | Verified live | Gateway aliases; model picker shows WehniRoute Auto |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime |
| TalkNova | Provider preset | `talknova.site/v1` is OpenAI-compatible per its in-app API docs; desktop client is cloud-bound |

## Updating

Existing 0.4.x installations update in place from this repository. The release assets are `WehniRoute-0.4.4.zip` and `WehniRoute-0.4.4.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
