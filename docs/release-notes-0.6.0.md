# WehniRoute 0.6.0

WehniRoute 0.6.0 makes every mainstream local AI inference engine a first-class, auto-detectable provider, and makes the router fail over at *model* granularity within a provider before moving to the next provider.

The public release is [WehniRoute 0.6.0](https://github.com/wehnnit/WehniRouteMac/releases/tag/v0.6.0). The assets are `WehniRoute-0.6.0.zip` and `WehniRoute-0.6.0.zip.sha256`; the `.sha256` sidecar is the authoritative digest.

## Local engines, everywhere

- 18 new detectable local inference engines: Jan, GPT4All, KoboldCpp, Text Generation WebUI, TabbyAPI, llama.cpp server, llamafile, LocalAI, Hugging Face TGI, MLX-LM, vLLM, llama-cpp-python, SGLang, mistral.rs, Xinference, Docker Model Runner, AMD Lemonade, and LiteLLM Proxy — each with its own preset, pricing ($0, free tier), and catalog import.
- Shared loopback ports are disambiguated by engine-specific probes instead of guessed: 8080 (`/readyz` → LocalAI, empty `/health` → TGI, `{"status":"ok"}` → llama.cpp, MLX model IDs → MLX-LM), 8000 (`/metrics` → vLLM, `{"status":"ok"}` → llama-cpp-python), 5000 (OpenAPI title → TabbyAPI, otherwise Text Generation WebUI), 1234 (LM Studio's `/api/v0/models`, otherwise mistral.rs).
- llama.cpp servers are detected on both the classic 8080 port and the new 9931 native default; adopting one rewrites the provider URL to the responding port.
- TabbyAPI asks for its API key, because its server enforces authentication by default.
- Scanning probes every catalog port concurrently with a 1.5 s per-request timeout, so a machine with no engines finishes fast instead of waiting out a serial chain.
- The Antigravity bridge ports (8080 unidentified, 8877, 11435, 8045) and TalkNova detection are unchanged.

## Smarter failover

- New **Failover scope** control on the Routing lab's fallback ladder: **Global** (score-ordered, the previous behavior) or **Provider first**, which exhausts a provider's own models by score before falling over to the next provider.
- Per-model health tracking: a model that fails repeatedly cools down on its own (`providerID/modelID` keys) while its provider's other models stay in rotation. Provider-level circuit breaking is unchanged.
- Existing configs decode `failoverScope` as `Global`, so updating never silently reorders anyone's routing.

## Under the hood

- `ProviderKind` gained `localEngines` and a single `isLocal` branch, which collapsed the per-kind switches in routing, catalog parsing, and scanning into one code path — new engines inherit local routing, $0 pricing, and key-less requests automatically.
- A pure `LocalEngineCatalog` + `LocalEndpointClassifier` live in `WehniRouteCore`, so detection logic is unit-tested offline while the app-side scanner stays a thin network shim.
- The Models tab gains token-ranked search (`cmd-F`), trace history and persistence moved into a dedicated `TraceStore`, and Discord presence reflects the active section and last route.

## Updating

Existing 0.5.x installations update in place from this repository through **Settings → Updates**. The updater reads the latest public GitHub Release, verifies the downloaded archive against the published SHA-256, and installs to `~/Applications` when running from a translocated copy. macOS may still require a first-launch confirmation because the app is ad-hoc signed, not notarized.
