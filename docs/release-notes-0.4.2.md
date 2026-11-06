# WehniRoute 0.4.2

WehniRoute 0.4.2 makes auto-update independent of where the app is launched from. The local-only gateway, harnesses, trace inspector, and routing engine are unchanged from 0.4.1.

The public release is [WehniRoute 0.4.2](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.4.2). The assets are `WehniRoute-0.4.2.zip` and `WehniRoute-0.4.2.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Fixes

- **Auto-update from any location** — the updater previously required the running bundle's folder to be writable and failed on macOS App Translocation mounts, the read-only randomized location Gatekeeper uses when a quarantined app is launched from Downloads or similar. The updater now detects a translocated or read-only home and relocates instead of failing: the downloaded, checksum-verified build is installed into `~/Applications/WehniRoute.app` (falling back to `/Applications`), the quarantine attribute is cleared, and the app relaunches from the stable location. Subsequent updates are in-place because the relocated copy is no longer quarantined. The decision and target path are recorded in `update.log`, and Settings shows a notice while the app runs from a translocated copy.
- **Clearer failure message** — if no writable install location exists at all, the error now names every location that was tried.

## Notes for 0.4.0 installations

The 0.4.0 updater predates this fix, so a 0.4.0 copy running under App Translocation cannot self-update and shows the read-only location error once. Escape it once: quit WehniRoute, move the original `WehniRoute.app` to `~/Applications`, complete the one-time Open Anyway confirmation in System Settings → Privacy & Security, then use **Check now**. From 0.4.1 onward, and from any fresh 0.4.2 download, updates succeed from any launch location.

## Harness verification

| Harness | Result | Evidence |
| --- | --- | --- |
| Claude Code | Verified live in 0.4.0 | `CLAUDE_WEHNI_OK`, HTTP 200 |
| Hermes Agent | Verified live in 0.4.0 | `HERMES_WEHNI_OK`, HTTP 200 |
| Pi | Verified live in 0.4.0 | `PI_WEHNI_OK`, HTTP 200 |
| DeepSeek Harness | Fixed in 0.4.1 | Gateway accepts `/chat/completions` without the `/v1` prefix |
| Codex | Wired, not exercised | Isolated `CODEX_HOME` and chat-completions provider generated |
| OpenCode | Blocked upstream | OpenCode 2.0.26 ignores generated custom providers in its server runtime |

## Updating

Existing 0.4.0 and 0.4.1 installations update in place from this repository. The release assets are `WehniRoute-0.4.2.zip` and `WehniRoute-0.4.2.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
