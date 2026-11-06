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
    case ollama
    case simulation
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .google: return "Google AI Studio"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .simulation: return "Simulation"
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
        case .ollama: return "Local, no key, no egress"
        case .simulation: return "Offline demo, no key"
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
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .simulation: return "simulation://local"
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
        case .ollama: return "llama3.1"
        case .simulation: return "sim-echo"
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
        case .ollama: return 131_072
        case .simulation: return 128_000
        case .custom: return 128_000
        }
    }

    public var defaultInputPrice: Double? {
        switch self {
        case .anthropic: return 3.0
        case .openai: return 0.15
        case .groq, .google, .ollama, .simulation: return 0
        case .openrouter, .custom: return nil
        }
    }

    public var defaultOutputPrice: Double? {
        switch self {
        case .anthropic: return 15.0
        case .openai: return 0.60
        case .groq, .google, .ollama, .simulation: return 0
        case .openrouter, .custom: return nil
        }
    }

    public var defaultModelIsFree: Bool {
        switch self {
        case .groq, .google, .ollama, .simulation: return true
        case .anthropic, .openai, .openrouter, .custom: return false
        }
    }

    public var requiresKey: Bool {
        switch self {
        case .ollama, .simulation: return false
        default: return true
        }
    }

    public var isLocal: Bool {
        self == .ollama || self == .simulation
    }

    public var symbol: String {
        switch self {
        case .anthropic: return "sparkles"
        case .openai: return "circle.hexagongrid.fill"
        case .groq: return "bolt.fill"
        case .google: return "diamond.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .ollama: return "desktopcomputer"
        case .simulation: return "flask.fill"
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
        case .ollama: return 0xE5E7EB
        case .simulation: return 0xFBBF24
        case .custom: return 0x5EEAD4
        }
    }

    /// Kinds shown first in the add-provider grid.
    public static var addable: [ProviderKind] {
        [.anthropic, .openai, .groq, .google, .openrouter, .ollama, .simulation, .custom]
    }
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

    public init(
        id: UUID = UUID(),
        providerID: String,
        modelID: String,
        displayName: String = "",
        enabled: Bool = true,
        contextWindow: Int = 128_000,
        inputPerMillion: Double? = nil,
        outputPerMillion: Double? = nil,
        isFree: Bool = false
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

public struct RoutingConfig: Codable, Sendable, Equatable {
    public var strategy: Strategy
    public var allowPaidModels: Bool
    public var weights: RoutingWeights
    public var fallbackAttempts: Int

    public init(
        strategy: Strategy = .auto,
        allowPaidModels: Bool = true,
        weights: RoutingWeights = .balanced,
        fallbackAttempts: Int = 4
    ) {
        self.strategy = strategy
        self.allowPaidModels = allowPaidModels
        self.weights = weights
        self.fallbackAttempts = fallbackAttempts
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
        responsePreview: String = ""
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
