import Foundation

// MARK: - Providers

public enum APIFormat: String, Codable, Sendable, CaseIterable {
    case openAI = "openai-compatible"
    case anthropic

    public var label: String {
        switch self {
        case .openAI: return "OpenAI-compatible"
        case .anthropic: return "Anthropic Messages"
        }
    }
}

public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai
    case groq
    case google
    case openrouter
    case mistral
    case xai
    case deepseek
    case together
    case cerebras
    case fireworks
    case moonshot
    case nvidia
    case ollama
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
    case talkNova = "talknova"
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .google: return "Google AI Studio"
        case .openrouter: return "OpenRouter"
        case .mistral: return "Mistral"
        case .xai: return "xAI Grok"
        case .deepseek: return "DeepSeek"
        case .together: return "Together AI"
        case .cerebras: return "Cerebras"
        case .fireworks: return "Fireworks AI"
        case .moonshot: return "Moonshot Kimi"
        case .nvidia: return "NVIDIA NIM"
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
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
        case .simulation: return "Simulation"
        case .talkNova: return "TalkNova"
        case .custom: return "Custom endpoint"
        }
    }

    public var tagline: String {
        switch self {
        case .anthropic: return "Claude, direct"
        case .openai: return "GPT models, direct"
        case .groq: return "Fast open models"
        case .google: return "Gemini, generous free tier"
        case .openrouter: return "One key, many models"
        case .mistral: return "Mistral, direct"
        case .xai: return "Grok models, direct"
        case .deepseek: return "DeepSeek, direct"
        case .together: return "Open models, one key"
        case .cerebras: return "Wafer-fast inference"
        case .fireworks: return "Fast open-model serving"
        case .moonshot: return "Kimi models, direct"
        case .nvidia: return "NIM, free credits"
        case .ollama: return "Local, no key, no egress"
        case .lmstudio: return "Local server, your models"
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
        case .simulation: return "Offline demo, no key"
        case .talkNova: return "TalkNova catalog with your personal key"
        case .custom: return "Any OpenAI-compatible API"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .xai: return "https://api.x.ai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .together: return "https://api.together.ai/v1"
        case .cerebras: return "https://api.cerebras.ai/v1"
        case .fireworks: return "https://api.fireworks.ai/inference/v1"
        case .moonshot: return "https://api.moonshot.ai/v1"
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .lmstudio: return "http://127.0.0.1:1234/v1"
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
        case .simulation: return "simulation://local"
        case .talkNova: return "https://talknova.site/v1"
        case .custom: return "https://"
        }
    }

    public var defaultAPIFormat: APIFormat {
        self == .anthropic ? .anthropic : .openAI
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openai: return "gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .google: return "gemini-2.5-flash"
        case .openrouter: return "openrouter/auto"
        case .mistral: return "mistral-small-latest"
        case .xai: return "grok-4"
        case .deepseek: return "deepseek-chat"
        case .together: return "meta-llama/Llama-3.3-70B-Instruct-Turbo"
        case .cerebras: return "llama-3.3-70b"
        case .fireworks: return ""
        case .moonshot: return "kimi-k2"
        case .nvidia: return "meta/llama-3.3-70b-instruct"
        case .ollama: return "llama3.1"
        case .lmstudio: return ""
        case .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
             .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
             .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade,
             .litellm: return ""
        case .simulation: return "sim-echo"
        case .talkNova: return "nova-spark"
        case .custom: return ""
        }
    }

    public var defaultContextWindow: Int {
        switch self {
        case .anthropic: return 500_000
        case .openai: return 400_000
        case .groq: return 131_072
        case .google: return 1_000_000
        case .openrouter: return 200_000
        case .mistral: return 128_000
        case .xai: return 256_000
        case .deepseek: return 128_000
        case .together: return 131_072
        case .cerebras: return 131_072
        case .fireworks: return 131_072
        case .moonshot: return 131_072
        case .nvidia: return 131_072
        case .ollama: return 131_072
        case .lmstudio: return 131_072
        case .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
             .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
             .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade,
             .litellm: return 131_072
        case .simulation: return 128_000
        case .talkNova: return 128_000
        case .custom: return 128_000
        }
    }

    public var defaultInputPrice: Double? {
        switch self {
        case .anthropic: return 3.0
        case .openai: return 0.15
        case .groq, .google, .ollama, .lmstudio, .simulation, .jan, .gpt4all,
             .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp, .llamafile,
             .localai, .tgi, .mlxlm, .vllm, .llamacpppython, .sglang,
             .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm: return 0
        case .mistral: return 2.0
        case .xai: return 3.0
        case .deepseek: return 0.27
        case .openrouter, .together, .cerebras, .fireworks, .moonshot, .nvidia, .talkNova, .custom: return nil
        }
    }

    public var defaultOutputPrice: Double? {
        switch self {
        case .anthropic: return 15.0
        case .openai: return 0.60
        case .groq, .google, .ollama, .lmstudio, .simulation, .jan, .gpt4all,
             .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp, .llamafile,
             .localai, .tgi, .mlxlm, .vllm, .llamacpppython, .sglang,
             .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm: return 0
        case .mistral: return 6.0
        case .xai: return 15.0
        case .deepseek: return 1.10
        case .openrouter, .together, .cerebras, .fireworks, .moonshot, .nvidia, .talkNova, .custom: return nil
        }
    }

    public var defaultModelIsFree: Bool {
        switch self {
        case .groq, .google, .ollama, .lmstudio, .simulation, .jan, .gpt4all,
             .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp, .llamafile,
             .localai, .tgi, .mlxlm, .vllm, .llamacpppython, .sglang,
             .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm: return true
        case .anthropic, .openai, .openrouter, .mistral, .xai, .deepseek, .together,
             .cerebras, .fireworks, .moonshot, .nvidia, .talkNova, .custom: return false
        }
    }

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

    public var isLocal: Bool {
        ProviderKind.localEngines.contains(self) || self == .simulation
    }

    public var symbol: String {
        switch self {
        case .anthropic: return "sparkles"
        case .openai: return "circle.hexagongrid.fill"
        case .groq: return "bolt.fill"
        case .google: return "diamond.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .mistral: return "paperplane.fill"
        case .xai: return "xmark"
        case .deepseek: return "whale"
        case .together: return "square.stack.3d.up.fill"
        case .cerebras: return "cpu"
        case .fireworks: return "flame.fill"
        case .moonshot: return "moon.fill"
        case .nvidia: return "waveform.path.ecg"
        case .ollama: return "desktopcomputer"
        case .lmstudio: return "server.rack"
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
        case .simulation: return "flask.fill"
        case .talkNova: return "bubble.left.and.bubble.right.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var accentHex: UInt32 {
        switch self {
        case .anthropic: return 0xD97757
        case .openai: return 0x74AA9C
        case .groq: return 0xF55036
        case .google: return 0x4285F4
        case .openrouter: return 0x8B5CF6
        case .mistral: return 0xFF7000
        case .xai: return 0xE8E8E8
        case .deepseek: return 0x4D6BFE
        case .together: return 0x0F6FFF
        case .cerebras: return 0xF97316
        case .fireworks: return 0xEF4444
        case .moonshot: return 0x1A1A2E
        case .nvidia: return 0x76B900
        case .ollama: return 0xE5E7EB
        case .lmstudio: return 0xC4B5FD
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
        case .simulation: return 0xFBBF24
        case .talkNova: return 0x38BDF8
        case .custom: return 0x5EEAD4
        }
    }

    /// Kinds shown first in the add-provider grid.
    public static var addable: [ProviderKind] {
        [.anthropic, .openai, .google, .groq, .mistral, .xai, .deepseek, .openrouter,
         .together, .cerebras, .fireworks, .moonshot, .nvidia,
         .ollama, .lmstudio, .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi,
         .llamacpp, .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
         .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
         .talkNova, .simulation, .custom]
    }

    /// Every kind that runs inference on this machine via a loopback HTTP
    /// API. Router and client behavior keys off `isLocal`; this list is for
    /// UI grouping, scanning, and tests. Simulation is excluded on purpose.
    public static let localEngines: [ProviderKind] = [
        .ollama, .lmstudio, .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi,
        .llamacpp, .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
        .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
    ]
}

public enum SimulatedFailure: String, Codable, CaseIterable, Sendable, Identifiable {
    case rateLimit = "429"
    case timeout
    case outage

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rateLimit: return "Rate limit (429)"
        case .timeout: return "Timeout"
        case .outage: return "Provider outage (503)"
        }
    }
}

public struct ProviderConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: ProviderKind
    public var name: String
    public var baseURL: String
    public var apiFormat: APIFormat
    public var enabled: Bool
    public var addedAt: Date
    public var simulatedFailure: SimulatedFailure?

    public init(
        kind: ProviderKind,
        id: String? = nil,
        name: String? = nil,
        baseURL: String? = nil,
        apiFormat: APIFormat? = nil,
        enabled: Bool = true,
        addedAt: Date = Date(),
        simulatedFailure: SimulatedFailure? = nil
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.name = name ?? kind.displayName
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.apiFormat = apiFormat ?? kind.defaultAPIFormat
        self.enabled = enabled
        self.addedAt = addedAt
        self.simulatedFailure = simulatedFailure
    }

    public var keychainAccount: String { "provider.\(id)" }
}

public struct ModelConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var providerID: String
    public var modelID: String
    public var displayName: String
    public var enabled: Bool
    public var contextWindow: Int
    public var inputPerMillion: Double?
    public var outputPerMillion: Double?
    public var isFree: Bool
    /// Human-facing tier explanation, e.g. "free tier rate limits apply" or
    /// "draws from your plan allowance". Never affects routing.
    public var tierNote: String?

    public init(
        id: UUID = UUID(),
        providerID: String,
        modelID: String,
        displayName: String = "",
        enabled: Bool = true,
        contextWindow: Int = 128_000,
        inputPerMillion: Double? = nil,
        outputPerMillion: Double? = nil,
        isFree: Bool = false,
        tierNote: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.displayName = displayName.isEmpty ? modelID : displayName
        self.enabled = enabled
        self.contextWindow = contextWindow
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.isFree = isFree
        self.tierNote = tierNote
    }

    public var blendedPrice: Double {
        (inputPerMillion ?? 0) + (outputPerMillion ?? 0) * 2
    }
}

// MARK: - Health

public enum HealthState: String, Codable, Sendable, CaseIterable {
    case unknown
    case healthy
    case degraded
    case down

    public var label: String {
        switch self {
        case .unknown: return "Untested"
        case .healthy: return "Healthy"
        case .degraded: return "Degraded"
        case .down: return "Circuit open"
        }
    }
}

public struct HealthSnapshot: Codable, Sendable, Equatable {
    public var state: HealthState
    public var consecutiveFailures: Int
    public var cooldownUntil: Date?
    public var avgLatencyMS: Int?
    public var lastChecked: Date?
    public var lastError: String?

    public init(
        state: HealthState = .unknown,
        consecutiveFailures: Int = 0,
        cooldownUntil: Date? = nil,
        avgLatencyMS: Int? = nil,
        lastChecked: Date? = nil,
        lastError: String? = nil
    ) {
        self.state = state
        self.consecutiveFailures = consecutiveFailures
        self.cooldownUntil = cooldownUntil
        self.avgLatencyMS = avgLatencyMS
        self.lastChecked = lastChecked
        self.lastError = lastError
    }

    public func isCoolingDown(at date: Date) -> Bool {
        guard let cooldownUntil else { return false }
        return cooldownUntil > date
    }
}

// MARK: - Routing

public enum Strategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case coding
    case fast
    case cheap
    case reliable
    case local

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .coding: return "Coding"
        case .fast: return "Fast"
        case .cheap: return "Cheap"
        case .reliable: return "Reliable"
        case .local: return "Local first"
        }
    }

    public var blurb: String {
        switch self {
        case .auto: return "Balanced scoring across fit, health, speed and cost."
        case .coding: return "Favors models that are strong at code and tools."
        case .fast: return "Prioritizes low latency and responsive providers."
        case .cheap: return "Favors free tiers and the lowest blended price."
        case .reliable: return "Prioritizes healthy providers with clean records."
        case .local: return "Keeps traffic on Ollama and the simulation provider."
        }
    }

    public var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .fast: return "hare.fill"
        case .cheap: return "leaf.fill"
        case .reliable: return "shield.lefthalf.filled"
        case .local: return "desktopcomputer"
        }
    }

    public var accentHex: UInt32 {
        switch self {
        case .auto: return 0x5EEAD4
        case .coding: return 0xA78BFA
        case .fast: return 0xFBBF24
        case .cheap: return 0x34D399
        case .reliable: return 0x60A5FA
        case .local: return 0xF472B6
        }
    }
}

public struct RoutingWeights: Codable, Sendable, Equatable {
    public var taskFit: Double
    public var health: Double
    public var speed: Double
    public var cost: Double
    public var context: Double
    public var quota: Double

    public init(
        taskFit: Double = 0.30,
        health: Double = 0.25,
        speed: Double = 0.15,
        cost: Double = 0.15,
        context: Double = 0.10,
        quota: Double = 0.05
    ) {
        self.taskFit = taskFit
        self.health = health
        self.speed = speed
        self.cost = cost
        self.context = context
        self.quota = quota
    }

    public static let balanced = RoutingWeights()

    public static func preset(for strategy: Strategy) -> RoutingWeights {
        switch strategy {
        case .auto:
            return .balanced
        case .coding:
            return RoutingWeights(taskFit: 0.42, health: 0.20, speed: 0.08, cost: 0.10, context: 0.15, quota: 0.05)
        case .fast:
            return RoutingWeights(taskFit: 0.15, health: 0.15, speed: 0.45, cost: 0.10, context: 0.05, quota: 0.10)
        case .cheap:
            return RoutingWeights(taskFit: 0.15, health: 0.15, speed: 0.05, cost: 0.45, context: 0.05, quota: 0.15)
        case .reliable:
            return RoutingWeights(taskFit: 0.15, health: 0.50, speed: 0.10, cost: 0.05, context: 0.05, quota: 0.15)
        case .local:
            return RoutingWeights(taskFit: 0.20, health: 0.20, speed: 0.10, cost: 0.30, context: 0.05, quota: 0.15)
        }
    }

    public var normalized: RoutingWeights {
        let total = taskFit + health + speed + cost + context + quota
        guard total > 0 else { return .balanced }
        return RoutingWeights(
            taskFit: taskFit / total,
            health: health / total,
            speed: speed / total,
            cost: cost / total,
            context: context / total,
            quota: quota / total
        )
    }
}

/// Which tiers of models the router may consider. Replaces the old
/// `allowPaidModels` boolean, which stays available as a computed alias so
/// existing configs, exports, and call sites keep working.
public enum TierMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case freeOnly
    case paidOnly
    case both

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .freeOnly: return "Free"
        case .paidOnly: return "Paid"
        case .both: return "Both"
        }
    }

    public var blurb: String {
        switch self {
        case .freeOnly: return "Route only free-tier and local models."
        case .paidOnly: return "Route only models that draw on a paid balance."
        case .both: return "Route everything the policy allows."
        }
    }
}

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

public struct RoutingConfig: Codable, Sendable, Equatable {
    public var strategy: Strategy
    public var tierMode: TierMode
    public var weights: RoutingWeights
    public var fallbackAttempts: Int
    public var failoverScope: FailoverScope

    /// Legacy alias kept for existing configs, exports, and call sites.
    public var allowPaidModels: Bool {
        get { tierMode != .freeOnly }
        set { tierMode = newValue ? .both : .freeOnly }
    }

    public init(
        strategy: Strategy = .auto,
        tierMode: TierMode = .both,
        weights: RoutingWeights = .balanced,
        fallbackAttempts: Int = 4,
        failoverScope: FailoverScope = .global
    ) {
        self.strategy = strategy
        self.tierMode = tierMode
        self.weights = weights
        self.fallbackAttempts = fallbackAttempts
        self.failoverScope = failoverScope
    }

    private enum CodingKeys: String, CodingKey {
        case strategy
        case tierMode
        case legacyAllowPaid = "allowPaidModels"
        case weights
        case fallbackAttempts
        case failoverScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strategy = try container.decodeIfPresent(Strategy.self, forKey: .strategy) ?? .auto
        if let mode = try container.decodeIfPresent(TierMode.self, forKey: .tierMode) {
            tierMode = mode
        } else if let legacy = try container.decodeIfPresent(Bool.self, forKey: .legacyAllowPaid) {
            tierMode = legacy ? .both : .freeOnly
        } else {
            tierMode = .both
        }
        weights = try container.decodeIfPresent(RoutingWeights.self, forKey: .weights) ?? .balanced
        fallbackAttempts = try container.decodeIfPresent(Int.self, forKey: .fallbackAttempts) ?? 4
        failoverScope = try container.decodeIfPresent(FailoverScope.self, forKey: .failoverScope) ?? .global
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(tierMode, forKey: .tierMode)
        // Kept for older exports and third-party readers.
        try container.encode(allowPaidModels, forKey: .legacyAllowPaid)
        try container.encode(weights, forKey: .weights)
        try container.encode(fallbackAttempts, forKey: .fallbackAttempts)
        try container.encode(failoverScope, forKey: .failoverScope)
    }
}

public enum TaskType: String, Codable, Sendable, CaseIterable {
    case coding
    case reasoning
    case writing
    case fast
    case vision
    case unknown

    public var label: String {
        rawValue.capitalized
    }
}

// MARK: - Configuration

public struct AppConfig: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var providers: [ProviderConfig]
    public var models: [ModelConfig]
    public var routing: RoutingConfig
    public var gatewayPort: Int
    public var requireAPIKey: Bool
    public var createdAt: Date
    public var isFirstRun: Bool

    public init(
        schemaVersion: Int = 1,
        providers: [ProviderConfig] = [],
        models: [ModelConfig] = [],
        routing: RoutingConfig = RoutingConfig(),
        gatewayPort: Int = 20128,
        requireAPIKey: Bool = false,
        createdAt: Date = Date(),
        isFirstRun: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.models = models
        self.routing = routing
        self.gatewayPort = gatewayPort
        self.requireAPIKey = requireAPIKey
        self.createdAt = createdAt
        self.isFirstRun = isFirstRun
    }

    public func provider(id: String) -> ProviderConfig? {
        providers.first { $0.id == id }
    }

    public func models(for providerID: String) -> [ModelConfig] {
        models.filter { $0.providerID == providerID }
    }

    public var enabledProviders: [ProviderConfig] {
        providers.filter(\.enabled)
    }

    public var enabledModels: [ModelConfig] {
        models.filter(\.enabled)
    }

    public mutating func addDefaultModel(for provider: ProviderConfig) {
        guard !provider.kind.defaultModel.isEmpty else { return }
        guard !models.contains(where: { $0.providerID == provider.id }) else { return }
        models.append(
            ModelConfig(
                providerID: provider.id,
                modelID: provider.kind.defaultModel,
                contextWindow: provider.kind.defaultContextWindow,
                inputPerMillion: provider.kind.defaultInputPrice,
                outputPerMillion: provider.kind.defaultOutputPrice,
                isFree: provider.kind.defaultModelIsFree
            )
        )
    }
}

// MARK: - Traces

public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int

    public init(input: Int = 0, output: Int = 0) {
        self.input = input
        self.output = output
    }

    public var total: Int { input + output }
    public static let zero = TokenUsage()
}

public enum AttemptOutcome: String, Codable, Sendable {
    case success
    case httpError
    case networkError
    case simulated
    case skipped

    public var label: String {
        switch self {
        case .success: return "Success"
        case .httpError: return "HTTP error"
        case .networkError: return "Network error"
        case .simulated: return "Simulated"
        case .skipped: return "Skipped"
        }
    }
}

public struct TraceAttempt: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var providerID: String
    public var providerName: String
    public var model: String
    public var outcome: AttemptOutcome
    public var status: Int?
    public var latencyMS: Int
    public var detail: String?

    public init(
        id: UUID = UUID(),
        providerID: String,
        providerName: String,
        model: String,
        outcome: AttemptOutcome,
        status: Int? = nil,
        latencyMS: Int = 0,
        detail: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.providerName = providerName
        self.model = model
        self.outcome = outcome
        self.status = status
        self.latencyMS = latencyMS
        self.detail = detail
    }
}

public struct Trace: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var requestID: String
    public var endpoint: String
    public var requestedModel: String
    public var taskType: TaskType
    public var strategy: Strategy
    public var selectedProviderID: String?
    public var selectedProviderName: String?
    public var selectedModel: String?
    public var status: Int
    public var latencyMS: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double
    public var fallbackUsed: Bool
    public var attempts: [TraceAttempt]
    public var errorSummary: String?
    public var requestPreview: String
    public var responsePreview: String
    /// Which harness (when attributable) issued the request. Presence-only.
    public var harness: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        requestID: String,
        endpoint: String,
        requestedModel: String,
        taskType: TaskType,
        strategy: Strategy,
        selectedProviderID: String? = nil,
        selectedProviderName: String? = nil,
        selectedModel: String? = nil,
        status: Int,
        latencyMS: Int,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        costUSD: Double = 0,
        fallbackUsed: Bool = false,
        attempts: [TraceAttempt] = [],
        errorSummary: String? = nil,
        requestPreview: String = "",
        responsePreview: String = "",
        harness: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.requestID = requestID
        self.endpoint = endpoint
        self.requestedModel = requestedModel
        self.taskType = taskType
        self.strategy = strategy
        self.selectedProviderID = selectedProviderID
        self.selectedProviderName = selectedProviderName
        self.selectedModel = selectedModel
        self.status = status
        self.latencyMS = latencyMS
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.fallbackUsed = fallbackUsed
        self.attempts = attempts
        self.errorSummary = errorSummary
        self.requestPreview = requestPreview
        self.responsePreview = responsePreview
        self.harness = harness
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
    public var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Formatting helpers

public enum Format {
    public static func money(_ value: Double) -> String {
        if value == 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        return String(format: "$%.2f", value)
    }

    public static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return "\(value)"
    }

    public static func latency(_ ms: Int) -> String {
        ms >= 1_000 ? String(format: "%.1fs", Double(ms) / 1_000) : "\(ms) ms"
    }
}
