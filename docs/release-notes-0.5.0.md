# WehniRoute 0.5.0

WehniRoute 0.5.0 truly wires the TalkNova desktop app into WehniRoute by intercepting it on the wire, after reverse engineering exactly how the client communicates.

The public release is [WehniRoute 0.5.0](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.5.0). The assets are `WehniRoute-0.5.0.zip` and `WehniRoute-0.5.0.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## How TalkNova actually works

Inspecting the TalkNova 0.3.77 bundle (extracting and disassembling its compiled Python backend) established the facts that make the integration possible:

- Every backend HTTPS call goes through `urllib.request.urlopen` with the **default opener**, which honors the standard `HTTPS_PROXY` environment variable.
- The TLS context is built by `_ssl_context()`, which honors **`SSL_CERT_FILE`** as a CA bundle override while keeping hostname verification on.
- The cloud endpoints — including `https://talknova.site/v1/chat/completions` and `/v1/models` — are compile-time constants; no configuration or environment variable can repoint them.
- Chat streams with `Accept: text/event-stream`, sends `Authorization: Bearer <personal key>`, and treats missing `capabilities` in a model entry as `tool_calling: true`.
- The frontend is served by a local pywebview HTTP server and talks to the backend through the pywebview bridge, so the chat data path lives entirely inside the compiled backend.

## Changes

- **TalkNova interception proxy** — WehniRoute now runs a loopback HTTP CONNECT proxy. Launching TalkNova from Harnesses sets `HTTPS_PROXY` and `SSL_CERT_FILE` in its environment and quits an already-running TalkNova first, so the interception takes effect. The proxy MITMs **only** `talknova.site`: `/v1/chat/completions` and `/v1/models` are relayed to the WehniRoute gateway with the local gateway key, so TalkNova's model picker shows **WehniRoute Auto** and chat consumes **no TalkNova usage**. Every other `talknova.site` path (account, login exchange, usage, personalization) is relayed to the real service over TLS with system trust, and all other hosts tunnel blind without inspection.
- **Local CA** — WehniRoute generates a CA and a `talknova.site` leaf certificate with the system `openssl`, stores them mode 0600 under Application Support, and hands TalkNova a trust bundle that contains the interception CA plus TalkNova's own bundled certifi roots, so non-intercepted HTTPS still verifies.
- **Honest launch card** — the TalkNova setup note now documents the interception, the one-time quit of a running instance, and the optional TalkNova provider preset (personal `tn-live-` key) for making TalkNova's models available to every other harness.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live in 0.4.0 | `CLAUDE_WEHNI_OK`, HTTP 200 |
| Hermes Agent | Verified live in 0.4.0 | `HERMES_WEHNI_OK`, HTTP 200 |
| Pi | Verified live in 0.4.0 | `PI_WEHNI_OK`, HTTP 200 |
| DeepSeek Harness | Verified live | Gateway aliases; model picker shows WehniRoute Auto |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime |
| TalkNova | Wired by interception | urllib proxy + SSL_CERT_FILE behavior verified in the compiled backend; chat and models served by the gateway |

## Updating

Existing 0.4.x installations update in place from this repository. The release assets are `WehniRoute-0.5.0.zip` and `WehniRoute-0.5.0.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
