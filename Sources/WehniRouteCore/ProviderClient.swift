import Foundation

public struct ProviderClientError: Error, Sendable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

/// How a discovered model is billed. Routing stays binary (free vs paid);
/// notes carry provider-specific truth like rate limits or data-training
/// consent so the UI can be honest about what "free" means.
public enum DiscoveryTier: String, Codable, Sendable, CaseIterable {
    case free
    case paid
    case unknown
}

public struct DiscoveredModel: Identifiable, Sendable, Equatable {
    public var id: String { modelID }
    public var modelID: String
    public var displayName: String
    public var contextWindow: Int?
    public var inputPerMillion: Double?
    public var outputPerMillion: Double?
    public var tier: DiscoveryTier
    public var note: String?

    public init(
        modelID: String,
        displayName: String = "",
        contextWindow: Int? = nil,
        inputPerMillion: Double? = nil,
        outputPerMillion: Double? = nil,
        tier: DiscoveryTier = .unknown,
        note: String? = nil
    ) {
        self.modelID = modelID
        self.displayName = displayName.isEmpty ? modelID : displayName
        self.contextWindow = contextWindow
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.tier = tier
        self.note = note
    }
}

public struct ProviderCall: Sendable {
    public var provider: ProviderConfig
    public var model: ModelConfig
    public var apiKey: String
    public var request: CanonicalRequest

    public init(provider: ProviderConfig, model: ModelConfig, apiKey: String, request: CanonicalRequest) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.request = request
    }
}

public enum ProviderCallOutcome: Sendable {
    case success(CanonicalResponse, latencyMS: Int)
    case httpError(status: Int, message: String, latencyMS: Int)
    case networkError(message: String, latencyMS: Int)

    public var latencyMS: Int {
        switch self {
        case .success(_, let latencyMS), .httpError(_, _, let latencyMS), .networkError(_, let latencyMS):
            return latencyMS
        }
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

public enum ProviderClient {
    public static func call(_ call: ProviderCall) async -> ProviderCallOutcome {
        if call.provider.kind == .simulation {
            try? await Task.sleep(nanoseconds: 260_000_000)
            let prompt = call.request.lastUserText()
            let text = prompt.isEmpty
                ? "Simulation route confirmed. Add a real provider to send live requests."
                : "Simulation route confirmed.\n\nEcho: \(prompt.prefix(600))"
            let response = CanonicalResponse(
                id: "sim_\(UUID().uuidString.prefix(8))",
                model: call.model.modelID,
                text: text,
                toolCalls: [],
                finishReason: "stop",
                usage: TokenUsage(
                    input: max(1, prompt.count / 4),
                    output: max(1, prompt.count / 8)
                )
            )
            return .success(response, latencyMS: 260)
        }

        let started = Date()
        do {
            let request = try makeRequest(for: call)
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(started) * 1_000)
            guard let http = response as? HTTPURLResponse else {
                return .networkError(message: "No HTTP response", latencyMS: latency)
            }
            let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
            guard (200..<300).contains(http.statusCode) else {
                return .httpError(
                    status: http.statusCode,
                    message: errorMessage(from: body, status: http.statusCode),
                    latencyMS: latency
                )
            }
            let canonical = call.provider.apiFormat == .anthropic
                ? AnthropicAdapter.parse(body)
                : OpenAIAdapter.parse(body)
            return .success(canonical, latencyMS: latency)
        } catch {
            let latency = Int(Date().timeIntervalSince(started) * 1_000)
            return .networkError(message: error.localizedDescription, latencyMS: latency)
        }
    }

    public static func listModels(
        provider: ProviderConfig,
        apiKey: String
    ) async -> Result<[String], ProviderClientError> {
        switch await discoverModels(provider: provider, apiKey: apiKey) {
        case .success(let models):
            return .success(models.map(\.modelID))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Tier-aware model discovery. Providers with rich catalogs (OpenRouter,
    /// Groq) contribute real pricing and context metadata; providers that only
    /// list IDs fall back to preset defaults. Ollama uses its native /api/tags.
    public static func discoverModels(
        provider: ProviderConfig,
        apiKey: String
    ) async -> Result<[DiscoveredModel], ProviderClientError> {
        if provider.kind == .simulation {
            return .success([DiscoveredModel(modelID: "sim-echo", displayName: "Simulated echo", tier: .free,
                                             note: "Offline simulation · no cost")])
        }

        if provider.kind == .ollama {
            return await discoverOllama(provider: provider)
        }

        let base = trimmedBase(provider.baseURL)
        if provider.apiFormat == .anthropic {
            let urlString = base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
            let result = await getJSON(urlString: urlString, headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ])
            switch result {
            case .success(let body):
                let parsed = parseOpenAIList(body, provider: provider, fallbackTier: .paid)
                if !parsed.isEmpty { return .success(parsed) }
                return await probeAnthropicModels(provider: provider, apiKey: apiKey)
            case .failure(let error) where error.message.contains("404"):
                return await probeAnthropicModels(provider: provider, apiKey: apiKey)
            case .failure(let error):
                return .failure(error)
            }
        }

        let urlString = base.hasSuffix("/models") ? base : "\(base)/models"
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        if provider.kind == .openrouter {
            headers["HTTP-Referer"] = "https://wehniroute.local"
            headers["X-Title"] = "WehniRoute"
        }
        let result = await getJSON(urlString: urlString, headers: headers)
        switch result {
        case .success(let body):
            return .success(parseCatalog(body, provider: provider))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Generic id-list parser for providers whose catalogs carry no pricing
    /// metadata; tier falls back to the preset's expectation.
    private static func parseOpenAIList(
        _ body: JSONValue,
        provider: ProviderConfig,
        fallbackTier: DiscoveryTier
    ) -> [DiscoveredModel] {
        let entries = body["data"]?.arrayValue ?? body["models"]?.arrayValue ?? []
        let models = entries.compactMap { entry -> DiscoveredModel? in
            guard let id = entry["id"]?.stringValue ?? entry["name"]?.stringValue, !id.isEmpty else {
                return nil
            }
            var model = DiscoveredModel(modelID: id, displayName: entry["name"]?.stringValue ?? "", tier: fallbackTier)
            model.contextWindow = provider.kind.defaultContextWindow
            if !provider.kind.isLocal {
                model.inputPerMillion = provider.kind.defaultInputPrice
                model.outputPerMillion = provider.kind.defaultOutputPrice
            }
            return model
        }
        return models.sorted { $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending }
    }

    private static func probeAnthropicModels(
        provider: ProviderConfig,
        apiKey: String
    ) async -> Result<[DiscoveredModel], ProviderClientError> {
        switch await probeAnthropic(provider: provider, apiKey: apiKey) {
        case .success(let ids):
            return .success(ids.map { id in
                DiscoveredModel(modelID: id, tier: .paid, note: "Discovered via probe; model list unavailable")
            })
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func parseCatalog(_ body: JSONValue, provider: ProviderConfig) -> [DiscoveredModel] {        let entries = body["data"]?.arrayValue ?? body["models"]?.arrayValue ?? []
        let models = entries.compactMap { entry -> DiscoveredModel? in
            guard let id = entry["id"]?.stringValue ?? entry["name"]?.stringValue, !id.isEmpty else {
                return nil
            }
            var model = DiscoveredModel(modelID: id, displayName: entry["name"]?.stringValue ?? "")

            switch provider.kind {
            case .openrouter:
                let pricing = entry["pricing"] ?? .object([:])
                let prompt = Double(pricing["prompt"]?.stringValue ?? "") ?? -1
                let completion = Double(pricing["completion"]?.stringValue ?? "") ?? -1
                if prompt >= 0 && completion >= 0 {
                    model.inputPerMillion = prompt * 1_000_000
                    model.outputPerMillion = completion * 1_000_000
                    model.tier = (prompt == 0 && completion == 0) ? .free : .paid
                }
                if id.hasSuffix(":free") { model.tier = .free }
                if let ctx = entry["context_length"]?.intValue { model.contextWindow = ctx }
                if let description = entry["description"]?.stringValue {
                    model.note = String(description.prefix(140))
                }

            case .groq:
                if let ctx = entry["context_window"]?.intValue { model.contextWindow = ctx }
                model.tier = .free
                model.note = "Groq free-tier rate limits apply"

            case .google, .cerebras, .nvidia:
                if let ctx = entry["context_window"]?.intValue ?? entry["context_length"]?.intValue {
                    model.contextWindow = ctx
                }
                model.tier = .free
                model.note = provider.kind == .google
                    ? "AI Studio free-tier rate limits apply"
                    : "Free credits/tier available on this provider"

            case .ollama, .lmstudio:
                model.tier = .free
                model.note = "Local model · no egress, no cost"

            case .mistral:
                model.tier = .paid
                model.note = "Free Experiment plan exists (data-training consent required)"

            case .talkNova:
                model.tier = .paid
                model.note = "Draws from your TalkNova plan allowance"

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
            }

            if model.contextWindow == nil {
                model.contextWindow = provider.kind.defaultContextWindow
            }
            if model.inputPerMillion == nil && provider.kind.defaultInputPrice != nil {
                model.inputPerMillion = provider.kind.defaultInputPrice
            }
            if model.outputPerMillion == nil && provider.kind.defaultOutputPrice != nil {
                model.outputPerMillion = provider.kind.defaultOutputPrice
            }
            return model
        }
        return models.sorted {
            if $0.tier != $1.tier { return $0.tier == .free && $1.tier != .free }
            return $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending
        }
    }

    /// Test-only surface for the catalog parser. Never call from app code.
    static func parseCatalogForTesting(_ body: JSONValue, provider: ProviderConfig) -> [DiscoveredModel] {
        parseCatalog(body, provider: provider)
    }

    private static func discoverOllama(provider: ProviderConfig) async -> Result<[DiscoveredModel], ProviderClientError> {
        // Native endpoint: richer than the OpenAI shim (families, sizes).
        let base = trimmedBase(provider.baseURL)
        let root = base.hasSuffix("/v1") ? String(base.dropLast(3)) : base
        let result = await getJSON(urlString: "\(root)/api/tags", headers: [:])
        switch result {
        case .success(let body):
            let entries = body["models"]?.arrayValue ?? []
            let models = entries.compactMap { entry -> DiscoveredModel? in
                guard let name = entry["name"]?.stringValue ?? entry["model"]?.stringValue, !name.isEmpty else {
                    return nil
                }
                var model = DiscoveredModel(modelID: name, displayName: name, tier: .free,
                                            note: "Local model · no egress, no cost")
                if let size = entry["details"]?["parameter_size"]?.stringValue {
                    model.displayName = "\(name) · \(size)"
                }
                return model
            }
            return .success(models.sorted { $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending })
        case .failure(let error):
            return .failure(error)
        }
    }

    private static func getJSON(urlString: String, headers: [String: String]) async -> Result<JSONValue, ProviderClientError> {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return .failure(ProviderClientError("Invalid models URL: \(urlString)"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(ProviderClientError("No HTTP response"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
                return .failure(ProviderClientError("HTTP \(http.statusCode): \(errorMessage(from: body, status: http.statusCode))"))
            }
            let body = try? JSONDecoder().decode(JSONValue.self, from: data)
            return .success(body ?? .object([:]))
        } catch {
            return .failure(ProviderClientError(error.localizedDescription))
        }
    }

    // MARK: - HTTP

    private static func makeRequest(for call: ProviderCall) throws -> URLRequest {
        let base = trimmedBase(call.provider.baseURL)
        let endpoint: String
        switch call.provider.apiFormat {
        case .anthropic:
            let root = base.hasSuffix("/v1") ? base : "\(base)/v1"
            endpoint = "\(root)/messages"
        case .openAI:
            endpoint = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
        }

        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw ProviderClientError("Invalid base URL: \(call.provider.baseURL)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WehniRoute/0.1 (macOS)", forHTTPHeaderField: "User-Agent")

        switch call.provider.apiFormat {
        case .anthropic:
            if !call.apiKey.isEmpty {
                request.setValue(call.apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = call.request.anthropicBody(model: call.model.modelID).jsonData
        case .openAI:
            if !call.apiKey.isEmpty {
                request.setValue("Bearer \(call.apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = call.request.openAIBody(model: call.model.modelID, stream: false).jsonData
        }
        return request
    }

    private static func getModelIDs(
        urlString: String,
        headers: [String: String]
    ) async -> Result<[String], ProviderClientError> {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return .failure(ProviderClientError("Invalid models URL: \(urlString)"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(ProviderClientError("No HTTP response"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
                return .failure(ProviderClientError("HTTP \(http.statusCode): \(errorMessage(from: body, status: http.statusCode))"))
            }
            let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
            return .success(modelIDs(from: body))
        } catch {
            return .failure(ProviderClientError(error.localizedDescription))
        }
    }

    private static func probeAnthropic(
        provider: ProviderConfig,
        apiKey: String
    ) async -> Result<[String], ProviderClientError> {
        let base = trimmedBase(provider.baseURL)
        let root = base.hasSuffix("/v1") ? base : "\(base)/v1"
        guard let url = URL(string: "\(root)/messages") else {
            return .failure(ProviderClientError("Invalid base URL"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = JSONValue.object([
            "model": .string(provider.kind.defaultModel),
            "max_tokens": .num(1),
            "messages": .array([
                .object(["role": .string("user"), "content": .string("ping")])
            ]),
        ]).jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(ProviderClientError("No HTTP response"))
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .object([:])
                return .failure(ProviderClientError("HTTP \(http.statusCode): \(errorMessage(from: body, status: http.statusCode))"))
            }
            return .success([provider.kind.defaultModel])
        } catch {
            return .failure(ProviderClientError(error.localizedDescription))
        }
    }

    private static func modelIDs(from body: JSONValue) -> [String] {
        if let data = body["data"]?.arrayValue {
            return data.compactMap { $0["id"]?.stringValue }
        }
        if let models = body["models"]?.arrayValue {
            return models.compactMap { $0["id"]?.stringValue ?? $0["name"]?.stringValue }
        }
        return []
    }

    private static func errorMessage(from body: JSONValue, status: Int) -> String {
        if let message = body["error"]?["message"]?.stringValue { return message }
        if let message = body["error"]?.stringValue { return message }
        if let message = body["message"]?.stringValue { return message }
        return "HTTP \(status)"
    }

    private static func trimmedBase(_ value: String) -> String {
        var base = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}
