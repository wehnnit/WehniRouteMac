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
        let models = probes.last { $0.path.hasSuffix("/models") }

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
