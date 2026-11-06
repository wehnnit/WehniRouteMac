import Foundation

public struct Rejection: Sendable, Identifiable, Equatable {
    public var id: String { "\(providerID)/\(modelID)" }
    public let providerID: String
    public let providerName: String
    public let modelID: String
    public let reason: String

    public init(providerID: String, providerName: String, modelID: String, reason: String) {
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.reason = reason
    }
}

public struct Candidate: Sendable, Identifiable, Equatable {
    public var id: String { "\(providerID)/\(modelID)" }
    public let providerID: String
    public let providerName: String
    public let modelID: String
    public let modelName: String
    public let score: Double
    public let reasons: [String]
    public let isFree: Bool
    public let apiFormat: APIFormat
    public let contextWindow: Int

    public init(
        providerID: String,
        providerName: String,
        modelID: String,
        modelName: String,
        score: Double,
        reasons: [String],
        isFree: Bool,
        apiFormat: APIFormat,
        contextWindow: Int
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.modelID = modelID
        self.modelName = modelName
        self.score = score
        self.reasons = reasons
        self.isFree = isFree
        self.apiFormat = apiFormat
        self.contextWindow = contextWindow
    }
}

public enum Router {
    /// Cheap, deterministic classifier. The UI shows the result and every
    /// routing decision records it, but it never leaves the machine.
    public static func classify(messages: [JSONValue], tools: [JSONValue]?) -> TaskType {
        if tools?.isEmpty == false { return .coding }
        let text = messages
            .compactMap { message -> String? in
                if let content = message["content"]?.stringValue { return content }
                if let blocks = message["content"]?.arrayValue {
                    return blocks.compactMap { $0["text"]?.stringValue }.joined(separator: " ")
                }
                return nil
            }
            .joined(separator: " ")
            .lowercased()

        if text.contains("image_url") || text.contains("\"type\":\"image\"") { return .vision }

        let codeHints = [
            "```", "function", "swift", "typescript", "javascript", "python", "rust",
            "compile", "stack trace", "bug", "regex", "api", "sql", "refactor", "unit test",
        ]
        if codeHints.contains(where: { text.contains($0) }) { return .coding }

        let reasoningHints = ["prove", "derive", "step by step", "analyze", "trade-off", "architecture"]
        if reasoningHints.contains(where: { text.contains($0) }) { return .reasoning }

        let writingHints = ["write", "rewrite", "summarize", "email", "essay", "tone", "copy"]
        if writingHints.contains(where: { text.contains($0) }) { return .writing }

        if text.count < 160 { return .fast }
        return .unknown
    }

    public static func estimateTokens(messages: [JSONValue], tools: [JSONValue]? = nil) -> Int {
        var characters = 0
        for message in messages {
            if let content = message["content"]?.stringValue {
                characters += content.count
            } else if let blocks = message["content"]?.arrayValue {
                for block in blocks {
                    characters += block["text"]?.stringValue?.count ?? 0
                }
            }
            characters += 8
        }
        if let tools {
            characters += tools.reduce(0) { $0 + $1.jsonString.count }
        }
        return max(1, characters / 4)
    }

    public static func rank(
        config: AppConfig,
        health: [String: HealthSnapshot],
        estimatedInputTokens: Int,
        task: TaskType,
        now: Date = Date(),
        requestedModel: String? = nil
    ) -> (candidates: [Candidate], rejected: [Rejection]) {
        let weights = config.routing.weights.normalized
        var candidates: [Candidate] = []
        var rejected: [Rejection] = []

        for provider in config.providers where provider.enabled {
            let models = config.models.filter { $0.providerID == provider.id && $0.enabled }
            if models.isEmpty {
                rejected.append(
                    Rejection(
                        providerID: provider.id,
                        providerName: provider.name,
                        modelID: "—",
                        reason: "No enabled models"
                    )
                )
                continue
            }

            let snapshot = health[provider.id] ?? HealthSnapshot()
            if snapshot.isCoolingDown(at: now) {
                rejected.append(
                    Rejection(
                        providerID: provider.id,
                        providerName: provider.name,
                        modelID: "—",
                        reason: "Circuit open until \(snapshot.cooldownUntil?.formatted(date: .omitted, time: .shortened) ?? "later")"
                    )
                )
                continue
            }

            for model in models {
                if !config.routing.allowPaidModels && !model.isFree {
                    rejected.append(
                        Rejection(
                            providerID: provider.id,
                            providerName: provider.name,
                            modelID: model.modelID,
                            reason: "Paid model while paid routing is off"
                        )
                    )
                    continue
                }

                if estimatedInputTokens > model.contextWindow {
                    rejected.append(
                        Rejection(
                            providerID: provider.id,
                            providerName: provider.name,
                            modelID: model.modelID,
                            reason: "Context \(Format.compact(estimatedInputTokens)) exceeds \(Format.compact(model.contextWindow))"
                        )
                    )
                    continue
                }

                let fit = taskFit(kind: provider.kind, task: task, strategy: config.routing.strategy)
                let healthScore = score(health: snapshot, failures: snapshot.consecutiveFailures)
                let speedScore = score(latency: snapshot.avgLatencyMS, provider: provider.kind)
                let costScore = score(cost: model)
                let contextScore = score(contextWindow: model.contextWindow, estimatedTokens: estimatedInputTokens)
                let quotaScore = provider.kind.isLocal ? 1.0 : (model.isFree ? 0.92 : 0.55)

                var total =
                    weights.taskFit * fit +
                    weights.health * healthScore +
                    weights.speed * speedScore +
                    weights.cost * costScore +
                    weights.context * contextScore +
                    weights.quota * quotaScore

                var reasons: [String] = [
                    "fit \(percent(fit))",
                    "\(snapshot.state.label.lowercased()) \(percent(healthScore))",
                    "\(Format.latency(snapshot.avgLatencyMS ?? fallbackLatency(provider.kind)))",
                    model.isFree ? "free tier" : "\(Format.money(model.blendedPrice))/M blended",
                    "\(Format.compact(model.contextWindow)) ctx",
                ]

                if let requestedModel, !requestedModel.isEmpty, requestedModel != "auto" {
                    if model.modelID == requestedModel || model.displayName == requestedModel {
                        total += 0.18
                        reasons.append("requested model")
                    }
                }

                if provider.simulatedFailure != nil {
                    total -= 0.25
                    reasons.append("simulation armed")
                }

                candidates.append(
                    Candidate(
                        providerID: provider.id,
                        providerName: provider.name,
                        modelID: model.modelID,
                        modelName: model.displayName,
                        score: min(1, max(0, total)),
                        reasons: reasons,
                        isFree: model.isFree,
                        apiFormat: provider.apiFormat,
                        contextWindow: model.contextWindow
                    )
                )
            }
        }

        candidates.sort {
            if abs($0.score - $1.score) < 0.0001 {
                return $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
            return $0.score > $1.score
        }
        return (candidates, rejected)
    }

    // MARK: - Scores

    static func taskFit(kind: ProviderKind, task: TaskType, strategy: Strategy) -> Double {
        if strategy == .local {
            return kind.isLocal ? 1.0 : 0.25
        }
        if strategy == .cheap {
            return kind.isLocal ? 1.0 : 0.55
        }
        if strategy == .reliable {
            switch kind {
            case .anthropic, .openai, .google: return 0.9
            case .groq, .openrouter: return 0.8
            case .ollama, .simulation: return 0.6
            case .talkNova: return 0.75
            case .custom: return 0.7
            }
        }

        switch task {
        case .coding:
            switch kind {
            case .anthropic: return 1.0
            case .openai: return 0.97
            case .google: return 0.90
            case .openrouter: return 0.86
            case .groq: return 0.70
            case .custom: return 0.72
            case .ollama: return 0.60
            case .talkNova: return 0.76
            case .simulation: return 0.75
            }
        case .reasoning:
            switch kind {
            case .anthropic: return 1.0
            case .openai: return 0.96
            case .google: return 0.92
            case .openrouter: return 0.85
            case .groq: return 0.78
            case .custom: return 0.70
            case .ollama: return 0.58
            case .talkNova: return 0.71
            case .simulation: return 0.70
            }
        case .writing:
            switch kind {
            case .openai: return 1.0
            case .anthropic: return 0.96
            case .google: return 0.92
            case .openrouter: return 0.86
            case .groq: return 0.75
            case .custom: return 0.70
            case .ollama: return 0.62
            case .talkNova: return 0.73
            case .simulation: return 0.72
            }
        case .fast:
            switch kind {
            case .groq: return 1.0
            case .talkNova: return 0.80
            case .simulation: return 0.98
            case .google: return 0.90
            case .openai: return 0.86
            case .anthropic: return 0.82
            case .openrouter: return 0.78
            case .custom: return 0.65
            case .ollama: return 0.58
            }
        case .vision:
            switch kind {
            case .google: return 1.0
            case .openai: return 0.95
            case .anthropic: return 0.92
            case .openrouter: return 0.85
            case .groq: return 0.70
            case .custom: return 0.60
            case .ollama: return 0.50
            case .talkNova: return 0.55
            case .simulation: return 0.40
            }
        case .unknown:
            return 0.7
        }
    }

    static func score(health: HealthSnapshot, failures: Int) -> Double {
        let base: Double
        switch health.state {
        case .healthy: base = 1.0
        case .unknown: base = 0.68
        case .degraded: base = 0.38
        case .down: base = 0.05
        }
        return max(0.05, base - min(0.3, Double(failures) * 0.08))
    }

    static func score(latency: Int?, provider: ProviderKind) -> Double {
        guard let latency else { return provider.isLocal ? 0.82 : 0.55 }
        if latency <= 250 { return 1.0 }
        if latency <= 600 { return 0.88 }
        if latency <= 1_200 { return 0.68 }
        if latency <= 2_500 { return 0.45 }
        return 0.20
    }

    static func score(cost model: ModelConfig) -> Double {
        if model.isFree { return 1.0 }
        let blended = model.blendedPrice
        if blended <= 0 { return 0.80 }
        return max(0.05, 1.0 - min(1.0, blended / 40.0))
    }

    static func score(contextWindow: Int, estimatedTokens: Int) -> Double {
        guard contextWindow > 0 else { return 0.3 }
        let headroom = Double(contextWindow - estimatedTokens) / Double(contextWindow)
        return min(1.0, max(0.05, headroom * 3.0))
    }

    static func fallbackLatency(_ kind: ProviderKind) -> Int {
        kind.isLocal ? 120 : 800
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
