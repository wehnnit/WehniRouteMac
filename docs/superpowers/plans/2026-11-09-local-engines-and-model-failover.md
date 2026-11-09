# Local Engine Support + Model-Aware Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

> **Revision 2 (2026-11-10).** Rev 1 was re-verified against the current source tree and up-to-date vendor docs. Fixes in this revision: llama.cpp's new 9931 default port, TabbyAPI's default-on authentication, the Task 1 `localEngines` count bug, the stale Task 3 `parseCatalog` change (the `default:` branch already handles local tiers — the real gap is `context_length` parsing), multi-port `LocalEngineSpec`, concurrent scanner probing, preserving the extra Antigravity bridge ports, the missing model-level cooldown rejection in Task 7, and the Task 9 UI instructions rewritten for the actual `fallbackCard` layout (there is no tierMode picker to copy).

**Goal:** Make every mainstream local AI inference engine a first-class, auto-detectable WehniRoute provider, and make the router fail over at *model* granularity within a provider before moving to the next provider.

**Architecture:** Part A adds the new engines as `ProviderKind` cases in `WehniRouteCore` and collapses the scattered `case .ollama, .lmstudio` switches into `kind.isLocal` early branches so all local engines inherit local routing/pricing/request behavior with zero per-kind code. Part B adds a pure, testable `LocalEndpointClassifier` in Core that disambiguates engines sharing loopback ports (8080/8000/5000/1234), then rewrites `LocalSourceScanner` to probe the full engine catalog concurrently and dedupe by port. Part C introduces a `failoverScope` routing option (`global` = today's globally sorted model list; `withinProvider` = exhaust a provider's models by score before moving to the next provider) plus per-model health snapshots so a single bad model cools down instead of its whole provider.

**Tech Stack:** Swift 6 / SPM (`swift test` for Core, `swift build` for the app target), SwiftUI (app target), no new dependencies, URLSession loopback probes only.

## Global Constraints

- No third-party dependencies. Package deps stay exactly as they are today.
- All local-engine probing is loopback-only (`127.0.0.1`), 1.5 s timeout per request, same as the existing probes in `LocalSources.swift`.
- Every `ProviderKind` switch statement in Core must remain exhaustive (Swift enforces this — the compiler is the checklist).
- Config decode defaults must never change for existing configs: `failoverScope` decodes to `.global` when absent, so an update must not silently reorder anyone's routing.
- New `ProviderKind` rawValues are lowercase, no hyphens (matches existing style: `talknova`, `lmstudio`), and are stable API keys — never rename after shipping.
- Model-level health keys use the format `"{providerID}/{modelID}"` (mirrors `Candidate.id` and `Rejection.id` which already use this shape).
- Pricing for every local engine is `$0` (free tier), `isLocal == true`. Every new engine is key-less (`requiresKey == false`) **except TabbyAPI**, whose server enforces auth by default (`disable_auth: false` in its config) — it is the one new kind with `requiresKey == true`.
- Tests live in `Tests/WehniRouteCoreTests/`. Core logic must be pure and testable — no network in unit tests; the scanner stays thin over the pure classifier.
- Existing tests in `RouterTests.swift` and `ModelSearchTests.swift` must keep passing at every task boundary.
- `Router.rank`'s existing call sites (Store.swift lines ~768, ~777, and ~1031) must keep compiling: new parameters get defaults, never new required params.

### Engine catalog being added (ports re-verified against vendor docs, 2026-11-10)

| Kind (rawValue) | Display name | Default loopback base | Notes |
|---|---|---|---|
| `jan` | Jan | `http://127.0.0.1:1337/v1` | Desktop app, llama.cpp engine; auth optional (off by default) |
| `gpt4all` | GPT4All | `http://127.0.0.1:4891/v1` | API is opt-in ("Enable Local API Server" in settings); project unmaintained since 2025 but port is stable |
| `koboldcpp` | KoboldCpp | `http://127.0.0.1:5001/v1` | Single binary, GGUF, OpenAI `/v1/` family confirmed |
| `textgenwebui` | Text Generation WebUI | `http://127.0.0.1:5000/v1` | oobabooga; API opt-in (`--api`), default API port 5000 |
| `tabbyapi` | TabbyAPI | `http://127.0.0.1:5000/v1` | ExLlama serving, shares 5000. **Auth required by default** → `requiresKey == true`; `disable_auth: true` users leave the key field empty |
| `llamacpp` | llama.cpp server | `http://127.0.0.1:8080/v1` | `llama-server`. **Default port moved 8080 → 9931** (PR #26508, Aug 2026; Docker image still 8080). Keep 8080 as `defaultBaseURL` (works for Docker + older native builds) and probe **both 8080 and 9931** during scanning |
| `llamafile` | llamafile | `http://127.0.0.1:8080/v1` | Same llama.cpp-derived API; functionally indistinguishable from llama.cpp server — classifies as `.llamacpp` is acceptable |
| `localai` | LocalAI | `http://127.0.0.1:8080/v1` | `/readyz` distinguishes it |
| `tgi` | Hugging Face TGI | `http://127.0.0.1:8080/v1` | `/health` returns an empty 200 body. TGI is in maintenance mode upstream; port/API unchanged |
| `mlxlm` | MLX-LM server | `http://127.0.0.1:8080/v1` | `mlx_lm.server` defaults to `--port 8080` (verified in mlx-lm `server.py`); model IDs containing "mlx" are the detection signal |
| `vllm` | vLLM | `http://127.0.0.1:8000/v1` | `/metrics` text contains `vllm:` metric names |
| `llamacpppython` | llama-cpp-python | `http://127.0.0.1:8000/v1` | Shares 8000; `/health` returns `{"status":"ok"}`; optional `api_key` supported but off by default |
| `sglang` | SGLang | `http://127.0.0.1:30000/v1` | Unique port |
| `mistralrs` | mistral.rs | `http://127.0.0.1:1234/v1` | Shares 1234 with LM Studio; binds 0.0.0.0 by default (loopback probe still reaches it) |
| `xinference` | Xinference | `http://127.0.0.1:9997/v1` | Unique port |
| `dockermodelrunner` | Docker Model Runner | `http://127.0.0.1:12434/engines/v1` | Docker Desktop requires enabling TCP host access (Docker Engine has it on by default) |
| `lemonade` | AMD Lemonade | `http://127.0.0.1:13305/api/v1` | Default port changed 8000 → 13305 in Lemonade v10.1.0 (Apr 2026). Probe 13305; legacy (<10.1) installs on 8000 fall through the 8000 shared-port classification and may surface as unidentified |
| `litellm` | LiteLLM Proxy | `http://127.0.0.1:4000/v1` | Proxy; user's config decides models. 4000 is the standard/Docker default; bare `litellm` CLI installs may use 8000 — documented limitation, no extra probe (8000 is already a shared-port group) |

Deliberately excluded: **NVIDIA NIM local** (reuse the existing `.nvidia` kind with a custom baseURL — same OpenAI-compatible API), **Open WebUI** (a front-end, not an inference engine — it sits *on top of* the engines above).

---

## File Structure

Files created or modified, and their single responsibility:

- `Sources/WehniRouteCore/Models.swift` — modify: new `ProviderKind` cases + metadata; `FailoverScope` enum; `failoverScope` on `RoutingConfig`; `addable` list.
- `Sources/WehniRouteCore/Router.swift` — modify: `taskFit` refactor to `isLocal` early branches; `orderedForFailover`; `rank` consumes `modelHealth` (including the model-level cooldown rejection) + applies failover ordering.
- `Sources/WehniRouteCore/LocalEngines.swift` — **create**: `LocalEngineSpec`/`LocalEngineCatalog` (multi-port engine metadata table) + `LocalProbeResult` + `LocalEndpointClassifier` (pure port disambiguation).
- `Sources/WehniRouteCore/ProviderClient.swift` — modify: add `parseCatalogForTesting` hook and `context_length` parsing for local engines in `parseCatalog`'s `default:` branch. **No change to discovery routing**: Ollama keeps its native `/api/tags` gate (`provider.kind == .ollama`), every other local engine already falls through to the generic OpenAI `/v1/models` path, and `parseCatalog`'s `default:` branch already assigns `.free` when `provider.kind.isLocal`.
- `Sources/WehniRouteApp/LocalSources.swift` — modify: catalog-driven scanner with concurrent probing; dedupe shared ports; new `LocalSourceKind` cases; keep the extra Antigravity bridge ports (8877, 11435, 8045).
- `Sources/WehniRouteApp/Store.swift` — modify: `sourceProviderID`/`connectSource` for new kinds; `@Published var modelHealth`; `RoutingSnapshot.modelHealth`; `execute` updates model health and passes it to `rank`.
- `Sources/WehniRouteApp/RoutingView.swift` — modify: failover-scope control in `fallbackCard`.
- `Sources/WehniRouteApp/ProvidersView.swift` — modify: scan-row copy.
- `Tests/WehniRouteCoreTests/LocalEngineTests.swift` — **create**: classifier + catalog tests.
- `Tests/WehniRouteCoreTests/RouterTests.swift` — modify: failover-scope and model-health tests.

---

### Task 1: New `ProviderKind` cases with full metadata

**Files:**
- Modify: `Sources/WehniRouteCore/Models.swift`
- Test: `Tests/WehniRouteCoreTests/LocalEngineTests.swift` (create in this task; it keeps growing)

**Interfaces:**
- Produces: `ProviderKind` cases `jan, gpt4all, koboldcpp, textgenwebui, tabbyapi, llamacpp, llamafile, localai, tgi, mlxlm, vllm, llamacpppython, sglang, mistralrs, xinference, dockermodelrunner, lemonade, litellm`; static `ProviderKind.localEngines: [ProviderKind]` (20 entries: ollama, lmstudio + the 18 new engines — **not** simulation); `isLocal` returns true for all of `localEngines` plus `.simulation`. Every later task relies on `isLocal` and the metadata switches.

- [x] **Step 1: Write the failing test**

Create `Tests/WehniRouteCoreTests/LocalEngineTests.swift`:

```swift
import XCTest
@testable import WehniRouteCore

final class LocalEngineTests: XCTestCase {
    func testAllNewLocalEnginesAreFlaggedLocal() {
        let expected: [ProviderKind] = [
            .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
            .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
            .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
        ]
        for kind in expected {
            XCTAssertTrue(kind.isLocal, "\(kind.rawValue) must be local")
            XCTAssertEqual(kind.defaultInputPrice, 0, "\(kind.rawValue) is free")
            XCTAssertEqual(kind.defaultOutputPrice, 0, "\(kind.rawValue) is free")
            XCTAssertTrue(kind.defaultModelIsFree, "\(kind.rawValue) default model is free")
            if kind == .tabbyapi {
                XCTAssertTrue(kind.requiresKey, "tabbyapi enforces auth by default")
            } else {
                XCTAssertFalse(kind.requiresKey, "\(kind.rawValue) must not require a key")
            }
        }
        // 18 new engines + ollama + lmstudio. Simulation is deliberately NOT
        // in localEngines: its request path is synthetic, not a loopback API.
        XCTAssertEqual(ProviderKind.localEngines.count, expected.count + 2)
        XCTAssertTrue(ProviderKind.simulation.isLocal, "simulation stays local")
        XCTAssertFalse(ProviderKind.localEngines.contains(.simulation))
    }

    func testDefaultBaseURLsUseLoopback() {
        XCTAssertEqual(ProviderKind.jan.defaultBaseURL, "http://127.0.0.1:1337/v1")
        XCTAssertEqual(ProviderKind.gpt4all.defaultBaseURL, "http://127.0.0.1:4891/v1")
        XCTAssertEqual(ProviderKind.koboldcpp.defaultBaseURL, "http://127.0.0.1:5001/v1")
        XCTAssertEqual(ProviderKind.textgenwebui.defaultBaseURL, "http://127.0.0.1:5000/v1")
        XCTAssertEqual(ProviderKind.tabbyapi.defaultBaseURL, "http://127.0.0.1:5000/v1")
        XCTAssertEqual(ProviderKind.llamacpp.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.llamafile.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.localai.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.tgi.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.mlxlm.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.vllm.defaultBaseURL, "http://127.0.0.1:8000/v1")
        XCTAssertEqual(ProviderKind.llamacpppython.defaultBaseURL, "http://127.0.0.1:8000/v1")
        XCTAssertEqual(ProviderKind.sglang.defaultBaseURL, "http://127.0.0.1:30000/v1")
        XCTAssertEqual(ProviderKind.mistralrs.defaultBaseURL, "http://127.0.0.1:1234/v1")
        XCTAssertEqual(ProviderKind.xinference.defaultBaseURL, "http://127.0.0.1:9997/v1")
        XCTAssertEqual(ProviderKind.dockermodelrunner.defaultBaseURL, "http://127.0.0.1:12434/engines/v1")
        XCTAssertEqual(ProviderKind.lemonade.defaultBaseURL, "http://127.0.0.1:13305/api/v1")
        XCTAssertEqual(ProviderKind.litellm.defaultBaseURL, "http://127.0.0.1:4000/v1")
    }

    func testDefaultModelIsEmptyLikeLMStudio() {
        for kind in ProviderKind.localEngines where kind != .ollama {
            XCTAssertEqual(kind.defaultModel, "", "\(kind.rawValue) discovers its catalog; no hardcoded model")
        }
    }

    func testRawValuesAreStableAndLowercase() {
        for kind in ProviderKind.localEngines {
            XCTAssertEqual(kind.rawValue, kind.rawValue.lowercased())
            XCTAssertFalse(kind.rawValue.contains(" "), "\(kind.rawValue) must not contain spaces")
            XCTAssertFalse(kind.rawValue.contains("-"), "\(kind.rawValue) must not contain hyphens")
        }
    }
}
```

> Why the TabbyAPI exception: its wiki states "Every call to a TabbyAPI endpoint requires some form of authentication" with `disable_auth` defaulting to `false`. Marking it key-less would produce a provider that silently 401s on every request. `requiresKey == true` reuses the existing AddSheets key-field path (line ~143: `if !preset.requiresKey { apiKey = "" }`) and the gateway's honest "No API key → skipped" behavior.

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter LocalEngineTests`
Expected: FAIL — type `ProviderKind` has no member `jan` (compile error counts as the failing state).

- [x] **Step 3: Add the cases and metadata in Models.swift**

In `enum ProviderKind`, add cases after `case lmstudio`:

```swift
    case lmstudio
    case jan
    case gpt4all
    case koboldcpp
    case textgenwebui
    case tabbyapi
    case llamacpp
    case llamafile
    case localai
    case tgi
    case mlxlm
    case vllm
    case llamacpppython
    case sglang
    case mistralrs
    case xinference
    case dockermodelrunner
    case lemonade
    case litellm
    case simulation
```

(The `simulation` case already exists below — keep its position; only insert the new cases between `lmstudio` and `simulation`.)

Add a static list on `ProviderKind` (near `addable`):

```swift
    /// Every kind that runs inference on this machine via a loopback HTTP
    /// API. Router and client behavior keys off `isLocal`; this list is for
    /// UI grouping, scanning, and tests. Simulation is excluded on purpose.
    public static let localEngines: [ProviderKind] = [
        .ollama, .lmstudio, .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi,
        .llamacpp, .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
        .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
    ]
```

Update each metadata switch by inserting these cases (all values per the catalog table above):

`displayName`:
```swift
        case .jan: return "Jan"
        case .gpt4all: return "GPT4All"
        case .koboldcpp: return "KoboldCpp"
        case .textgenwebui: return "Text Generation WebUI"
        case .tabbyapi: return "TabbyAPI"
        case .llamacpp: return "llama.cpp server"
        case .llamafile: return "llamafile"
        case .localai: return "LocalAI"
        case .tgi: return "Hugging Face TGI"
        case .mlxlm: return "MLX-LM server"
        case .vllm: return "vLLM"
        case .llamacpppython: return "llama-cpp-python"
        case .sglang: return "SGLang"
        case .mistralrs: return "mistral.rs"
        case .xinference: return "Xinference"
        case .dockermodelrunner: return "Docker Model Runner"
        case .lemonade: return "AMD Lemonade"
        case .litellm: return "LiteLLM Proxy"
```

`tagline`:
```swift
        case .jan: return "Offline desktop app, llama.cpp engine"
        case .gpt4all: return "Local desktop app by Nomic"
        case .koboldcpp: return "One-binary GGUF runner"
        case .textgenwebui: return "oobabooga multi-backend UI"
        case .tabbyapi: return "ExLlama-powered serving"
        case .llamacpp: return "llama-server, OpenAI-compatible"
        case .llamafile: return "Single-file model executables"
        case .localai: return "Drop-in OpenAI replacement"
        case .tgi: return "Hugging Face text-generation serving"
        case .mlxlm: return "Apple-Silicon-native server"
        case .vllm: return "High-throughput GPU serving"
        case .llamacpppython: return "Python llama.cpp server"
        case .sglang: return "Low-latency structured serving"
        case .mistralrs: return "Rust inference server"
        case .xinference: return "Multi-model serving platform"
        case .dockermodelrunner: return "Docker Desktop's built-in runner"
        case .lemonade: return "AMD Ryzen AI runtime"
        case .litellm: return "Proxy that aggregates backends"
```

`defaultBaseURL`:
```swift
        case .jan: return "http://127.0.0.1:1337/v1"
        case .gpt4all: return "http://127.0.0.1:4891/v1"
        case .koboldcpp: return "http://127.0.0.1:5001/v1"
        case .textgenwebui: return "http://127.0.0.1:5000/v1"
        case .tabbyapi: return "http://127.0.0.1:5000/v1"
        case .llamacpp, .llamafile, .localai, .tgi, .mlxlm: return "http://127.0.0.1:8080/v1"
        case .vllm, .llamacpppython: return "http://127.0.0.1:8000/v1"
        case .sglang: return "http://127.0.0.1:30000/v1"
        case .mistralrs: return "http://127.0.0.1:1234/v1"
        case .xinference: return "http://127.0.0.1:9997/v1"
        case .dockermodelrunner: return "http://127.0.0.1:12434/engines/v1"
        case .lemonade: return "http://127.0.0.1:13305/api/v1"
        case .litellm: return "http://127.0.0.1:4000/v1"
```

`defaultModel`:
```swift
        case .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
             .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
             .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade,
             .litellm: return ""
```

`defaultContextWindow`:
```swift
        case .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
             .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
             .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade,
             .litellm: return 131_072
```

`defaultInputPrice`, `defaultOutputPrice`: add the 18 kinds to the existing `case .groq, .google, .ollama, .lmstudio, .simulation: return 0` lines (both functions).

`defaultModelIsFree`: add them to the free case:
```swift
        case .groq, .google, .ollama, .lmstudio, .simulation, .jan, .gpt4all,
             .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp, .llamafile,
             .localai, .tgi, .mlxlm, .vllm, .llamacpppython, .sglang,
             .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm: return true
```

`requiresKey` — every new engine is key-less **except tabbyapi**:
```swift
    public var requiresKey: Bool {
        switch self {
        case .ollama, .lmstudio, .simulation, .jan, .gpt4all, .koboldcpp,
             .textgenwebui, .llamacpp, .llamafile, .localai, .tgi,
             .mlxlm, .vllm, .llamacpppython, .sglang, .mistralrs, .xinference,
             .dockermodelrunner, .lemonade, .litellm: return false
        case .tabbyapi: return true
        default: return true
        }
    }
```

`isLocal` — replace the whole computed property with:
```swift
    public var isLocal: Bool {
        ProviderKind.localEngines.contains(self) || self == .simulation
    }
```

`symbol`:
```swift
        case .jan: return "tray.2.fill"
        case .gpt4all: return "dot.circle.viewfinder"
        case .koboldcpp: return "pawprint.fill"
        case .textgenwebui: return "terminal.fill"
        case .tabbyapi: return "cat.fill"
        case .llamacpp: return "curlybraces"
        case .llamafile: return "doc.fill"
        case .localai: return "shippingbox.fill"
        case .tgi: return "h.square.fill"
        case .mlxlm: return "apple.logo"
        case .vllm: return "gauge.open.with.lines.needle.50percent"
        case .llamacpppython: return "chevron.left.slash.chevron.right"
        case .sglang: return "point.3.connected.trianglepath.fill"
        case .mistralrs: return "wind"
        case .xinference: return "square.3.layers.3d.down.right.fill"
        case .dockermodelrunner: return "cube.transparent.fill"
        case .lemonade: return "sun.and.horizon.fill"
        case .litellm: return "arrow.triangle.swap"
```

`accentHex`:
```swift
        case .jan: return 0x0EA5E9
        case .gpt4all: return 0x10B981
        case .koboldcpp: return 0xF59E0B
        case .textgenwebui: return 0x84CC16
        case .tabbyapi: return 0xFB7185
        case .llamacpp: return 0xA3A3A3
        case .llamafile: return 0xFBBF24
        case .localai: return 0x6366F1
        case .tgi: return 0xFACC15
        case .mlxlm: return 0xF43F5E
        case .vllm: return 0x8B5CF6
        case .llamacpppython: return 0x22D3EE
        case .sglang: return 0x34D399
        case .mistralrs: return 0xFF7000
        case .xinference: return 0x38BDF8
        case .dockermodelrunner: return 0x2496ED
        case .lemonade: return 0xEF4444
        case .litellm: return 0x14B8A6
```

`addable` — keep the grid curated; insert the local engines after `.lmstudio` (keep `.talkNova`, `.simulation`, `.custom` at the end, `.custom` last):
```swift
    public static var addable: [ProviderKind] {
        [.anthropic, .openai, .google, .groq, .mistral, .xai, .deepseek, .openrouter,
         .together, .cerebras, .fireworks, .moonshot, .nvidia,
         .ollama, .lmstudio, .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi,
         .llamacpp, .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
         .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
         .talkNova, .simulation, .custom]
    }
```

- [x] **Step 4: Run test to verify it passes**

Run: `swift test --filter LocalEngineTests`
Expected: PASS (4 tests). Then run `swift test` — `RouterTests` and `ModelSearchTests` must still pass (they only reference existing kinds).

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/Models.swift Tests/WehniRouteCoreTests/LocalEngineTests.swift
git commit -m "feat(core): add 18 local engine provider kinds with metadata"
```

---

### Task 2: Router task-fit via `isLocal` early branch

**Files:**
- Modify: `Sources/WehniRouteCore/Router.swift` (`taskFit`, lines ~247–366)
- Test: `Tests/WehniRouteCoreTests/RouterTests.swift`

**Interfaces:**
- Consumes: `ProviderKind.isLocal` (Task 1).
- Produces: `Router.taskFit(kind:task:strategy:)` unchanged signature — new engines score identically to Ollama/LM Studio. Strategy branches: local/cheap give local kinds `1.0`; reliable gives `0.6`.

- [x] **Step 1: Write the failing test**

Append to `Tests/WehniRouteCoreTests/RouterTests.swift`:

```swift
func testNewLocalEnginesScoreLikeOllama() {
    let engines: [ProviderKind] = [.jan, .koboldcpp, .vllm, .mlxlm, .litellm, .lemonade]
    for kind in engines {
        XCTAssertEqual(
            Router.taskFit(kind: kind, task: .coding, strategy: .auto),
            Router.taskFit(kind: .ollama, task: .coding, strategy: .auto),
            "\(kind.rawValue) must fit coding like ollama"
        )
        XCTAssertEqual(
            Router.taskFit(kind: kind, task: .reasoning, strategy: .local),
            1.0, "\(kind.rawValue) gets full fit under local strategy"
        )
        XCTAssertEqual(
            Router.taskFit(kind: kind, task: .writing, strategy: .cheap),
            1.0, "\(kind.rawValue) gets full fit under cheap strategy"
        )
        XCTAssertEqual(
            Router.taskFit(kind: kind, task: .fast, strategy: .reliable),
            0.6, "\(kind.rawValue) gets 0.6 under reliable strategy"
        )
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter testNewLocalEnginesScoreLikeOllama`
Expected: FAIL — compile error in the switch statements (non-exhaustive once Task 1 landed) or wrong values.

- [x] **Step 3: Refactor taskFit**

Replace the whole `taskFit` function with an early-branch structure:

```swift
    static func taskFit(kind: ProviderKind, task: TaskType, strategy: Strategy) -> Double {
        if kind == .simulation { return simulationFit(task: task, strategy: strategy) }
        if kind.isLocal { return localFit(task: task, strategy: strategy) }

        if strategy == .local { return 0.25 }
        if strategy == .cheap { return 0.55 }
        if strategy == .reliable {
            switch kind {
            case .anthropic, .openai, .google: return 0.9
            case .groq, .openrouter, .mistral, .xai, .deepseek: return 0.8
            case .together, .cerebras, .fireworks, .moonshot, .nvidia: return 0.75
            case .talkNova: return 0.75
            case .custom: return 0.7
            default: break
            }
        }

        switch task {
        case .coding:
            switch kind {
            case .anthropic: return 1.0
            case .openai: return 0.97
            case .google: return 0.90
            case .openrouter: return 0.86
            case .mistral: return 0.86
            case .xai: return 0.88
            case .deepseek: return 0.85
            case .groq: return 0.70
            case .together: return 0.78
            case .cerebras: return 0.76
            case .fireworks: return 0.74
            case .moonshot: return 0.73
            case .nvidia: return 0.73
            case .custom: return 0.72
            case .talkNova: return 0.76
            default: return 0.7
            }
        // …remaining task cases (.reasoning, .writing, .fast, .vision) follow
        // the same shape as the original file, with every cloud kind's value
        // preserved exactly and the `case .simulation` and
        // `case .ollama, .lmstudio` entries deleted from every list (the
        // early branches now handle them). The final case stays:
        case .unknown: return 0.7
        }
    }

    /// Local engines share one fit profile: capable, private, sometimes slow.
    /// Values are exactly the ones ollama/lmstudio had per task.
    private static func localFit(task: TaskType, strategy: Strategy) -> Double {
        switch strategy {
        case .local, .cheap: return 1.0
        case .reliable: return 0.6
        default: break
        }
        switch task {
        case .coding: return 0.60
        case .reasoning: return 0.58
        case .writing: return 0.62
        case .fast: return 0.58
        case .vision: return 0.50
        case .unknown: return 0.60
        }
    }

    private static func simulationFit(task: TaskType, strategy: Strategy) -> Double {
        switch strategy {
        case .local, .cheap: return 1.0
        case .reliable: return 0.6
        default: break
        }
        switch task {
        case .coding: return 0.75
        case .reasoning: return 0.70
        case .writing: return 0.72
        case .fast: return 0.98
        case .vision: return 0.40
        case .unknown: return 0.70
        }
    }
```

When filling in "…remaining task cases…", copy each cloud-kind line verbatim from the original file and delete the `case .simulation` / `case .ollama, .lmstudio` entries from every list — the early branches now handle them. Every cloud number must be character-identical to the original (`anthropic 1.0 / openai 0.96 / …` for reasoning, `openai 1.0 / anthropic 0.96 / …` for writing, `groq 1.0 / simulation removed / google 0.90 / …` for fast, `google 1.0 / …` for vision). The `default: return 0.7` in each cloud switch is only reached by nothing today (the enum is fully covered above it), but keeps the switch compiler-clean without listing local kinds.

- [x] **Step 4: Run tests to verify they pass and old behavior is preserved**

Run: `swift test --filter RouterTests`
Expected: PASS, including every pre-existing RouterTests case — if any pre-existing test breaks, the cloud values were transcribed wrong; fix the transcription, never the test.

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/Router.swift Tests/WehniRouteCoreTests/RouterTests.swift
git commit -m "refactor(core): route local engines through isLocal branch in taskFit"
```

---

### Task 3: Catalog parsing for all local engines (test hook + context parsing)

**Files:**
- Modify: `Sources/WehniRouteCore/ProviderClient.swift` (`parseCatalog`, lines ~190)
- Test: `Tests/WehniRouteCoreTests/LocalEngineTests.swift`

**Interfaces:**
- Consumes: `ProviderKind.isLocal` (Task 1).
- Produces: `ProviderClient.parseCatalogForTesting(_ body: JSONValue, provider: ProviderConfig) -> [DiscoveredModel]` (test-only surface). Local engines' discovered models are `.free` with the local note, and honor `context_length`/`context_window` fields when the engine's `/v1/models` payload carries them.

> **Revision note:** the current `parseCatalog` already has `case .ollama, .lmstudio` for the free note **and** a `default: model.tier = provider.kind.isLocal ? .free : .paid` branch — discovery routing also needs no change (Ollama's native gate is `provider.kind == .ollama`; every other local engine already falls through to the generic OpenAI path, and `trimmedBase` preserves the baseURL's path suffix, which is why Lemonade's `/api/v1` and Docker Model Runner's `/engines/v1` work unmodified). The only real gaps are the context-field parsing and the test hook.

- [x] **Step 1: Write the failing test**

Append to `Tests/WehniRouteCoreTests/LocalEngineTests.swift`:

```swift
func testParseCatalogTreatsEveryLocalEngineAsFreeLocal() {
    let body: JSONValue = .object([
        "data": .array([
            .object(["id": .string("qwen2.5-7b-instruct"), "context_length": .num(32768)]),
            .object(["id": .string("llama-3.2-1b")]),
        ])
    ])
    for kind in [ProviderKind.jan, .koboldcpp, .vllm, .mlxlm, .tgi, .localai, .sglang, .litellm, .dockermodelrunner, .lemonade] {
        let provider = ProviderConfig(kind: kind)
        let parsed = ProviderClient.parseCatalogForTesting(body, provider: provider)
        XCTAssertEqual(parsed.count, 2, "\(kind.rawValue) parses both entries")
        XCTAssertTrue(parsed.allSatisfy { $0.tier == .free }, "\(kind.rawValue) models are free")
        XCTAssertEqual(parsed.first?.contextWindow, 32768, "\(kind.rawValue) honors context_length")
        XCTAssertEqual(parsed.last?.contextWindow, kind.defaultContextWindow, "\(kind.rawValue) falls back to default context")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter testParseCatalogTreatsEveryLocalEngineAsFreeLocal`
Expected: FAIL — `parseCatalogForTesting` does not exist (and `context_length` is not parsed for local kinds).

- [x] **Step 3: Implement**

In `parseCatalog`, extend the `default:` branch so local engines honor context fields and carry the local note:

```swift
            default:
                if provider.kind.isLocal {
                    model.tier = .free
                    model.note = "Local model · no egress, no cost"
                    if let ctx = entry["context_length"]?.intValue ?? entry["context_window"]?.intValue {
                        model.contextWindow = ctx
                    }
                } else {
                    model.tier = .paid
                }
```

Keep the explicit `case .ollama, .lmstudio` as it is (it documents the original pair; the `default` branch covers all new engines without enumeration).

Below the `parseCatalog` function, add the test hook:

```swift
    /// Test-only surface for the catalog parser. Never call from app code.
    static func parseCatalogForTesting(_ body: JSONValue, provider: ProviderConfig) -> [DiscoveredModel] {
        parseCatalog(body, provider: provider)
    }
```

Also run `rg -n "\.ollama|\.lmstudio" Sources/WehniRouteCore/ProviderClient.swift` and confirm the only remaining enumerations are the `discoverOllama` gate and the `parseCatalog` case — replace any other "local engine" enumeration with `provider.kind.isLocal` guards.

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LocalEngineTests`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/ProviderClient.swift Tests/WehniRouteCoreTests/LocalEngineTests.swift
git commit -m "feat(core): generic catalog parsing for all local engines"
```

---

### Task 4: Local engine catalog (multi-port) + pure port classifier in Core

**Files:**
- Create: `Sources/WehniRouteCore/LocalEngines.swift`
- Test: `Tests/WehniRouteCoreTests/LocalEngineTests.swift`

**Interfaces:**
- Produces:
  - `struct LocalEngineSpec: Sendable, Equatable` with `kind: ProviderKind`, `ports: [Int]` (first entry is the primary/default port), `blurb: String`, `detectionPaths: [String]`.
  - `enum LocalEngineCatalog` with `static var engines: [LocalEngineSpec]` (one entry per local engine incl. ollama/lmstudio) and `static func byPort(_ port: Int) -> [LocalEngineSpec]` (matches any listed port).
  - `struct LocalProbeResult: Sendable, Equatable` with `path: String`, `status: Int?`, `json: JSONValue?`, `text: String?`.
  - `enum LocalEndpointClassifier` with `static func classify(port: Int, probes: [LocalProbeResult]) -> ProviderKind?` — nil means "reach loopback but could not identify an engine".

> **Why `ports` is an array:** llama.cpp moved its default port 8080 → 9931 (PR #26508, Aug 2026). Native installs after the change listen on 9931; the Docker image and older builds keep 8080. The engine must be discoverable on both, while `defaultBaseURL` stays 8080 for broad compatibility (the adopted provider's URL is rewritten to the detected port by the scanner — Task 5).

- [x] **Step 1: Write the failing test**

Append to `Tests/WehniRouteCoreTests/LocalEngineTests.swift`:

```swift
func testUniquePortsMapDirectlyToKinds() {
    let expectations: [Int: ProviderKind] = [
        1337: .jan, 4891: .gpt4all, 5001: .koboldcpp, 30000: .sglang,
        9997: .xinference, 12434: .dockermodelrunner, 13305: .lemonade,
        4000: .litellm, 11434: .ollama,
    ]
    for (port, kind) in expectations {
        let probes = [LocalProbeResult(path: "/v1/models", status: 200,
                                       json: .object(["data": .array([.object(["id": .string("m")])]))])]
        XCTAssertEqual(LocalEndpointClassifier.classify(port: port, probes: probes), kind)
    }
}

func testLLamaCppIsDiscoveredOnBoth8080And9931() {
    let okHealth = LocalProbeResult(path: "/health", status: 200,
                                    json: .object(["status": .string("ok")]))
    XCTAssertEqual(LocalEndpointClassifier.classify(port: 8080, probes: [okHealth]), .llamacpp)
    XCTAssertEqual(LocalEndpointClassifier.classify(port: 9931, probes: [okHealth]), .llamacpp)
    XCTAssertEqual(LocalEngineCatalog.byPort(9931).map(\.kind), [.llamacpp])
}

func testPort8080Disambiguation() {
    func models(_ ids: [String]) -> LocalProbeResult {
        .init(path: "/v1/models", status: 200,
              json: .object(["data": .array(ids.map { .object(["id": .string($0)]) })]))
    }
    // LocalAI answers /readyz
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8080, probes: [
            .init(path: "/readyz", status: 200, json: nil, text: "ok"), models(["gpt4all"]),
        ]),
        .localai
    )
    // TGI answers /health with an empty 200 body
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8080, probes: [
            .init(path: "/health", status: 200, json: nil, text: ""), models(["t5-small"]),
        ]),
        .tgi
    )
    // llama.cpp / llamafile answer /health with {"status":"ok"}
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8080, probes: [
            .init(path: "/health", status: 200, json: .object(["status": .string("ok")]), text: nil), models(["qwen"]),
        ]),
        .llamacpp
    )
    // MLX models betray the MLX server even on 8080
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8080, probes: [
            models(["mlx-community/Llama-3.2-1B-4bit"]),
        ]),
        .mlxlm
    )
    // Nothing identifiable → nil (the scanner keeps its Antigravity fallback)
    XCTAssertNil(LocalEndpointClassifier.classify(port: 8080, probes: [
        .init(path: "/health", status: 404, json: nil, text: nil),
        .init(path: "/v1/models", status: 404, json: nil, text: nil),
    ]))
}

func testPort8000Disambiguation() {
    // vLLM exposes Prometheus metrics mentioning itself
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8000, probes: [
            .init(path: "/metrics", status: 200, json: nil, text: "# HELP vllm:num_requests_running vllm:foo\n"),
        ]),
        .vllm
    )
    // llama-cpp-python answers /health with {"status":"ok"}
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 8000, probes: [
            .init(path: "/health", status: 200, json: .object(["status": .string("ok")])),
        ]),
        .llamacpppython
    )
}

func testPort5000And1234Disambiguation() {
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 5000, probes: [
            .init(path: "/openapi.json", status: 200, json: .object(["info": .object(["title": .string("TabbyAPI")]))]),
        ]),
        .tabbyapi
    )
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 5000, probes: [
            .init(path: "/openapi.json", status: 404, json: nil, text: nil),
            .init(path: "/v1/models", status: 200, json: .object(["data": .array([])])),
        ]),
        .textgenwebui
    )
    // LM Studio's own v0 API marks the real LM Studio on 1234
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 1234, probes: [
            .init(path: "/api/v0/models", status: 200, json: .object(["data": .array([])])),
        ]),
        .lmstudio
    )
    XCTAssertEqual(
        LocalEndpointClassifier.classify(port: 1234, probes: [
            .init(path: "/api/v0/models", status: 404, json: nil, text: nil),
            .init(path: "/v1/models", status: 200, json: .object(["data": .array([.object(["id": .string("m")])]))]),
        ]),
        .mistralrs
    )
}

func testCatalogCoversEveryLocalEngine() {
    for kind in ProviderKind.localEngines {
        XCTAssertTrue(LocalEngineCatalog.engines.contains { $0.kind == kind },
                      "catalog missing \(kind.rawValue)")
    }
    // Shared ports return multiple candidate engines so the scanner probes
    // every disambiguation path.
    XCTAssertEqual(LocalEngineCatalog.byPort(8080).count, 5)
    XCTAssertEqual(LocalEngineCatalog.byPort(8000).count, 2)
    XCTAssertEqual(LocalEngineCatalog.byPort(5000).count, 2)
    XCTAssertEqual(LocalEngineCatalog.byPort(1234).count, 2)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter LocalEngineTests`
Expected: FAIL — `LocalProbeResult`/`LocalEndpointClassifier`/`LocalEngineCatalog` do not exist.

- [x] **Step 3: Implement LocalEngines.swift**

```swift
import Foundation

// MARK: - Local engine catalog
//
// A pure, offline-testable description of every local inference engine
// WehniRoute can detect. The app-side scanner (LocalSources.swift) performs
// the network work; all decisions live here.

public struct LocalEngineSpec: Sendable, Equatable {
    public let kind: ProviderKind
    /// Loopback ports to probe. The first entry is the primary port used for
    /// the default base URL. llama.cpp lists [8080, 9931] because the native
    /// default moved to 9931 while Docker/older builds keep 8080.
    public let ports: [Int]
    /// Human-facing detection blurb for the scanner UI.
    public let blurb: String
    /// Paths that must be probed (in order) to identify this engine when its
    /// port is shared with other engines. Unique-port engines need only
    /// `/v1/models`.
    public let detectionPaths: [String]

    public init(kind: ProviderKind, ports: [Int], blurb: String, detectionPaths: [String] = ["/v1/models"]) {
        self.kind = kind
        self.ports = ports
        self.blurb = blurb
        self.detectionPaths = detectionPaths
    }
}

public enum LocalEngineCatalog {
    public static let engines: [LocalEngineSpec] = [
        LocalEngineSpec(kind: .ollama, ports: [11434], blurb: "Local models on 127.0.0.1:11434 — imports everything installed", detectionPaths: ["/api/tags"]),
        LocalEngineSpec(kind: .lmstudio, ports: [1234], blurb: "LM Studio's server on 127.0.0.1:1234 — imports downloaded models", detectionPaths: ["/api/v0/models", "/v1/models"]),
        LocalEngineSpec(kind: .jan, ports: [1337], blurb: "Jan's local server on 127.0.0.1:1337"),
        LocalEngineSpec(kind: .gpt4all, ports: [4891], blurb: "GPT4All's API server on 127.0.0.1:4891 (enable it in GPT4All settings)"),
        LocalEngineSpec(kind: .koboldcpp, ports: [5001], blurb: "KoboldCpp on 127.0.0.1:5001"),
        LocalEngineSpec(kind: .textgenwebui, ports: [5000], blurb: "Text Generation WebUI (oobabooga) on 127.0.0.1:5000 — launched with --api"),
        LocalEngineSpec(kind: .tabbyapi, ports: [5000], blurb: "TabbyAPI on 127.0.0.1:5000 — requires an API key by default"),
        LocalEngineSpec(kind: .llamacpp, ports: [8080, 9931], blurb: "llama.cpp's llama-server on 127.0.0.1:8080 (9931 on new native installs)"),
        LocalEngineSpec(kind: .llamafile, ports: [8080], blurb: "llamafile on 127.0.0.1:8080 — same API as llama.cpp"),
        LocalEngineSpec(kind: .localai, ports: [8080], blurb: "LocalAI on 127.0.0.1:8080"),
        LocalEngineSpec(kind: .tgi, ports: [8080], blurb: "Hugging Face TGI on 127.0.0.1:8080"),
        LocalEngineSpec(kind: .mlxlm, ports: [8080], blurb: "MLX-LM server on 127.0.0.1:8080 — Apple Silicon"),
        LocalEngineSpec(kind: .vllm, ports: [8000], blurb: "vLLM on 127.0.0.1:8000", detectionPaths: ["/metrics", "/v1/models"]),
        LocalEngineSpec(kind: .llamacpppython, ports: [8000], blurb: "llama-cpp-python server on 127.0.0.1:8000", detectionPaths: ["/health", "/v1/models"]),
        LocalEngineSpec(kind: .sglang, ports: [30000], blurb: "SGLang on 127.0.0.1:30000"),
        LocalEngineSpec(kind: .mistralrs, ports: [1234], blurb: "mistral.rs on 127.0.0.1:1234"),
        LocalEngineSpec(kind: .xinference, ports: [9997], blurb: "Xinference on 127.0.0.1:9997"),
        LocalEngineSpec(kind: .dockermodelrunner, ports: [12434], blurb: "Docker Model Runner on 127.0.0.1:12434 (enable TCP host access in Docker Desktop)", detectionPaths: ["/engines/v1/models"]),
        LocalEngineSpec(kind: .lemonade, ports: [13305], blurb: "AMD Lemonade on 127.0.0.1:13305 (v10.1+; older installs use 8000)", detectionPaths: ["/api/v1/models"]),
        LocalEngineSpec(kind: .litellm, ports: [4000], blurb: "LiteLLM proxy on 127.0.0.1:4000"),
    ]

    /// Every spec that lists `port` (first entry = primary port).
    public static func byPort(_ port: Int) -> [LocalEngineSpec] {
        engines.filter { $0.ports.contains(port) }
    }
}

public struct LocalProbeResult: Sendable, Equatable {
    public var path: String
    public var status: Int?
    public var json: JSONValue?
    public var text: String?

    public init(path: String, status: Int? = nil, json: JSONValue? = nil, text: String? = nil) {
        self.path = path
        self.status = status
        self.json = json
        self.text = text
    }

    public var isSuccess: Bool {
        guard let status else { return false }
        return (200..<300).contains(status)
    }
}

public enum LocalEndpointClassifier {
    /// Maps loopback probe results onto a provider kind. Returns nil when the
    /// port answers but no known engine can be identified.
    public static func classify(port: Int, probes: [LocalProbeResult]) -> ProviderKind? {
        func probe(_ path: String) -> LocalProbeResult? {
            probes.first { $0.path == path }
        }
        let models = probes.first { $0.path.hasSuffix("/models") }

        switch port {
        case 8080, 9931:
            if probe("/readyz")?.isSuccess == true { return .localai }
            if let health = probe("/health"), health.isSuccess {
                if health.json?["status"]?.stringValue == "ok" { return .llamacpp }
                // TGI returns an empty 200 body on /health.
                if health.json == nil, (health.text ?? "").isEmpty { return .tgi }
            }
            if let list = models, list.isSuccess,
               let ids = list.json?["data"]?.arrayValue?.compactMap({ $0["id"]?.stringValue }),
               ids.contains(where: { $0.lowercased().contains("mlx") }) {
                return .mlxlm
            }
            return nil

        case 8000:
            if let metrics = probe("/metrics"), metrics.isSuccess,
               (metrics.text ?? "").contains("vllm") {
                return .vllm
            }
            if let health = probe("/health"), health.isSuccess,
               health.json?["status"]?.stringValue == "ok" {
                return .llamacpppython
            }
            return nil

        case 5000:
            if let openapi = probe("/openapi.json"),
               (openapi.json?["info"]?["title"]?.stringValue ?? "").lowercased().contains("tabby") {
                return .tabbyapi
            }
            return models?.isSuccess == true ? .textgenwebui : nil

        case 1234:
            if probe("/api/v0/models")?.isSuccess == true { return .lmstudio }
            return models?.isSuccess == true ? .mistralrs : nil

        default:
            guard let spec = LocalEngineCatalog.byPort(port).first else { return nil }
            // Unique-port engines still require a successful catalog probe.
            let path = spec.detectionPaths.first ?? "/v1/models"
            let hit = probes.first { p in
                p.path.hasSuffix(path) || p.path.hasSuffix("/models") || p.path.hasSuffix("/api/tags")
            }
            return hit?.isSuccess == true ? spec.kind : nil
        }
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LocalEngineTests`
Expected: PASS (all previous LocalEngineTests + the new classifier tests).

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/LocalEngines.swift Tests/WehniRouteCoreTests/LocalEngineTests.swift
git commit -m "feat(core): pure local-engine catalog and loopback port classifier"
```

---

### Task 5: Catalog-driven scanner and Store adoption wiring

**Files:**
- Modify: `Sources/WehniRouteApp/LocalSources.swift` (whole file restructure)
- Modify: `Sources/WehniRouteApp/Store.swift:619` (`sourceProviderID`) and `Store.swift:665` (`connectSource`)
- Modify: `Sources/WehniRouteApp/ProvidersView.swift:92` (scan copy)

**Interfaces:**
- Consumes: `LocalEngineCatalog`, `LocalEndpointClassifier`, `LocalProbeResult` (Task 4).
- Produces: `LocalSourceKind` gains a case per new engine (rawValue identical to the `ProviderKind` rawValue); `LocalSourceScanner.scan()` returns candidates for every detected engine, exactly one candidate per responding port, probed **concurrently**; `Store.sourceProviderID(for:)`/`connectSource` map every `LocalSourceKind` case.

**Two constraints the implementation must honor:**
1. **Concurrency:** ~14 distinct loopback ports are probed. Sequential 1.5 s timeouts would make a fully-dead machine's scan take ~20–30 s (today's scanner probes 7 endpoints via `async let`). Probe all ports in one `withTaskGroup`, and all paths of one port concurrently too. Keep the per-probe 1.5 s timeout.
2. **No regression on Antigravity bridges:** the current scanner also probes ports 8877, 11435, and 8045 for Antigravity bridges. Those ports are not engine ports, so they must keep their own probe (as generic OpenAI-compatible servers → `antigravityBridge` candidates). The 8080 unidentified-server fallback stays too.

- [x] **Step 1: Extend `LocalSourceKind`**

Replace the enum and its computed properties in `LocalSources.swift`:

```swift
enum LocalSourceKind: String, Sendable, CaseIterable {
    case ollama
    case lmStudio = "lmstudio"
    case jan
    case gpt4all
    case koboldcpp
    case textgenwebui
    case tabbyapi
    case llamacpp
    case llamafile
    case localai
    case tgi
    case mlxlm
    case vllm
    case llamacpppython
    case sglang
    case mistralrs
    case xinference
    case dockermodelrunner
    case lemonade
    case litellm
    case antigravityBridge
    case talkNova

    var displayName: String {
        if kind == nil && self != .talkNova { return "Antigravity bridge" }
        if self == .talkNova { return "TalkNova" }
        return kind?.displayName ?? "Antigravity bridge"
    }

    /// The equivalent provider kind; nil for the two non-engine sources.
    var kind: ProviderKind? {
        switch self {
        case .antigravityBridge: return nil
        case .talkNova: return nil
        default: return ProviderKind(rawValue: rawValue)
        }
    }
}
```

Delete the old `blurb` computed property — the scanner now builds detail strings from `LocalEngineCatalog` blurbs and live probe results (the catalog's `blurb` serves as the static fallback).

- [x] **Step 2: Rewrite the probes (concurrent, catalog-driven)**

Replace `probeOllama`, `probeLMStudio`, and `probeAntigravityBridges` with one catalog-driven implementation. Note the detected-port base URL: when an engine answers on a non-primary port (llama.cpp on 9931), the candidate's `baseURL` must use the responding port, not the kind's default — rewrite the port in the kind's `defaultBaseURL`.

```swift
    /// Probes every catalog engine on loopback, concurrently. Shared ports
    /// are probed once with all disambiguation paths and classified;
    /// unique ports need a single probe. TalkNova keeps its own probe
    /// (file + key based); the legacy Antigravity bridge ports keep theirs.
    static func scan() async -> [LocalSourceCandidate] {
        async let engines = scanEngines()
        async let bridges = probeExtraBridgePorts()
        async let talkNova = probeTalkNova()
        return await (engines + bridges + talkNova)
    }

    /// Distinct ports that must be probed, with the specs interested in each.
    private static func portMap() -> [Int: [LocalEngineSpec]] {
        var byPort: [Int: [LocalEngineSpec]] = [:]
        for spec in LocalEngineCatalog.engines {
            for port in spec.ports {
                byPort[port, default: []].append(spec)
            }
        }
        return byPort
    }

    private static func scanEngines() async -> [LocalSourceCandidate] {
        let byPort = portMap()
        // Probe every port concurrently; each port probes its paths
        // concurrently too. A dead port costs one timeout, not N.
        let results: [(port: Int, probes: [LocalProbeResult])] = await withTaskGroup(
            of: (Int, [LocalProbeResult]).self
        ) { group in
            for (port, specs) in byPort {
                let paths = Array(Set(specs.flatMap(\.detectionPaths))).sorted()
                group.addTask {
                    let probes = await withTaskGroup(of: LocalProbeResult.self) { inner in
                        for path in paths {
                            inner.addTask { await probePath(port: port, path: path) }
                        }
                        var collected: [LocalProbeResult] = []
                        for await probe in inner { collected.append(probe) }
                        return collected.sorted { $0.path < $1.path }
                    }
                    return (port, probes)
                }
            }
            var collected: [(Int, [LocalProbeResult])] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }

        var found: [LocalSourceCandidate] = []
        for (port, probes) in results {
            guard probes.contains(where: \.isSuccess) else { continue }
            let specs = byPort[port] ?? []

            if specs.count == 1 {
                found.append(candidate(for: specs[0], port: port, probes: probes))
            } else if let kind = LocalEndpointClassifier.classify(port: port, probes: probes) {
                let spec = specs.first { $0.kind == kind } ?? specs[0]
                found.append(candidate(for: spec, port: port, probes: probes))
            } else if port == 8080 {
                // Unidentified OpenAI-compatible server on 8080: keep the
                // historical Antigravity-bridge behavior as the fallback.
                let models = probes.first { $0.path.hasSuffix("/models") }
                if let count = models?.json?["data"]?.arrayValue?.count, count > 0 {
                    found.append(LocalSourceCandidate(
                        kind: .antigravityBridge,
                        name: "Antigravity bridge",
                        baseURL: "http://127.0.0.1:8080/v1",
                        apiKey: nil,
                        detail: "Unidentified local server · \(count) model\(count == 1 ? "" : "s")"
                    ))
                }
            }
        }
        return found
    }

    /// The non-engine Antigravity bridge ports the previous scanner covered.
    /// These stay out of the engine catalog: they are community proxies, not
    /// inference engines, and adoption maps them to the `custom` kind.
    private static func probeExtraBridgePorts() async -> [LocalSourceCandidate] {
        let known: [(port: Int, name: String)] = [
            (8877, "antigravity-proxy"),
            (11435, "Antigravity local bridge"),
            (8045, "Antigravity Manager proxy"),
        ]
        let results = await withTaskGroup(of: LocalSourceCandidate?.self) { group in
            for entry in known {
                group.addTask {
                    let probe = await probePath(port: entry.port, path: "/v1/models")
                    guard let count = probe.json?["data"]?.arrayValue?.count else { return nil }
                    return LocalSourceCandidate(
                        kind: .antigravityBridge,
                        name: entry.name,
                        baseURL: "http://127.0.0.1:\(entry.port)/v1",
                        apiKey: nil,
                        detail: "Detected · \(count) model\(count == 1 ? "" : "s")"
                    )
                }
            }
            var collected: [LocalSourceCandidate] = []
            for await candidate in group {
                if let candidate { collected.append(candidate) }
            }
            return collected
        }
        return results
    }

    private static func probePath(port: Int, path: String) async -> LocalProbeResult {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            return LocalProbeResult(path: path)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return LocalProbeResult(path: path) }
        let status = http.statusCode
        let json = (200..<300).contains(status)
            ? (try? JSONDecoder().decode(JSONValue.self, from: data))
            : nil
        let text = json == nil && (200..<300).contains(status) ? String(data: data, encoding: .utf8) : nil
        return LocalProbeResult(path: path, status: status, json: json, text: text)
    }

    private static func candidate(for spec: LocalEngineSpec, port: Int, probes: [LocalProbeResult]) -> LocalSourceCandidate {
        let modelsProbe = probes.last { $0.path.hasSuffix("/models") || $0.path.hasSuffix("/api/tags") }
        let count = modelsProbe?.json?["data"]?.arrayValue?.count
            ?? modelsProbe?.json?["models"]?.arrayValue?.count
        let detail: String
        if let count, count > 0 {
            detail = "\(count) model\(count == 1 ? "" : "s") served"
        } else if modelsProbe?.isSuccess == true {
            detail = "server reachable"
        } else {
            detail = spec.blurb
        }
        // Rewrite the port when the engine answered on a non-primary port
        // (llama.cpp on 9931), keeping any path suffix from defaultBaseURL.
        var root = spec.kind.defaultBaseURL
        if let primary = spec.ports.first, port != primary,
           let range = root.range(of: ":\(primary)") {
            root.replaceSubrange(range, with: ":\(port)")
        }
        return LocalSourceCandidate(
            kind: LocalSourceKind(rawValue: spec.kind.rawValue) ?? .localai,
            name: spec.kind.displayName,
            baseURL: root,
            apiKey: nil,
            detail: detail
        )
    }
```

Keep `probeTalkNova` exactly as it is. Delete the now-unused `getJSON` helper only if nothing else in the file uses it (the TalkNova probe is file-based). Run `swift build` to confirm.

`LocalSourceCandidate.id` is `"\(kind.rawValue):\(baseURL)"` and still works unchanged.

- [x] **Step 3: Wire Store adoption for every new kind**

In `Store.sourceProviderID(for:)` (line ~619), replace the switch:

```swift
    func sourceProviderID(for candidate: LocalSourceCandidate) -> String? {
        switch candidate.kind {
        case .antigravityBridge:
            let target = normalizedURL(candidate.baseURL)
            return config.providers.first { normalizedURL($0.baseURL) == target }?.id
        case .talkNova:
            return config.provider(id: "talknova") != nil ? "talknova" : nil
        default:
            guard let kind = candidate.kind.kind else { return nil }
            return config.provider(id: kind.rawValue) != nil ? kind.rawValue : nil
        }
    }
```

In `Store.connectSource(_:existingID:)` (line ~665), replace the `switch candidate.kind` body:

```swift
        switch candidate.kind {
        case .antigravityBridge:
            _ = addProvider(kind: .custom, apiKey: "", baseURL: candidate.baseURL, name: candidate.name)
        case .talkNova:
            var key = candidate.apiKey
            if key == nil || key?.isEmpty == true {
                key = await TalkNovaKeyReader.readStoredKey()
            }
            guard let key else {
                showToast("Add your TalkNova key manually — copy it from TalkNova → Settings → API access", kind: .info)
                return nil
            }
            _ = addProvider(kind: .talkNova, apiKey: key)
        default:
            guard let kind = candidate.kind.kind else { return nil }
            _ = addProvider(kind: kind, apiKey: "")
        }
        return candidate.kind == .antigravityBridge
            ? config.providers.last
            : config.provider(id: candidate.kind.kind?.rawValue ?? candidate.kind.rawValue)
```

(TabbyAPI adoption intentionally creates the provider with an empty key; the gateway then reports "No API key → skipped" until the user pastes the TabbyAPI key in Providers — honest behavior, matching the cloud-provider flow.)

- [x] **Step 4: Update the scan-row copy and build the app target**

In `ProvidersView.swift` line 92, replace:

```swift
                    Text("Scan for local model sources — Ollama, LM Studio, Antigravity bridges, TalkNova")
```

with:

```swift
                    Text("Scan for local model sources — Ollama, LM Studio, Jan, GPT4All, KoboldCpp, llama.cpp, vLLM, MLX and more, plus Antigravity bridges and TalkNova")
```

Run: `swift build`
Expected: BUILD SUCCEEDED.

- [x] **Step 5: Run the full test suite and commit**

Run: `swift test`
Expected: all PASS.

```bash
git add Sources/WehniRouteApp/LocalSources.swift Sources/WehniRouteApp/Store.swift Sources/WehniRouteApp/ProvidersView.swift
git commit -m "feat(app): catalog-driven local engine scanning for 18 engines"
```

---

### Task 6: Failover scope — models within a provider before moving on

**Files:**
- Modify: `Sources/WehniRouteCore/Models.swift` (`RoutingConfig`, new `FailoverScope`)
- Modify: `Sources/WehniRouteCore/Router.swift` (`rank`, new `orderedForFailover`)
- Test: `Tests/WehniRouteCoreTests/RouterTests.swift`

**Interfaces:**
- Produces:
  - `enum FailoverScope: String, Codable, Sendable, CaseIterable, Identifiable` with `.global`, `.withinProvider`; `RoutingConfig.failoverScope: FailoverScope` (init default `.global`, decode default `.global`).
  - `static func Router.orderedForFailover(_ candidates: [Candidate], scope: FailoverScope) -> [Candidate]`.
  - `rank` applies the ordering before returning, so `Store.execute`'s existing walk over `ranked.prefix(fallbackAttempts)` inherits the new semantics with zero changes.

- [x] **Step 1: Write the failing test**

Append to `Tests/WehniRouteCoreTests/RouterTests.swift`:

```swift
func testOrderedForFailoverGlobalKeepsScoreOrder() {
    let candidates = [
        Candidate(providerID: "p1", providerName: "P1", modelID: "a", modelName: "a", score: 0.90, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
        Candidate(providerID: "p2", providerName: "P2", modelID: "b", modelName: "b", score: 0.85, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
        Candidate(providerID: "p1", providerName: "P1", modelID: "c", modelName: "c", score: 0.80, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
    ]
    XCTAssertEqual(Router.orderedForFailover(candidates, scope: .global).map(\.modelID), ["a", "b", "c"])
}

func testOrderedForFailoverWithinProviderGroupsByProvider() {
    let candidates = [
        // P1's best (0.90), then P2's best (0.86), then P1's weaker model (0.80),
        // then P2's weaker model (0.70).
        Candidate(providerID: "p1", providerName: "P1", modelID: "a", modelName: "a", score: 0.90, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
        Candidate(providerID: "p2", providerName: "P2", modelID: "b", modelName: "b", score: 0.86, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
        Candidate(providerID: "p1", providerName: "P1", modelID: "c", modelName: "c", score: 0.80, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
        Candidate(providerID: "p2", providerName: "P2", modelID: "d", modelName: "d", score: 0.70, reasons: [], isFree: true, apiFormat: .openAI, contextWindow: 128_000),
    ]
    let ordered = Router.orderedForFailover(candidates, scope: .withinProvider)
    // Providers keep their score rank (P1 best 0.90 before P2 best 0.86), and
    // each provider's models are exhausted by score before the next provider.
    XCTAssertEqual(ordered.map(\.modelID), ["a", "c", "b", "d"])
}

func testRoutingConfigDecodesMissingFailoverScopeAsGlobal() throws {
    let json = #"{"strategy":"auto","tierMode":"both","fallbackAttempts":3}"#.data(using: .utf8)!
    let config = try JSONDecoder().decode(RoutingConfig.self, from: json)
    XCTAssertEqual(config.failoverScope, .global)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter testOrderedForFailover`
Expected: FAIL — `FailoverScope` does not exist.

- [x] **Step 3: Implement**

In `Models.swift`, add above `RoutingConfig`:

```swift
/// How the router orders its fallback chain across the models it scored.
/// `.global` interleaves the best models of every provider by score.
/// `.withinProvider` exhausts each provider's models by score before moving
/// to the next provider — useful when a provider's own models make natural
/// backups for each other (e.g. several GGUF quants on one local engine).
public enum FailoverScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case global
    case withinProvider

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .global: return "Global"
        case .withinProvider: return "Provider first"
        }
    }

    public var blurb: String {
        switch self {
        case .global: return "Failover follows the global model ranking."
        case .withinProvider: return "Try each provider's models by score before moving to the next provider."
        }
    }
}
```

In `RoutingConfig`: add the stored property, init parameter, and coding keys:

```swift
    public var failoverScope: FailoverScope
```

Init parameter — add `failoverScope: FailoverScope = .global` after `fallbackAttempts` and set `self.failoverScope = failoverScope`.

CodingKeys and custom coders:

```swift
    private enum CodingKeys: String, CodingKey {
        case strategy
        case tierMode
        case legacyAllowPaid = "allowPaidModels"
        case weights
        case fallbackAttempts
        case failoverScope
    }
```

In `init(from:)`: `failoverScope = try container.decodeIfPresent(FailoverScope.self, forKey: .failoverScope) ?? .global`
In `encode(to:)`: `try container.encode(failoverScope, forKey: .failoverScope)`

In `Router.rank`, after the existing `candidates.sort { … }` and before `return (candidates, rejected)`:

```swift
        let ordered = orderedForFailover(candidates, scope: config.routing.failoverScope)
        return (ordered, rejected)
```

Add the ordering function in the `Router` enum:

```swift
    /// Reorders the flat candidate list for the fallback walk. Global scope
    /// keeps the existing score-sorted order; withinProvider groups by
    /// provider (providers ranked by their best model, then name for ties)
    /// and orders models inside each group by score.
    static func orderedForFailover(_ candidates: [Candidate], scope: FailoverScope) -> [Candidate] {
        switch scope {
        case .global:
            return candidates
        case .withinProvider:
            var providerOrder: [String] = []
            var bestByProvider: [String: Double] = [:]
            var nameByProvider: [String: String] = [:]
            var buckets: [String: [Candidate]] = [:]
            for candidate in candidates {
                if buckets[candidate.providerID] == nil {
                    providerOrder.append(candidate.providerID)
                    nameByProvider[candidate.providerID] = candidate.providerName
                }
                buckets[candidate.providerID, default: []].append(candidate)
                bestByProvider[candidate.providerID] = max(
                    bestByProvider[candidate.providerID] ?? -1,
                    candidate.score
                )
            }
            let rankedProviders = providerOrder.sorted { a, b in
                let bestA = bestByProvider[a] ?? 0
                let bestB = bestByProvider[b] ?? 0
                if abs(bestA - bestB) > 0.0001 { return bestA > bestB }
                let nameA = nameByProvider[a] ?? a
                let nameB = nameByProvider[b] ?? b
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
            return rankedProviders.flatMap { id in
                (buckets[id] ?? []).sorted { $0.score > $1.score }
            }
        }
    }
```

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RouterTests`
Expected: PASS. The pre-existing rank tests pass because default scope is `.global`.

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/Models.swift Sources/WehniRouteCore/Router.swift Tests/WehniRouteCoreTests/RouterTests.swift
git commit -m "feat(core): failover scope with provider-first model exhaustion"
```

---

### Task 7: Per-model health snapshots in the router

**Files:**
- Modify: `Sources/WehniRouteCore/Router.swift` (`rank` signature and body)
- Test: `Tests/WehniRouteCoreTests/RouterTests.swift`

**Interfaces:**
- Produces: `Router.rank(config:health:modelHealth:estimatedInputTokens:task:now:requestedModel:)` where `modelHealth: [String: HealthSnapshot]` defaults to `[:]` and keys are `"{providerID}/{modelID}"`. Semantics:
  - Provider-level cooldown still rejects the whole provider (unchanged).
  - **A model-level cooldown rejects only that model, with a "Circuit open" rejection reason** (the rank loop gets an explicit rejection branch — this is what the test asserts and what rev 1 forgot).
  - Health and speed scores use the model snapshot when present, otherwise the provider snapshot.

- [x] **Step 1: Write the failing test**

Append to `Tests/WehniRouteCoreTests/RouterTests.swift`:

```swift
func testModelHealthCooldownRejectsOnlyThatModel() {
    var config = AppConfig(
        providers: [
            ProviderConfig(kind: .simulation),
        ],
        models: [
            ModelConfig(providerID: "simulation", modelID: "sim-echo"),
        ],
        routing: RoutingConfig()
    )
    config.models.append(ModelConfig(providerID: "simulation", modelID: "sim-second"))

    let cooling = Date().addingTimeInterval(60)
    let modelHealth = [
        "simulation/sim-second": HealthSnapshot(state: .down, cooldownUntil: cooling),
    ]

    let ranking = Router.rank(
        config: config,
        health: [:],
        modelHealth: modelHealth,
        estimatedInputTokens: 100,
        task: .fast
    )

    XCTAssertFalse(ranking.candidates.contains { $0.modelID == "sim-second" })
    XCTAssertTrue(ranking.candidates.contains { $0.modelID == "sim-echo" })
    XCTAssertTrue(ranking.rejected.contains { $0.modelID == "sim-second" && $0.reason.contains("Circuit open") })
}

func testModelHealthSnapshotDrivesHealthScore() {
    var config = AppConfig(
        providers: [ProviderConfig(kind: .simulation)],
        models: [ModelConfig(providerID: "simulation", modelID: "sim-echo")]
    )

    let healthyAtProvider = Router.rank(
        config: config,
        health: ["simulation": HealthSnapshot(state: .healthy)],
        estimatedInputTokens: 100,
        task: .fast
    ).candidates[0]

    let degradedAtModel = Router.rank(
        config: config,
        health: ["simulation": HealthSnapshot(state: .healthy)],
        modelHealth: ["simulation/sim-echo": HealthSnapshot(state: .degraded)],
        estimatedInputTokens: 100,
        task: .fast
    ).candidates[0]

    XCTAssertGreaterThan(healthyAtProvider.score, degradedAtModel.score)
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --filter testModelHealth`
Expected: FAIL — `rank` has no `modelHealth` parameter.

- [x] **Step 3: Implement**

Change `rank`'s signature to:

```swift
    public static func rank(
        config: AppConfig,
        health: [String: HealthSnapshot],
        modelHealth: [String: HealthSnapshot] = [:],
        estimatedInputTokens: Int,
        task: TaskType,
        now: Date = Date(),
        requestedModel: String? = nil
    ) -> (candidates: [Candidate], rejected: [Rejection]) {
```

Inside the model loop, replace the single snapshot line:

```swift
            let snapshot = health[provider.id] ?? HealthSnapshot()
```

with:

```swift
            let providerSnapshot = health[provider.id] ?? HealthSnapshot()
```

and inside the `for model in models` loop compute the effective per-model snapshot:

```swift
                let modelKey = "\(provider.id)/\(model.modelID)"
                let snapshot = modelHealth[modelKey] ?? providerSnapshot

                if snapshot.isCoolingDown(at: now) {
                    rejected.append(
                        Rejection(
                            providerID: provider.id,
                            providerName: provider.name,
                            modelID: model.modelID,
                            reason: "Circuit open until \(snapshot.cooldownUntil?.formatted(date: .omitted, time: .shortened) ?? "later")"
                        )
                    )
                    continue
                }
```

The provider-level cooldown block above the model loop stays keyed to `providerSnapshot` (it references the old `snapshot` name — update it). All score calls inside the loop (`score(health:)`, `score(latency:)`) and the reason strings already read `snapshot`, so they now automatically prefer model-level health when it exists.

- [x] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RouterTests`
Expected: PASS including pre-existing rank tests (`modelHealth` defaults to `[:]`, so behavior is unchanged when absent).

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteCore/Router.swift Tests/WehniRouteCoreTests/RouterTests.swift
git commit -m "feat(core): per-model health snapshots in routing"
```

---

### Task 8: Store records model-level health and passes it to the router

**Files:**
- Modify: `Sources/WehniRouteApp/Store.swift` (state at line 99, `RoutingSnapshot` at ~848, `currentRoutingSnapshot` at ~860, `execute` at ~1021, `publish` at ~1235)

**Interfaces:**
- Consumes: `Router.rank(config:health:modelHealth:...)` (Task 7), `FailoverScope` (Task 6, read from `config.routing` — no Store change needed for ordering).
- Produces: `@Published var modelHealth: [String: HealthSnapshot]`; snapshot carries it; `execute` updates both provider and model health on every attempt outcome.

- [x] **Step 1: Add the published state**

Next to `@Published var health: [String: HealthSnapshot]` (line 99):

```swift
    @Published var modelHealth: [String: HealthSnapshot] = [:]
```

- [x] **Step 2: Thread it through the snapshot**

In `RoutingSnapshot` add `var modelHealth: [String: HealthSnapshot]`; in `currentRoutingSnapshot()` add `modelHealth: modelHealth` to the constructor call.

- [x] **Step 3: Use and update it in execute**

At the top of `execute`, pass it into the ranking:

```swift
        let ranking = Router.rank(
            config: snapshot.config,
            health: snapshot.health,
            modelHealth: snapshot.modelHealth,
            estimatedInputTokens: estimated,
            task: task,
            requestedModel: requestedModel
        )
```

Add a local working copy next to `var localHealth = snapshot.health`:

```swift
        var localModelHealth = snapshot.modelHealth
```

Key helper (add near `updatedHealthSnapshot`):

```swift
    private nonisolated static func modelHealthKey(providerID: String, modelID: String) -> String {
        "\(providerID)/\(modelID)"
    }
```

Then in the four outcome branches (simulated failure, success, httpError, networkError), immediately after each existing `localHealth[provider.id] = Self.updatedHealthSnapshot(...)` call, add:

```swift
                let modelKey = Self.modelHealthKey(providerID: provider.id, modelID: candidate.modelID)
                localModelHealth[modelKey] = Self.updatedHealthSnapshot(
                    localModelHealth[modelKey],
                    success: /* same boolean as the adjacent provider update */,
                    latency: /* same latency argument as the adjacent provider update */,
                    message: /* same message argument as the adjacent provider update */
                )
```

Concretely: simulated → `success: false, latency: 0, message: detail`; success → `success: true, latency: latency, message: nil`; httpError and networkError → `success: false, latency: latency, message: message`.

(The skipped "No API key" branch intentionally records no health — it is a configuration problem, not a health signal, matching the existing provider behavior.)

Finally, update the `publish(trace:health:baseline:consumedSimulation:)` call sites (three in `execute`, plus the empty-rank guard): add `modelHealth: localModelHealth` and `baselineModelHealth: snapshot.modelHealth` parameters. In `publish` — which currently diffs `updated` against `baseline` and only assigns changed providers — mirror that diff for model health:

```swift
        for (key, snapshot) in updatedModelHealth where baselineModelHealth[key] != snapshot {
            modelHealth[key] = snapshot
        }
```

Read `publish` before editing and mirror its existing diffing exactly; do not introduce wholesale assignment where diffing exists.

- [x] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: BUILD SUCCEEDED, all tests PASS.

- [x] **Step 5: Commit**

```bash
git add Sources/WehniRouteApp/Store.swift
git commit -m "feat(app): record and route on per-model health"
```

---

### Task 9: UI wiring

**Files:**
- Modify: `Sources/WehniRouteApp/RoutingView.swift`
- Modify: `Sources/WehniRouteApp/AddSheets.swift` (verify only)

**Interfaces:**
- Consumes: `FailoverScope` (Task 6), `ProviderKind.addable` (Task 1).

- [x] **Step 1: Add the failover-scope control to RoutingView's `fallbackCard`**

> **Revision note:** rev 1 told the implementer to "copy the tierMode picker" — no such picker exists. `RoutingView` edits `config.routing` through a `fallbackCard` (Fallback ladder) that holds an attempts `Stepper` and the "Allow paid models" `Toggle`, and the file's segmented-control pattern is `TaskSegmentPicker`. Add the scope control to that same header row, mirroring `TaskSegmentPicker` structurally.

In `fallbackCard`, inside the `HStack(spacing: 7)` that holds `ATTEMPTS` + `Stepper`, add a scope control before the stepper (and widen nothing else — the card already uses `ViewThatFits` upstream):

```swift
                    HStack(spacing: 2) {
                        ForEach(FailoverScope.allCases) { scope in
                            Button {
                                store.config.routing.failoverScope = scope
                                store.saveConfig()
                            } label: {
                                Text(scope.label)
                                    .font(.system(size: 9, weight: store.config.routing.failoverScope == scope ? .semibold : .medium))
                                    .foregroundStyle(store.config.routing.failoverScope == scope ? Color(hex: 0x061014) : Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(store.config.routing.failoverScope == scope ? Theme.accent : Color.white.opacity(0.03))
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Capsule().fill(Color.black.opacity(0.18)))
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.8))
                    .help(store.config.routing.failoverScope.blurb)
```

Under the `DividerLine()` in `fallbackCard`, add the blurb caption:

```swift
                Text(store.config.routing.failoverScope.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
```

Check `store.saveConfig()` exists (grep `func saveConfig` in Store.swift); if the card's other controls mutate through `store.binding(\.routing.…)` instead, prefer a `Toggle`-free `Picker` bound via `store.binding(\.routing.failoverScope)` styled to match — whichever pattern the file already uses for `fallbackAttempts` is the one to mirror.

- [x] **Step 2: Verify the add-provider grid renders the new engines**

`ProviderKind.addable` now includes the 18 engines, and the add-provider grid in `AddSheets.swift` renders from that array (`ForEach(ProviderKind.addable)` at line ~139). Confirm: (a) key-less kinds skip the key field — verified key-less path is `requiresKey`-driven (`if !preset.requiresKey { apiKey = "" }`, line ~143), which also gives TabbyAPI its key field automatically; (b) `AddSheets.swift` lines ~478–480 already compute prices/free-ness from `kind.isLocal`, so the new engines inherit correct defaults with no code change. Fix only what breaks.

- [x] **Step 3: Build and manually smoke-test**

Run: `swift build`
Expected: BUILD SUCCEEDED.

Manual smoke test (no engine needed): launch the app, add the "Jan" provider from the grid (no key), confirm the models view offers "Scan for models", flip the Routing page's new "Failover scope" control, confirm Strategy "Local first" blurb still renders.

- [x] **Step 4: Commit**

```bash
git add Sources/WehniRouteApp/RoutingView.swift
git commit -m "feat(app): failover scope control in the routing lab"
```

---

### Task 10: Full verification + release notes

**Files:**
- Create: `docs/release-notes-0.6.0.md` (the latest existing note is 0.5.1, so 0.6.0 is the next version)

- [x] **Step 1: Run the complete suite**

Run: `swift test 2>&1 | tail -5`
Expected: all tests PASS with zero failures and zero skipped-by-accident.

- [x] **Step 2: Build the app target and run a live-loopback sanity scan**

If any engine happens to be installed on the dev machine (e.g. Ollama), launch the app, run the scan, adopt it, send one gateway request, and confirm the trace shows the model-level attempt list. If no engine is installed, verify with the simulation provider only and note it.

- [x] **Step 3: Write release notes**

Create `docs/release-notes-0.6.0.md` following the structure of `release-notes-0.5.1.md` and include:

```markdown
## Local engines, everywhere
- 18 new detectable local inference engines: Jan, GPT4All, KoboldCpp, Text Generation WebUI, TabbyAPI, llama.cpp server, llamafile, LocalAI, Hugging Face TGI, MLX-LM, vLLM, llama-cpp-python, SGLang, mistral.rs, Xinference, Docker Model Runner, AMD Lemonade, LiteLLM Proxy.
- Shared ports (8080, 8000, 5000, 1234) are disambiguated by engine-specific probes instead of guessed.
- llama.cpp servers are detected on both the classic 8080 port and the new 9931 default; TabbyAPI asks for its API key (its server requires auth by default).

## Smarter failover
- New "Failover scope" routing option: Global (previous behavior) or Provider first — exhaust a provider's own models by score before falling over to the next provider.
- Per-model health tracking: one misbehaving model cools down alone; its provider's other models stay in rotation.
```

- [x] **Step 4: Commit**

```bash
git add docs/release-notes-0.6.0.md
git commit -m "docs: release notes for local engines and model-aware failover"
```

---

## Self-Review

**Spec coverage check:**
- "support for ALL these engines" → Tasks 1–5 (18 kinds, routing, requests, discovery, detection). ✅
- "route models within providers as well before moving to next" → Task 6 (`FailoverScope.withinProvider`). ✅
- "not just providers, models too" → the router already scores per-model; Task 6 makes the *failover order* honor model-within-provider priority, Tasks 7–8 make health per-model (including per-model cooldown rejection) so failover decisions are model-granular, not just ordering. ✅

**Web-verification record (2026-11-10):**
- mlx-lm `server.py`: `--port` default **8080** ✅ (mlx-lm SERVER.md + Liquid docs).
- Lemonade v10.1.0 migration wiki + PR #1507: default port **8000 → 13305**, base `http://localhost:8000/api/v1` → `http://localhost:13305/api/v1` ✅; legacy installs keep 8000 (noted).
- llama.cpp PR #26508 + issue #26116 + llama.app docs: `llama-server` default port moves **8080 → 9931**; Docker keeps 8080 ✅ (plan probes both).
- LocalAI docs: default **:8080**, `/readyz` healthcheck endpoint ✅.
- TGI README + router PR #244: `/health` 200 (empty body) on **8080** ✅; upstream is in maintenance mode (noted, no behavior impact).
- llama-cpp-python docs: default port **8000**, `/health` returns `{"status":"ok"}` ✅.
- TabbyAPI wiki/config_sample: port **5000**, auth **required by default** (`disable_auth: false`) → `requiresKey == true` in this revision ✅.
- Jan docs: `127.0.0.1:1337`, OpenAI-compatible `/v1`, auth optional/off by default ✅.
- GPT4All docs: opt-in server on **4891**, `/v1` ✅.
- KoboldCpp docs: **5001**, OpenAI `/v1/` family ✅.
- textgen (oobabooga) wiki: `--api`, default API port **5000** ✅.
- Docker Model Runner docs: `http://localhost:12434/engines/v1`, TCP host access must be enabled on Docker Desktop ✅.
- mistral.rs docs: port **1234**, `/v1` ✅.
- Xinference docs: default **9997** ✅. SGLang: default **30000** ✅. LiteLLM: standard port **4000** (bare-CLI legacy 8000 noted) ✅.

**Code-verification record (against the current tree):**
- `ProviderKind` metadata switches, `addable`, `isLocal` match Models.swift as written. ✅
- `taskFit` cloud values transcribed from Router.swift verbatim; local/simulation values match the originals. ✅
- Task 3 no longer claims to change discovery routing — `parseCatalog`'s `default:` branch already handles `isLocal` tiers; the real changes are `context_length`/`context_window` parsing and the test hook. ✅
- Task 4 uses multi-port `LocalEngineSpec` for llama.cpp (8080 + 9931) and the scanner rewrites the adopted base URL to the responding port. ✅
- Task 5 probes concurrently (TaskGroup) and keeps the legacy Antigravity ports 8877/11435/8045. ✅
- Task 7 adds the model-level cooldown rejection branch the test asserts. ✅
- Task 8 matches `publish`'s actual diffing behavior (diff, not wholesale assign) and all four outcome branches in `execute`. ✅
- Task 9 targets the real `fallbackCard` layout (no tierMode picker exists); TabbyAPI's key field comes free via the existing `requiresKey` path in AddSheets. ✅
- `JSONValue` helpers used in tests (`.num`, `.string`, `arrayValue`, `intValue`) all exist in JSONValue.swift. ✅
- `Store.addProvider(kind:apiKey:baseURL:name:)` signature matches Task 5's calls. ✅

**Type consistency:** `LocalProbeResult`/`LocalEndpointClassifier`/`LocalEngineCatalog` names are used identically in Tasks 4 and 5. `FailoverScope` casing matches between Models.swift, Router.swift, and RoutingView. `modelHealth` key format matches between Tasks 7 and 8 (`providerID/modelID`, mirroring existing `Candidate.id`).
