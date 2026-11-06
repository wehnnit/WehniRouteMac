# WehniRoute 0.5.1

WehniRoute 0.5.1 removes the TalkNova launch pad. Everything else — the gateway, the WehniRoute Auto presentation, the harness detection and relocation fixes, and auto-update — is unchanged from 0.5.0.

The public release is [WehniRoute 0.5.1](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.5.1). The assets are `WehniRoute-0.5.1.zip` and `WehniRoute-0.5.1.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Why the TalkNova launch pad is removed

The CLI harnesses work because they are designed to be repointed: Claude Code, Codex, OpenCode, Hermes, Pi, and the DeepSeek Harness read provider configuration from environment variables and generated config files, so WehniRoute can point them at the local gateway as their supported behavior. TalkNova's desktop client is a closed app with its cloud endpoints compiled into its binary — reverse engineering its backend found no configuration seam (the endpoint constants are compile-time values, not environment overrides), and the 0.5.0 interception launch pad did not capture its traffic, so chat kept going to TalkNova's cloud and consuming usage.

Rather than ship a card that silently does not work, it is removed. Launching TalkNova from WehniRoute is no longer offered.

## The supported TalkNova integration

The **TalkNova provider preset** remains. TalkNova documents an OpenAI-compatible API at `https://talknova.site/v1` with the personal `tn-live-…` key shown in TalkNova's Settings → API access. Connect it from **Connect provider → TalkNova** and its catalog joins the routing ladder, so any harness can route to TalkNova models through WehniRoute — with every harness still seeing the single **WehniRoute Auto** model.

## Updating

Existing 0.4.x and 0.5.0 installations update in place from this repository. The release assets are `WehniRoute-0.5.1.zip` and `WehniRoute-0.5.1.zip.sha256`.

Apache License 2.0. © 2026 wehnnit.
