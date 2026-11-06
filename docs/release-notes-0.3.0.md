# WehniRoute 0.3.0

This release adds launchable AI coding harnesses, a persistent macOS/license/version status strip, and a denser window layout that uses the full app height.

## Harnesses

The new **Harnesses** section detects installed terminal coding agents and launches them against WehniRoute's local inference:

- **Claude Code** — Anthropic Messages via `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`.
- **OpenCode** — OpenAI-compatible provider in a dedicated generated workspace.
- **Codex** — isolated `CODEX_HOME` using an OpenAI chat-completions provider. Codex is intentionally not exercised by local QA.
- **Hermes Agent** — custom OpenAI-compatible endpoint with provider `custom` and model `auto`.
- **Pi** — isolated `PI_CODING_AGENT_DIR` with a generated `wehni` provider catalog.
- **DeepSeek Harness** — `DEEPSEEK_BASE_URL`/`DEEPSEEK_API_KEY` with the DSH web profile.

Each card shows whether the CLI is detected, supports **Launch in Terminal**, copies the generated command, and opens setup guidance. Provider API keys remain in the macOS Keychain; only the local gateway key is written to the generated harness files. Generated configs live under `~/Library/Application Support/WehniRoute/harnesses/` and are mode `0600`; launchers are mode `0700`.

## UI and layout

- Added a full-width bottom status strip with the local gateway port, macOS version, Apache 2.0 license, app version/build, and copyright.
- Traces now occupies the available window height with a single internal list and inspector scroll, removing nested page scrolling.
- Tightened page, card, and header density while preserving the 1120 × 720 minimum window.
- Added a Harnesses shortcut in Settings → About.
- Updated all main-window screenshots and added the app logo asset.

## Installation

The app is **ad-hoc signed**, not notarized with a paid Apple Developer ID. On first open from a downloaded zip:

1. Open **System Settings → Privacy & Security**.
2. Click **Open Anyway** under Security.
3. Confirm **Open**.

Alternatively, right-click the app and choose **Open**. This is a one-time Gatekeeper confirmation; auto-updates clear quarantine on the new bundle.

## Auto-updates

WehniRoute 0.3.0 checks public GitHub Releases on launch and every 24 hours, verifies the SHA-256 checksum and ad-hoc signature, and replaces the app in place while preserving Application Support, Keychain entries, provider configuration, and traces.

## Verification

- `swift build` passed.
- `swift test` passed: 10 tests, 0 failures.
- `git diff --check` passed.
- OpenCode v2 provider JSON was validated against the installed CLI's project-config discovery.
- Pi `models.json` was validated with `pi --list-models`.
- Codex was not launched, by request.
