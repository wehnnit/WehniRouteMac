import Foundation

public struct ProviderClientError: Error, Sendable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
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
        if provider.kind == .simulation {
            return .success(["sim-echo"])
        }

        let base = trimmedBase(provider.baseURL)
        if provider.apiFormat == .anthropic {
            let urlString = base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
            let result = await getModelIDs(
                urlString: urlString,
                headers: [
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01",
                ]
            )
            switch result {
            case .success(let ids) where !ids.isEmpty:
                return .success(ids)
            case .success:
                return await probeAnthropic(provider: provider, apiKey: apiKey)
            case .failure(let error) where error.message.contains("404"):
                return await probeAnthropic(provider: provider, apiKey: apiKey)
            case .failure(let error):
                return .failure(error)
            }
        }

        let urlString = base.hasSuffix("/models") ? base : "\(base)/models"
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        return await getModelIDs(urlString: urlString, headers: headers)
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
