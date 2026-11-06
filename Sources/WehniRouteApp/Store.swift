import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WehniRouteCore

enum SetupError: LocalizedError {
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "Choose a port between 1024 and 65535."
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case providers
    case models
    case routing
    case harnesses
    case traces
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .providers: return "Providers"
        case .models: return "Models"
        case .routing: return "Routing"
        case .harnesses: return "Harnesses"
        case .traces: return "Traces"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .providers: return "point.3.connected.trianglepath.dotted"
        case .models: return "cpu.fill"
        case .routing: return "arrow.triangle.branch"
        case .harnesses: return "terminal.fill"
        case .traces: return "waveform.path.ecg"
        case .settings: return "gearshape.fill"
        }
    }
}

enum GatewayStatus: Equatable {
    case stopped
    case running(port: Int)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .running: return "Gateway online"
        case .failed: return "Gateway error"
        }
    }
}

enum ToastKind {
    case info
    case success
    case error
}

struct Toast: Identifiable, Equatable {
    let id: UUID
    var message: String
    var kind: ToastKind

    init(id: UUID = UUID(), message: String, kind: ToastKind = .info) {
        self.id = id
        self.message = message
        self.kind = kind
    }
}

private enum GatewayEndpoint {
    case openAI
    case anthropic
}

@MainActor
final class AppStore: ObservableObject {
    @Published var config: AppConfig
    @Published var traces: [Trace]
    @Published var health: [String: HealthSnapshot]
    @Published var section: AppSection = .overview
    @Published var gatewayStatus: GatewayStatus = .stopped
    @Published var toastMessage: Toast?
    @Published var showAddProvider = false
    @Published var showAddModel = false
    @Published var selectedTraceID: UUID?
    @Published var search = ""
    @Published var previewTask: TaskType = .coding
    @Published var testingProviderID: String?
    @Published var gatewayAPIKey: String
    @Published var revealGatewayKey = false
    @Published var armedProviderID: String?
    @Published var armedFailure: SimulatedFailure?
    @Published var needsSetup = false

    private let server = GatewayServer()
    private let interceptor = TalkNovaInterceptor()
    private let startedAt = Date()

    @Published private(set) var interceptorPort: Int?

    static var homeDirectory: URL {
        SupportDirectory.url
    }

    var supportDirectory: URL { Self.homeDirectory }

    private var configURL: URL { SupportDirectory.configURL }
    private var tracesURL: URL { SupportDirectory.tracesURL }
    private var gatewayKeyURL: URL { SupportDirectory.gatewayKeyURL }

    init() {
        let hasSupportFolder = SupportDirectory.exists
        config = Self.load(AppConfig.self, from: SupportDirectory.configURL) ?? AppConfig()
        traces = Self.load([Trace].self, from: SupportDirectory.tracesURL) ?? []
        health = [:]

        if let storedKey = Self.loadGatewayKey(from: SupportDirectory.gatewayKeyURL) {
            gatewayAPIKey = storedKey
        } else {
            gatewayAPIKey = Self.makeGatewayKey()
        }

        needsSetup = !hasSupportFolder
        guard !needsSetup else { return }

        var migrated = config
        if migrated.schemaVersion < AppConfig.latestSchemaVersion {
            migrated.schemaVersion = AppConfig.latestSchemaVersion
            config = migrated
            saveConfig()
        }

        if config.isFirstRun && config.providers.isEmpty {
            config.isFirstRun = false
            saveConfig()
        }
        startGateway()
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func saveConfig() {
        do {
            try persistConfig()
        } catch {
            showToast("Could not save config: \(error.localizedDescription)", kind: .error)
        }
    }

    private func persistConfig() throws {
        try SupportDirectory.ensureExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)
    }

    func completeSetup(port: Int, requireAPIKey: Bool, includeSimulation: Bool) throws {
        guard (1_024...65_535).contains(port) else {
            throw SetupError.invalidPort
        }

        try SupportDirectory.ensureExists()
        config.schemaVersion = AppConfig.latestSchemaVersion
        config.gatewayPort = port
        config.requireAPIKey = requireAPIKey
        config.isFirstRun = false

        if includeSimulation && config.provider(id: "simulation") == nil {
            let simulation = ProviderConfig(kind: .simulation)
            config.providers.append(simulation)
            config.addDefaultModel(for: simulation)
        }

        try persistConfig()
        saveTraces()
        if gatewayAPIKey.isEmpty {
            gatewayAPIKey = Self.makeGatewayKey()
        }
        Self.writeGatewayKey(gatewayAPIKey, to: gatewayKeyURL)

        needsSetup = false
        startGateway()
    }

    func saveTraces() {
        do {
            let encoder = JSONEncoder()
            try encoder.encode(traces).write(to: tracesURL, options: .atomic)
        } catch {
            // Trace persistence is best-effort; routing must not fail because of it.
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: {
                self.config[keyPath: keyPath] = $0
                self.saveConfig()
            }
        )
    }

    // MARK: - Gateway lifecycle

    func startGateway() {
        do {
            try server.start(port: UInt16(config.gatewayPort)) { [weak self] request in
                guard let self else {
                    return .error(503, message: "App is shutting down")
                }
                return await self.handle(request)
            }
            gatewayStatus = .running(port: config.gatewayPort)
            startInterceptor()
        } catch {
            gatewayStatus = .failed(error.localizedDescription)
            showToast(error.localizedDescription, kind: .error)
        }
    }

    /// The TalkNova interception proxy only matters when a TalkNova launch pads
    /// runs; failures are silent here and surface at launch time.
    private func startInterceptor() {
        interceptor.update(gatewayPort: config.gatewayPort, gatewayKey: gatewayAPIKey)
        guard !interceptor.isRunning else {
            interceptorPort = interceptor.port
            return
        }
        do {
            try interceptor.start()
            interceptorPort = interceptor.port
        } catch {
            interceptorPort = nil
        }
    }

    func stopGateway() {
        server.stop()
        interceptor.stop()
        interceptorPort = nil
        gatewayStatus = .stopped
    }

    func restartGateway() {
        server.stop()
        startGateway()
    }

    func updatePort(_ port: Int) {
        guard (1_024...65_535).contains(port) else {
            showToast("Choose a port between 1024 and 65535", kind: .error)
            return
        }
        config.gatewayPort = port
        saveConfig()
        restartGateway()
    }

    var gatewayURL: String {
        "http://127.0.0.1:\(config.gatewayPort)/v1"
    }

    func copyGatewayURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gatewayURL, forType: .string)
        showToast("Gateway URL copied", kind: .success)
    }

    func copyGatewayKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gatewayAPIKey, forType: .string)
        showToast("API key copied", kind: .success)
    }

    func regenerateGatewayKey() {
        gatewayAPIKey = Self.makeGatewayKey()
        Self.writeGatewayKey(gatewayAPIKey, to: gatewayKeyURL)
        interceptor.update(gatewayPort: config.gatewayPort, gatewayKey: gatewayAPIKey)
        showToast("Gateway key rotated", kind: .success)
    }

    // MARK: - Providers

    func provider(id: String) -> ProviderConfig? {
        config.provider(id: id)
    }

    func models(for providerID: String) -> [ModelConfig] {
        config.models(for: providerID)
    }

    @discardableResult
    func addProvider(
        kind: ProviderKind,
        apiKey: String,
        baseURL: String? = nil,
        name: String? = nil
    ) -> ProviderConfig? {
        let id: String
        if kind == .custom {
            id = "custom-\(UUID().uuidString.prefix(6).lowercased())"
        } else {
            id = kind.rawValue
        }

        if let existing = config.provider(id: id) {
            showToast("\(existing.name) is already connected", kind: .info)
            return existing
        }

        var provider = ProviderConfig(kind: kind, id: id, name: name)
        if kind == .custom {
            guard let baseURL, !baseURL.isEmpty else {
                showToast("A custom provider needs a base URL", kind: .error)
                return nil
            }
            provider.baseURL = baseURL
        } else if let baseURL, !baseURL.isEmpty {
            provider.baseURL = baseURL
        }

        if !apiKey.isEmpty {
            Keychain.set(apiKey, for: provider.keychainAccount)
        }

        config.providers.append(provider)
        config.addDefaultModel(for: provider)
        saveConfig()
        showToast("\(provider.name) added", kind: .success)
        return provider
    }

    func removeProvider(_ provider: ProviderConfig) {
        config.providers.removeAll { $0.id == provider.id }
        config.models.removeAll { $0.providerID == provider.id }
        health.removeValue(forKey: provider.id)
        Keychain.delete(provider.keychainAccount)
        if armedProviderID == provider.id {
            armedProviderID = nil
            armedFailure = nil
        }
        saveConfig()
        showToast("\(provider.name) removed", kind: .info)
    }

    func setProviderEnabled(_ providerID: String, enabled: Bool) {
        guard let index = config.providers.firstIndex(where: { $0.id == providerID }) else { return }
        config.providers[index].enabled = enabled
        saveConfig()
    }

    func updateProvider(_ provider: ProviderConfig) {
        guard let index = config.providers.firstIndex(where: { $0.id == provider.id }) else { return }
        config.providers[index] = provider
        saveConfig()
    }

    func testProvider(_ provider: ProviderConfig) async {
        let key = await Self.readProviderKey(provider)
        if provider.kind.requiresKey && key.isEmpty {
            showToast("Add an API key for \(provider.name) first", kind: .error)
            return
        }
        testingProviderID = provider.id
        let result = await ProviderClient.listModels(provider: provider, apiKey: key)
        testingProviderID = nil
        switch result {
        case .success(let ids):
            recordHealth(providerID: provider.id, success: true, latency: nil, status: 200, message: nil)
            showToast("\(provider.name) verified · \(ids.count) models", kind: .success)
        case .failure(let error):
            recordHealth(providerID: provider.id, success: false, latency: nil, status: nil, message: error.message)
            showToast("\(provider.name): \(error.message)", kind: .error)
        }
    }

    func armSimulation(_ mode: SimulatedFailure, on providerID: String) {
        armedProviderID = providerID
        armedFailure = mode
        if let index = config.providers.firstIndex(where: { $0.id == providerID }) {
            config.providers[index].simulatedFailure = mode
            saveConfig()
        }
        showToast("Next \(mode.label.lowercased()) will hit \(provider(id: providerID)?.name ?? "provider")", kind: .info)
    }

    func clearSimulation() {
        if let providerID = armedProviderID, let index = config.providers.firstIndex(where: { $0.id == providerID }) {
            config.providers[index].simulatedFailure = nil
            saveConfig()
        }
        armedProviderID = nil
        armedFailure = nil
    }

    // MARK: - Models

    func addModel(
        providerID: String,
        modelID: String,
        displayName: String,
        contextWindow: Int,
        inputPrice: Double?,
        outputPrice: Double?,
        isFree: Bool
    ) {
        let trimmedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            showToast("Model ID is required", kind: .error)
            return
        }
        guard !config.models.contains(where: { $0.providerID == providerID && $0.modelID == trimmedID }) else {
            showToast("That model is already configured", kind: .info)
            return
        }
        config.models.append(
            ModelConfig(
                providerID: providerID,
                modelID: trimmedID,
                displayName: displayName,
                contextWindow: contextWindow,
                inputPerMillion: inputPrice,
                outputPerMillion: outputPrice,
                isFree: isFree
            )
        )
        saveConfig()
        showToast("Model added", kind: .success)
    }

    func removeModel(_ model: ModelConfig) {
        config.models.removeAll { $0.id == model.id }
        saveConfig()
    }

    func setModelEnabled(_ modelID: UUID, enabled: Bool) {
        guard let index = config.models.firstIndex(where: { $0.id == modelID }) else { return }
        config.models[index].enabled = enabled
        saveConfig()
    }

    // MARK: - Routing

    func applyStrategy(_ strategy: Strategy) {
        config.routing.strategy = strategy
        config.routing.weights = .preset(for: strategy)
        saveConfig()
    }

    func resetHealth() {
        health = [:]
        showToast("Circuit state cleared", kind: .success)
    }

    var rankedCandidates: [Candidate] {
        Router.rank(
            config: config,
            health: health,
            estimatedInputTokens: 900,
            task: previewTask
        ).candidates
    }

    var rejectedCandidates: [Rejection] {
        Router.rank(
            config: config,
            health: health,
            estimatedInputTokens: 900,
            task: previewTask
        ).rejected
    }

    // MARK: - Traces

    func record(_ trace: Trace) {
        traces.insert(trace, at: 0)
        if traces.count > 500 {
            traces.removeLast(traces.count - 500)
        }
        saveTraces()
    }

    func clearTraces() {
        traces = []
        selectedTraceID = nil
        saveTraces()
        showToast("Decision records cleared", kind: .info)
    }

    var selectedTrace: Trace? {
        traces.first { $0.id == selectedTraceID }
    }

    // MARK: - Settings

    func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "wehni-route-config.json"
        panel.title = "Export WehniRoute configuration"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(config).write(to: url)
            showToast("Config exported", kind: .success)
        } catch {
            showToast("Export failed: \(error.localizedDescription)", kind: .error)
        }
    }

    func revealHome() {
        NSWorkspace.shared.activateFileViewerSelecting([Self.homeDirectory])
    }

    func showToast(_ message: String, kind: ToastKind = .info) {
        let next = Toast(message: message, kind: kind)
        withAnimation(.snappy(duration: 0.2)) {
            toastMessage = next
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, self.toastMessage?.id == next.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                self.toastMessage = nil
            }
        }
    }

    // MARK: - HTTP gateway

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard config.requireAPIKey else { return true }
        if request.bearerToken == gatewayAPIKey { return true }
        if request.headers["x-api-key"] == gatewayAPIKey { return true }
        return false
    }

    private func handle(_ request: HTTPRequest) async -> HTTPResponse {
        var path = request.path.split(separator: "?").first.map(String.init) ?? request.path

        // Some OpenAI-compatible clients join a bare base URL with
        // /chat/completions, and misconfigured ones can double-prefix /v1.
        // Normalize both onto the canonical routes so every harness connects.
        switch path {
        case "/chat/completions", "/v1/v1/chat/completions":
            path = "/v1/chat/completions"
        case "/messages", "/v1/v1/messages":
            path = "/v1/messages"
        case "/models", "/v1/v1/models":
            path = "/v1/models"
        default:
            break
        }

        switch (request.method, path) {
        case ("GET", "/healthz"):
            return .json(200, healthPayload())

        case ("GET", "/v1/models"):
            guard authorized(request) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            return .json(200, modelsPayload())

        case ("POST", "/v1/chat/completions"):
            guard authorized(request) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            guard let body = request.json else {
                return .error(400, message: "Invalid JSON body")
            }
            let canonical = CanonicalRequest.fromOpenAI(body)
            let requested = body["model"]?.stringValue ?? "auto"
            return await execute(canonical, endpoint: .openAI, requestedModel: requested)

        case ("POST", "/v1/messages"):
            guard authorized(request) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            guard let body = request.json else {
                return .error(400, message: "Invalid JSON body")
            }
            let canonical = CanonicalRequest.fromAnthropic(body)
            let requested = body["model"]?.stringValue ?? "auto"
            return await execute(canonical, endpoint: .anthropic, requestedModel: requested)

        case ("GET", "/"):
            return .json(200, .object([
                "service": .string("WehniRoute Native"),
                "endpoints": .array([.string("/v1/chat/completions"), .string("/v1/messages"), .string("/v1/models"), .string("/healthz")]),
            ]))

        default:
            return .error(404, message: "Unknown route \(request.method) \(path)")
        }
    }

    private func healthPayload() -> JSONValue {
        .object([
            "ok": .bool(true),
            "service": .string("WehniRoute Native"),
            "version": .string(AppVersion.short),
            "strategy": .string(config.routing.strategy.rawValue),
            "connectedProviders": .num(config.enabledProviders.count),
            "modelCount": .num(config.enabledModels.count),
            "port": .num(config.gatewayPort),
            "bind": .string("127.0.0.1"),
            "uptimeSec": .num(Int(Date().timeIntervalSince(startedAt))),
            "apiKeyRequired": .bool(config.requireAPIKey),
        ])
    }

    private func modelsPayload() -> JSONValue {
        // Clients only ever see the router model. Every harness model picker
        // therefore shows WehniRoute Auto instead of upstream model IDs; the
        // concrete catalog stays in Models and the trace log.
        return .object([
            "object": .string("list"),
            "data": .array([
                .object([
                    "id": .string("auto"),
                    "object": .string("model"),
                    "name": .string("WehniRoute Auto"),
                    "display_name": .string("WehniRoute Auto"),
                    "owned_by": .string("wehni-route"),
                    "wehni": .object([
                        "type": .string("router-model"),
                        "displayName": .string("WehniRoute Auto"),
                    ]),
                ])
            ]),
        ])
    }

    private func execute(
        _ request: CanonicalRequest,
        endpoint: GatewayEndpoint,
        requestedModel: String
    ) async -> HTTPResponse {
        let started = Date()
        let task = Router.classify(messages: request.messages, tools: request.tools)
        let estimated = Router.estimateTokens(messages: request.messages, tools: request.tools)
        let ranked = Router.rank(
            config: config,
            health: health,
            estimatedInputTokens: estimated,
            task: task,
            requestedModel: requestedModel
        ).candidates

        var trace = Trace(
            requestID: "req_\(UUID().uuidString.prefix(10).lowercased())",
            endpoint: endpoint == .openAI ? "/v1/chat/completions" : "/v1/messages",
            requestedModel: requestedModel,
            taskType: task,
            strategy: config.routing.strategy,
            status: 0,
            latencyMS: 0,
            requestPreview: request.preview()
        )

        guard !ranked.isEmpty else {
            let rejected = Router.rank(
                config: config,
                health: health,
                estimatedInputTokens: estimated,
                task: task,
                requestedModel: requestedModel
            ).rejected
            let reason = rejected.first?.reason ?? "No connected providers"
            trace.status = 503
            trace.latencyMS = Int(Date().timeIntervalSince(started) * 1_000)
            trace.errorSummary = "No eligible route. \(reason)"
            record(trace)
            return .error(503, message: "No eligible route: \(reason). Connect a provider or loosen the routing policy.")
        }

        let limit = min(max(1, config.routing.fallbackAttempts), ranked.count)
        var fallbackUsed = false
        var lastFailure = "No provider answered"

        for candidate in ranked.prefix(limit) {
            guard let provider = config.provider(id: candidate.providerID),
                  let model = config.models.first(where: {
                      $0.providerID == candidate.providerID && $0.modelID == candidate.modelID
                  })
            else { continue }

            if let simulated = provider.simulatedFailure {
                let status = simulated == .rateLimit ? 429 : 503
                let detail = "Simulated \(simulated.label)"
                trace.attempts.append(
                    TraceAttempt(
                        providerID: provider.id,
                        providerName: provider.name,
                        model: candidate.modelID,
                        outcome: .simulated,
                        status: status,
                        latencyMS: 0,
                        detail: detail
                    )
                )
                recordHealth(providerID: provider.id, success: false, latency: 0, status: status, message: detail)
                clearSimulation()
                fallbackUsed = true
                lastFailure = detail
                continue
            }

            let key = await Self.readProviderKey(provider)
            if provider.kind.requiresKey && key.isEmpty {
                trace.attempts.append(
                    TraceAttempt(
                        providerID: provider.id,
                        providerName: provider.name,
                        model: candidate.modelID,
                        outcome: .skipped,
                        latencyMS: 0,
                        detail: "No API key"
                    )
                )
                continue
            }

            let outcome = await ProviderClient.call(
                ProviderCall(provider: provider, model: model, apiKey: key, request: request)
            )

            switch outcome {
            case .success(let response, let latency):
                recordHealth(providerID: provider.id, success: true, latency: latency, status: 200, message: nil)
                trace.attempts.append(
                    TraceAttempt(
                        providerID: provider.id,
                        providerName: provider.name,
                        model: candidate.modelID,
                        outcome: .success,
                        status: 200,
                        latencyMS: latency
                    )
                )
                trace.selectedProviderID = provider.id
                trace.selectedProviderName = provider.name
                trace.selectedModel = candidate.modelID
                trace.status = 200
                trace.latencyMS = Int(Date().timeIntervalSince(started) * 1_000)
                trace.inputTokens = response.usage.input
                trace.outputTokens = response.usage.output
                trace.costUSD = cost(for: model, usage: response.usage)
                trace.fallbackUsed = fallbackUsed
                trace.responsePreview = String(response.text.prefix(240))
                record(trace)

                // Present the gateway, not the upstream, to clients: every
                // harness UI shows the route as WehniRoute Auto. The trace log
                // keeps the concrete provider and model that answered.
                var branded = response
                branded.model = "auto"

                if request.stream {
                    let frames = endpoint == .openAI
                        ? branded.openAIStreamFrames()
                        : branded.anthropicStreamFrames()
                    return .stream(frames, contentType: "text/event-stream; charset=utf-8")
                }
                return .json(200, endpoint == .openAI ? branded.openAIBody() : branded.anthropicBody())

            case .httpError(let status, let message, let latency):
                recordHealth(providerID: provider.id, success: false, latency: latency, status: status, message: message)
                trace.attempts.append(
                    TraceAttempt(
                        providerID: provider.id,
                        providerName: provider.name,
                        model: candidate.modelID,
                        outcome: .httpError,
                        status: status,
                        latencyMS: latency,
                        detail: message
                    )
                )
                fallbackUsed = true
                lastFailure = "\(provider.name): \(message)"

            case .networkError(let message, let latency):
                recordHealth(providerID: provider.id, success: false, latency: latency, status: nil, message: message)
                trace.attempts.append(
                    TraceAttempt(
                        providerID: provider.id,
                        providerName: provider.name,
                        model: candidate.modelID,
                        outcome: .networkError,
                        latencyMS: latency,
                        detail: message
                    )
                )
                fallbackUsed = true
                lastFailure = "\(provider.name): \(message)"
            }
        }

        trace.status = 502
        trace.fallbackUsed = fallbackUsed
        trace.latencyMS = Int(Date().timeIntervalSince(started) * 1_000)
        trace.errorSummary = lastFailure
        record(trace)
        return .error(502, message: "All providers failed. \(lastFailure)")
    }

    private func recordHealth(
        providerID: String,
        success: Bool,
        latency: Int?,
        status: Int?,
        message: String?
    ) {
        var snapshot = health[providerID] ?? HealthSnapshot()
        snapshot.lastChecked = Date()

        if success {
            snapshot.state = .healthy
            snapshot.consecutiveFailures = 0
            snapshot.cooldownUntil = nil
            snapshot.lastError = nil
            if let latency {
                if let average = snapshot.avgLatencyMS {
                    snapshot.avgLatencyMS = Int((Double(average) * 0.7) + (Double(latency) * 0.3))
                } else {
                    snapshot.avgLatencyMS = latency
                }
            }
        } else {
            snapshot.consecutiveFailures += 1
            snapshot.state = snapshot.consecutiveFailures >= 3 ? .down : .degraded
            snapshot.lastError = message
            if snapshot.consecutiveFailures >= 3 {
                snapshot.cooldownUntil = Date().addingTimeInterval(45)
            }
        }
        health[providerID] = snapshot
    }

    private func cost(for model: ModelConfig, usage: TokenUsage) -> Double {
        if model.isFree { return 0 }
        let input = (model.inputPerMillion ?? 0) / 1_000_000 * Double(usage.input)
        let output = (model.outputPerMillion ?? 0) / 1_000_000 * Double(usage.output)
        return input + output
    }

    // MARK: - Derived stats

    var successRate: Double? {
        guard !traces.isEmpty else { return nil }
        return Double(traces.filter(\.isSuccess).count) / Double(traces.count)
    }

    var averageLatencyMS: Int? {
        let values = traces.map(\.latencyMS).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var totalCost: Double {
        traces.reduce(0) { $0 + $1.costUSD }
    }

    var totalTokens: Int {
        traces.reduce(0) { $0 + $1.totalTokens }
    }

    var fallbackRate: Double? {
        guard !traces.isEmpty else { return nil }
        return Double(traces.filter(\.fallbackUsed).count) / Double(traces.count)
    }

    var hourRequestCount: Int {
        let cutoff = Date().addingTimeInterval(-3_600)
        return traces.filter { $0.createdAt > cutoff }.count
    }

    var providerHealthList: [(ProviderConfig, HealthSnapshot)] {
        config.providers.map { ($0, health[$0.id] ?? HealthSnapshot()) }
    }

    func sparklineValues() -> [Double] {
        traces.prefix(24).reversed().map { Double($0.latencyMS) }
    }

    private static func makeGatewayKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 18)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return "wrk_" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadGatewayKey(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            return nil
        }
        return key
    }

    private static func writeGatewayKey(_ key: String, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(key.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // The in-memory key still gates the loopback gateway for this session.
        }
    }

    private static func readProviderKey(_ provider: ProviderConfig) async -> String {
        await Task.detached(priority: .userInitiated) {
            Keychain.get(provider.keychainAccount) ?? ""
        }.value
    }
}
