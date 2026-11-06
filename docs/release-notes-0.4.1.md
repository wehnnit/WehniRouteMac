# WehniRoute 0.4.1

WehniRoute 0.4.1 fixes how installed harnesses are detected, opens the gateway to clients that build endpoint paths differently, and cleans up the Routing lab layout. The local-only gateway, trace inspector, and in-place updater are unchanged.

The public release is [WehniRoute 0.4.1](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.4.1). The assets are `WehniRoute-0.4.1.zip` and `WehniRoute-0.4.1.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Fixes

- **Harness detection** — installed CLIs were reported as "not in PATH" when their install location lived in `~/.zshrc` rather than the login-shell `PATH`. Detection now checks each CLI's well-known install locations first (`~/.local/bin`, `~/.opencode/bin`, `~/.hermes/node/bin`, `~/.npm-global/bin`, `~/.bun/bin`, Homebrew and `/usr/local` prefixes, plus the current process `PATH`), then falls back to a bounded login-shell and interactive-shell lookup. Detection runs for all six harnesses concurrently and a slow profile file can no longer wedge the refresh.
- **DeepSeek Harness connectivity** — the gateway returned 404 for endpoint paths without the `/v1` prefix, which is how OpenAI-compatible clients such as `dsh` may join `DEEPSEEK_BASE_URL`. The gateway now normalizes `/chat/completions`, `/messages`, and `/models` (and a doubled `/v1/v1` prefix) onto the canonical routes, so the DeepSeek Harness connects to `auto` regardless of how it composes the URL.
- **Routing lab layout** — the Scoring weights and Candidate preview cards no longer crowd each other at narrower window widths: the pair now reflows vertically with `ViewThatFits`, the gutter between cards is wider so card shadows do not visually collide, and the "filtered by policy" row can no longer clip its count.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live in 0.4.0 | `CLAUDE_WEHNI_OK`, HTTP 200 |
| Hermes Agent | Verified live in 0.4.0 | `HERMES_WEHNI_OK`, HTTP 200 |
| Pi | Verified live in 0.4.0 | `PI_WEHNI_OK`, HTTP 200 |
| DeepSeek Harness | Fixed in 0.4.1 | Gateway now accepts `/chat/completions` without the `/v1` prefix; `dsh` resolves through the aliases |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime; generated config follows its documented shape |

## Updating

Existing 0.4.0 installations update in place from this repository. The 0.4.1 release uses the same bundle identifier and data folder, so the in-place updater migrates automatically. The release assets are `WehniRoute-0.4.1.zip` and `WehniRoute-0.4.1.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
