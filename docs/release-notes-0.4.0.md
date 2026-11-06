# WehniRoute 0.4.0

WehniRoute 0.4.0 is the first release from the clean `wehnnit` repository. It adds first-class terminal commands for every generated harness, fixes Hermes Agent's provider home, and keeps the local-only gateway and in-place updater intact.

## Highlights

- **Terminal commands** — install `claude-wehniroute`, `opencode-wehniroute`, `codex-wehniroute`, `hermes-wehniroute`, `pi-wehniroute`, and `dsh-wehniroute` into `~/.local/bin` from Harnesses or Settings. Each command opens the real CLI with the generated WehniRoute configuration and any arguments you append.
- **Hermes Agent fixed** — the app now writes an isolated `HERMES_HOME/config.yaml` with a `wehni` provider and launches `hermes --provider wehni -m auto`. The user's `~/.hermes` configuration is untouched.
- **Settings harness controls** — a new **Harness commands** card in Settings installs the wrappers and links to the launch pads.
- **Clean repository** — fresh history, authored and committed only by `wehnnit`, with no co-author trailers.
- **Status strip retained** — the bottom strip reports gateway address, host macOS version, Apache 2.0 license, app version/build, and copyright.
- **Auto-update retained** — the updater checks this repository's latest public release, verifies the `.sha256`, validates the bundle, and replaces the app in place.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live | `CLAUDE_WEHNI_OK`, 1,572 input / 8 output tokens, provider `ollama`, HTTP 200 |
| Hermes Agent | Verified live | `HERMES_WEHNI_OK`, 15,870 input / 7 output tokens, provider `ollama`, HTTP 200; fresh clean-home run `HERMES_FRESH_OK`, 12,317 input / 6 output tokens, provider `ollama`, HTTP 200 |
| Pi | Verified live | `PI_WEHNI_OK`, 404 input / 6 output tokens, provider `ollama`, HTTP 200 |
| DeepSeek Harness | Verified live | Headless `dsh` exit 0, 8,097 input / 5 output tokens, provider `ollama`, HTTP 200 |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime; generated config follows its documented shape |

## Install without a paid Apple Developer ID

The app is ad-hoc signed, not notarized. On macOS 26.5.2, first open shows **“WehniRoute” Not Opened**; click **Done**, then use **System Settings → Privacy & Security → Security → Open Anyway**, authenticate with an administrator's Touch ID or password, and confirm **Open**. This is a one-time Gatekeeper confirmation and requires administrator authorization; a standard user without it cannot complete this step. Auto-updates clear quarantine on the new bundle. The `.sha256` asset contains a filename-only digest, so it works with `shasum -a 256 -c WehniRoute-0.4.0.zip.sha256` from the Downloads folder.

## Updating

Existing WehniRoute 0.3.x installations point at this same public repository. The 0.4.0 release uses the same bundle identifier and data folder, so the in-place updater migrates automatically. The release assets are `WehniRoute-0.4.0.zip` and `WehniRoute-0.4.0.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
