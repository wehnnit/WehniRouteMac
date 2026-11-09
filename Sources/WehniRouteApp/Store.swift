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

private enum GatewayEndpoint: Sendable {
    case openAI
    case anthropic
}

@MainActor
final class AppStore: ObservableObject {
    @Published var config: AppConfig
    @Published var health: [String: HealthSnapshot]
    @Published var section: AppSection = .overview
    @Published var gatewayStatus: GatewayStatus = .stopped
    @Published var toastMessage: Toast?
    @Published var showAddProvider = false
    @Published var showAddModel = false
    /// Incremented by ⌘F so the Models tab can focus its search field even
    /// when the tab was not visible yet.
    @Published private(set) var modelSearchToken = 0
    /// Set when "Add <query> as a model" opens the add sheet, so the model ID
    /// arrives prefilled. Cleared when the sheet goes away.
    @Published var pendingModelID: String?
    @Published var previewTask: TaskType = .coding
    @Published var testingProviderID: String?
    @Published var gatewayAPIKey: String
    @Published var revealGatewayKey = false
    @Published var armedProviderID: String?
    @Published var armedFailure: SimulatedFailure?
    @Published var needsSetup = false

    private let server = GatewayServer()
    private let startedAt = Date()
    let presence = DiscordPresenceManager()
    /// Trace history and its search/filter state live in their own observable
    /// object so gateway traffic only invalidates the views that show traces.
    let traceStore = TraceStore()

    private let configQueue = DispatchQueue(label: "com.wehnnit.WehniRoute.config-writes", qos: .utility)
    private var pendingConfigWrite: DispatchWorkItem?

    static var homeDirectory: URL {
        SupportDirectory.url
    }

    var supportDirectory: URL { Self.homeDirectory }

    private var gatewayKeyURL: URL { SupportDirectory.gatewayKeyURL }

    init() {
        let hasSupportFolder = SupportDirectory.exists
        config = Self.load(AppConfig.self, from: SupportDirectory.configURL) ?? AppConfig()
        health = [:]

        if let storedKey = Self.loadGatewayKey(from: SupportDirectory.gatewayKeyURL) {
            gatewayAPIKey = storedKey
        } else {
            gatewayAPIKey = Self.makeGatewayKey()
        }

        // Flush the coalesced config/trace writes when the app quits.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushConfig()
                self?.traceStore.flushNow()
            }
        }

        needsSetup = !hasSupportFolder
        guard !needsSetup else { return }

        var migrated = config
        if migrated.schemaVersion < AppConfig.latestSchemaVersion {
            migrated.schemaVersion = AppConfig.latestSchemaVersion
            config = migrated
            try? persistConfig()
        }

        if config.isFirstRun && config.providers.isEmpty {
            config.isFirstRun = false
            try? persistConfig()
        }
        startGateway()
        if ProcessInfo.processInfo.environment["WEHNIROUTE_SECTION_PROBE"] == "1" {
            runSectionProbe()
        }
    }

    // MARK: - Persistence

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Debounced config write: a burst of edits produces one encode + atomic
    /// write on a utility queue instead of one per binding change.
    func saveConfig() {
        let snapshot = config
        pendingConfigWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do {
                try Self.writeConfig(snapshot)
            } catch {
                Task { @MainActor [weak self] in
                    self?.showToast("Could not save config: \(error.localizedDescription)", kind: .error)
                }
            }
        }
        pendingConfigWrite = work
        configQueue.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Writes any pending config immediately (quit / setup paths). Runs on the
    /// same serial queue so it cannot race an in-flight debounced write.
    func flushConfig() {
        pendingConfigWrite?.cancel()
        pendingConfigWrite = nil
        let snapshot = config
        configQueue.sync {
            try? Self.writeConfig(snapshot)
        }
    }

    private func persistConfig() throws {
        try Self.writeConfig(config)
    }

    private static func writeConfig(_ config: AppConfig) throws {
        try SupportDirectory.ensureExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: SupportDirectory.configURL, options: .atomic)
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
        traceStore.flushNow()
        if gatewayAPIKey.isEmpty {
            gatewayAPIKey = Self.makeGatewayKey()
        }
        Self.writeGatewayKey(gatewayAPIKey, to: gatewayKeyURL)

        needsSetup = false
        startGateway()
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
            startPresence()
        } catch {
            gatewayStatus = .failed(error.localizedDescription)
            showToast(error.localizedDescription, kind: .error)
        }
    }

    func stopGateway() {
        server.stop()
        gatewayStatus = .stopped
        presence.clearActivity()
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
        clearSimulationState(for: armedProviderID)
        armedProviderID = nil
        armedFailure = nil
    }

    /// Clears a provider's armed simulation without touching presence/toasts so
    /// the request pipeline can call it from its single main-actor publish hop.
    private func clearSimulationState(for providerID: String?) {
        guard let providerID,
              let index = config.providers.firstIndex(where: { $0.id == providerID })
        else { return }
        config.providers[index].simulatedFailure = nil
        saveConfig()
    }

    // MARK: - Models

    /// ⌘F: switch to Models and focus its search field.
    func requestModelSearch() {
        section = .models
        modelSearchToken += 1
    }

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

    /// Imports a user-selected set of discovered models into the catalog.
    func importDiscovered(providerID: String, models: [DiscoveredModel]) {
        guard config.provider(id: providerID) != nil else { return }
        let existing = Set(config.models(for: providerID).map(\.modelID))
        var added = 0
        for model in models where !existing.contains(model.modelID) {
            config.models.append(
                ModelConfig(
                    providerID: providerID,
                    modelID: model.modelID,
                    displayName: model.displayName,
                    contextWindow: model.contextWindow ?? 128_000,
                    inputPerMillion: model.inputPerMillion,
                    outputPerMillion: model.outputPerMillion,
                    isFree: model.tier == .free,
                    tierNote: model.note
                )
            )
            added += 1
        }
        saveConfig()
        showToast(added > 0 ? "Added \(added) model\(added == 1 ? "" : "s") to the catalog" : "Those models are already in the catalog", kind: .success)
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

    /// Bulk enable/disable for the whole catalog. One mutation pass and a
    /// single config write, because every save rewrites the config file.
    func setAllModelsEnabled(_ enabled: Bool) {
        let changed = config.models.filter { $0.enabled != enabled }.count
        guard changed > 0 else {
            showToast(enabled ? "All models are already enabled" : "All models are already disabled", kind: .info)
            return
        }
        for index in config.models.indices {
            config.models[index].enabled = enabled
        }
        saveConfig()
        let noun = changed == 1 ? "model" : "models"
        showToast(enabled ? "Enabled \(changed) \(noun)" : "Disabled \(changed) \(noun)", kind: enabled ? .success : .info)
    }

    /// The harness currently attributed to live traffic (launch registration
    /// or header fingerprinting). Expires after 15 idle minutes.
    @Published private(set) var activeHarness: String?
    private var activeHarnessAt = Date()
    private let harnessIdleLimit: TimeInterval = 15 * 60

    /// Local model sources discovered by the last scan.
    @Published private(set) var detectedSources: [LocalSourceCandidate] = []
    @Published private(set) var scanningSources = false

    /// Which tier of models may be routed. Drives both the Providers screen
    /// filter and the router gate.
    func setTierMode(_ mode: TierMode) {
        config.routing.tierMode = mode
        saveConfig()
    }

    var tierMode: TierMode { config.routing.tierMode }

    /// True when the provider contributes models to the active tier (or has
    /// none configured yet, so it stays visible and manageable).
    func providerMatchesTier(_ provider: ProviderConfig) -> Bool {
        if tierMode == .both { return true }
        let wantFree = tierMode == .freeOnly
        let models = models(for: provider.id).filter(\.enabled)
        if models.isEmpty { return true }
        return models.contains { $0.isFree == wantFree }
    }

    func setActiveHarness(_ name: String) {
        activeHarness = name
        activeHarnessAt = Date()
    }

    /// Returns the still-valid harness attribution (nil after 15 idle minutes).
    private func expireActiveHarness() -> (String?, Date) {
        if let harness = activeHarness,
           Date().timeIntervalSince(activeHarnessAt) > harnessIdleLimit {
            activeHarness = nil
            return (nil, Date())
        }
        return (activeHarness, activeHarness != nil ? activeHarnessAt : startedAt)
    }

    // MARK: - Routing

    func applyStrategy(_ strategy: Strategy) {
        config.routing.strategy = strategy
        config.routing.weights = .preset(for: strategy)
        saveConfig()
    }

    // MARK: - Local model sources

    func scanLocalSources() async {
        guard !scanningSources else { return }
        scanningSources = true
        var found = await LocalSourceScanner.scan()
        // State-aware, not aspirational: sources that are already connected
        // providers surface a refresh affordance, never an add button.
        for index in found.indices {
            let candidate = found[index]
            if let providerID = sourceProviderID(for: candidate) {
                found[index].connected = true
                found[index].providerID = providerID
                let count = config.models(for: providerID).count
                found[index].detail = "Connected · \(count) model\(count == 1 ? "" : "s") in catalog"
            }
        }
        detectedSources = found
        scanningSources = false
    }

    private func normalizedURL(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// Maps a detected source onto an existing provider, when one exists.
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

    /// Adopts a detected local source as a provider and imports its catalog.
    /// Idempotent: adopting an already-connected source refreshes its catalog.
    @discardableResult
    func adoptLocalSource(_ candidate: LocalSourceCandidate) async -> Bool {
        let existingID = sourceProviderID(for: candidate)

        guard let provider = await connectSource(candidate, existingID: existingID) else {
            return false
        }

        let key = await Self.readProviderKey(provider)
        let result = await ProviderClient.discoverModels(provider: provider, apiKey: key)
        switch result {
        case .success(let models) where !models.isEmpty:
            let before = config.models(for: provider.id).count
            importDiscovered(providerID: provider.id, models: models)
            let after = config.models(for: provider.id).count
            if existingID != nil {
                let added = after - before
                showToast(added > 0
                    ? "\(provider.name): imported \(added) new model\(added == 1 ? "" : "s")"
                    : "\(provider.name): catalog is up to date", kind: .success)
            }
            return true
        case .success:
            showToast("\(provider.name): connected, but the catalog scan found no models", kind: .info)
            return true
        case .failure(let error):
            showToast("\(provider.name): \(error.message)", kind: .error)
            return false
        }
    }

    /// Creates (or resolves) the provider for a source; nil when the user must
    /// act first (e.g. TalkNova with no stored key).
    private func connectSource(_ candidate: LocalSourceCandidate, existingID: String?) async -> ProviderConfig? {
        if let existingID, let provider = config.provider(id: existingID) {
            return provider
        }
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
    }

    // MARK: - Discord presence


    /// Diagnostic hook (`WEHNIROUTE_SECTION_PROBE=1`) that walks every section
    /// through the real UI wiring, so presence can be verified headlessly.
    func runSectionProbe() {
        Task { @MainActor [weak self] in
            for candidate in AppSection.allCases {
                guard let self else { return }
                self.section = candidate
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    /// Presence is always on, uses the bundled WehniRoute Discord application,
    /// and is not user-configurable.
    func startPresence() {
        presence.start(clientID: DiscordPresenceManager.defaultClientID)
        refreshSectionPresence()
    }

    /// Feeds the current tab into Discord so the presence is never blank and
    /// changes as you move around the app.
    func refreshSectionPresence() {
        presence.presentSection(
            title: section.title,
            summary: sectionSummary(section),
            sessionStart: startedAt
        )
    }

    /// Called when the window loses focus; keeps presence populated.
    func dimPresenceForBackground() {
        presence.presentAway(summary: sectionSummary(section), sessionStart: startedAt)
    }

    /// "1 model" / "3 models" — presence text should never read like a template.
    private func count(_ value: Int, _ singular: String, plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    private func sectionSummary(_ section: AppSection) -> String {
        let activeProviders = config.providers.filter(\.enabled).count
        let activeModels = config.models.filter(\.enabled).count
        let gatewayOnline = gatewayStatus.isRunning
        switch section {
        case .overview:
            return "\(count(activeModels, "model")) · \(count(activeProviders, "provider")) · gateway \(gatewayOnline ? "online" : "stopped")"
        case .providers:
            let detected = detectedSources.filter(\.connected).count
            return detected > 0
                ? "\(count(activeProviders, "provider")) connected · \(count(detected, "found", plural: "found")) on this Mac"
                : "\(count(activeProviders, "provider")) connected"
        case .models:
            return "\(count(activeModels, "model")) · \(config.routing.tierMode.label) catalog"
        case .routing:
            return "\(config.routing.strategy.displayName) strategy · \(count(config.routing.fallbackAttempts, "fallback"))"
        case .harnesses:
            return "\(count(HarnessKind.allCases.count, "CLI agent")) supported"
        case .traces:
            return count(traceStore.traces.count, "routing decision") + " logged"
        case .settings:
            return gatewayOnline
                ? "gateway \(gatewayURL.replacingOccurrences(of: "http://", with: "")) · local only"
                : "gateway stopped · local only"
        }
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
        traceStore.record(trace)

        let (harnessHint, sessionStart) = expireActiveHarness()
        if trace.isSuccess {
            presence.present(
                harness: trace.harness ?? harnessHint,
                model: trace.selectedModel,
                provider: trace.selectedProviderName,
                fallback: trace.fallbackUsed,
                sessionStart: sessionStart
            )
        }
    }

    func clearTraces() {
        traceStore.clear()
        showToast("Decision records cleared", kind: .info)
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

    /// Immutable per-request view of all router state. Captured on the main
    /// actor once at request start; every decision, decode, network call, and
    /// classification after that runs on the gateway's detached task.
    private struct RoutingSnapshot: Sendable {
        var config: AppConfig
        var health: [String: HealthSnapshot]
        var gatewayAPIKey: String
        var activeHarness: String?
        var harnessSessionStart: Date
        var startedAt: Date
        var armedProviderID: String?
        var armedFailure: SimulatedFailure?
    }

    @MainActor
    private func currentRoutingSnapshot() -> RoutingSnapshot {
        let (harness, sessionStart) = expireActiveHarness()
        return RoutingSnapshot(
            config: config,
            health: health,
            gatewayAPIKey: gatewayAPIKey,
            activeHarness: harness,
            harnessSessionStart: sessionStart,
            startedAt: startedAt,
            armedProviderID: armedProviderID,
            armedFailure: armedFailure
        )
    }

    private nonisolated static func authorized(
        _ request: HTTPRequest,
        snapshot: RoutingSnapshot
    ) -> Bool {
        guard snapshot.config.requireAPIKey else { return true }
        if request.bearerToken == snapshot.gatewayAPIKey { return true }
        if request.headers["x-api-key"] == snapshot.gatewayAPIKey { return true }
        return false
    }

    /// Attributes traffic to a harness from the request itself. Conservative:
    /// only strong, well-known fingerprints are used.
    private nonisolated static func harnessFingerprint(_ headers: [String: String]) -> String? {
        let userAgent = headers["user-agent"]?.lowercased() ?? ""
        let xApp = headers["x-app"]?.lowercased()
        if userAgent.contains("claude-cli") || xApp == "cli" { return "Claude Code" }
        if userAgent.contains("opencode") { return "OpenCode" }
        if userAgent.contains("codex") { return "Codex" }
        if userAgent.contains("dsh") || headers["x-dsh-session"] != nil { return "DeepSeek Harness" }
        if headers["x-wehni-harness"] != nil { return headers["x-wehni-harness"] }
        return nil
    }

    /// Nonisolated so the body decode, classification, ranking, and provider
    /// loop run on the gateway's detached task instead of the main actor.
    private nonisolated func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let snapshot = await currentRoutingSnapshot()
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
            return .json(200, Self.healthPayload(snapshot))

        case ("POST", "/v1/harness-session"):
            // Loopback-only presence registration from launch scripts.
            guard let body = request.json else {
                return .error(400, message: "Invalid JSON body")
            }
            let harness = body["harness"]?.stringValue ?? ""
            guard !harness.isEmpty else {
                return .error(400, message: "Missing harness name")
            }
            await setActiveHarness(String(harness.prefix(48)))
            return .json(200, .object(["ok": .bool(true)]))

        case ("GET", "/v1/models"):
            guard Self.authorized(request, snapshot: snapshot) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            return .json(200, Self.modelsPayload())

        case ("POST", "/v1/chat/completions"):
            guard Self.authorized(request, snapshot: snapshot) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            guard let body = request.json else {
                return .error(400, message: "Invalid JSON body")
            }
            let canonical = CanonicalRequest.fromOpenAI(body)
            let requested = body["model"]?.stringValue ?? "auto"
            return await execute(
                canonical,
                endpoint: .openAI,
                requestedModel: requested,
                headerHarness: Self.harnessFingerprint(request.headers),
                snapshot: snapshot
            )

        case ("POST", "/v1/messages"):
            guard Self.authorized(request, snapshot: snapshot) else {
                return .error(401, message: "Missing or invalid WehniRoute API key")
            }
            guard let body = request.json else {
                return .error(400, message: "Invalid JSON body")
            }
            let canonical = CanonicalRequest.fromAnthropic(body)
            let requested = body["model"]?.stringValue ?? "auto"
            return await execute(
                canonical,
                endpoint: .anthropic,
                requestedModel: requested,
                headerHarness: Self.harnessFingerprint(request.headers),
                snapshot: snapshot
            )

        case ("GET", "/"):
            return .json(200, .object([
                "service": .string("WehniRoute Native"),
                "endpoints": .array([.string("/v1/chat/completions"), .string("/v1/messages"), .string("/v1/models"), .string("/healthz")]),
            ]))

        default:
            return .error(404, message: "Unknown route \(request.method) \(path)")
        }
    }

    private nonisolated static func healthPayload(_ snapshot: RoutingSnapshot) -> JSONValue {
        .object([
            "ok": .bool(true),
            "service": .string("WehniRoute Native"),
            "version": .string(AppVersion.short),
            "strategy": .string(snapshot.config.routing.strategy.rawValue),
            "connectedProviders": .num(snapshot.config.enabledProviders.count),
            "modelCount": .num(snapshot.config.enabledModels.count),
            "port": .num(snapshot.config.gatewayPort),
            "bind": .string("127.0.0.1"),
            "uptimeSec": .num(Int(Date().timeIntervalSince(snapshot.startedAt))),
            "apiKeyRequired": .bool(snapshot.config.requireAPIKey),
        ])
    }

    private nonisolated static func modelsPayload() -> JSONValue {
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

    private nonisolated func execute(
        _ request: CanonicalRequest,
        endpoint: GatewayEndpoint,
        requestedModel: String,
        headerHarness: String?,
        snapshot: RoutingSnapshot
    ) async -> HTTPResponse {
        let started = Date()
        let task = Router.classify(messages: request.messages, tools: request.tools)
        let estimated = Router.estimateTokens(messages: request.messages, tools: request.tools)
        let ranking = Router.rank(
            config: snapshot.config,
            health: snapshot.health,
            estimatedInputTokens: estimated,
            task: task,
            requestedModel: requestedModel
        )
        let ranked = ranking.candidates

        // Health updates stay local until the single publish hop, so a request
        // never mutates @Published state mid-flight.
        var localHealth = snapshot.health
        var consumedSimulation: String?

        var trace = Trace(
            requestID: "req_\(UUID().uuidString.prefix(10).lowercased())",
            endpoint: endpoint == .openAI ? "/v1/chat/completions" : "/v1/messages",
            requestedModel: requestedModel,
            taskType: task,
            strategy: snapshot.config.routing.strategy,
            status: 0,
            latencyMS: 0,
            requestPreview: request.preview(),
            harness: headerHarness ?? snapshot.activeHarness
        )

        guard !ranked.isEmpty else {
            let reason = ranking.rejected.first?.reason ?? "No connected providers"
            trace.status = 503
            trace.latencyMS = Int(Date().timeIntervalSince(started) * 1_000)
            trace.errorSummary = "No eligible route. \(reason)"
            await publish(
                trace: trace,
                health: localHealth,
                baseline: snapshot.health,
                consumedSimulation: consumedSimulation
            )
            return .error(503, message: "No eligible route: \(reason). Connect a provider or loosen the routing policy.")
        }

        let limit = min(max(1, snapshot.config.routing.fallbackAttempts), ranked.count)
        var fallbackUsed = false
        var lastFailure = "No provider answered"

        for candidate in ranked.prefix(limit) {
            guard let provider = snapshot.config.provider(id: candidate.providerID),
                  let model = snapshot.config.models.first(where: {
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
                localHealth[provider.id] = Self.updatedHealthSnapshot(
                    localHealth[provider.id],
                    success: false,
                    latency: 0,
                    message: detail
                )
                consumedSimulation = provider.id
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
                localHealth[provider.id] = Self.updatedHealthSnapshot(
                    localHealth[provider.id],
                    success: true,
                    latency: latency,
                    message: nil
                )
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
                trace.costUSD = Self.cost(for: model, usage: response.usage)
                trace.fallbackUsed = fallbackUsed
                trace.responsePreview = String(response.text.prefix(240))
                await publish(
                    trace: trace,
                    health: localHealth,
                    baseline: snapshot.health,
                    consumedSimulation: consumedSimulation
                )

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
                localHealth[provider.id] = Self.updatedHealthSnapshot(
                    localHealth[provider.id],
                    success: false,
                    latency: latency,
                    message: message
                )
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
                localHealth[provider.id] = Self.updatedHealthSnapshot(
                    localHealth[provider.id],
                    success: false,
                    latency: latency,
                    message: message
                )
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
        await publish(
            trace: trace,
            health: localHealth,
            baseline: snapshot.health,
            consumedSimulation: consumedSimulation
        )
        return .error(502, message: "All providers failed. \(lastFailure)")
    }

    /// The only main-actor hop at the end of a request: publish changed health
    /// snapshots, disarm a consumed simulation, and record the trace.
    @MainActor
    private func publish(
        trace: Trace,
        health updated: [String: HealthSnapshot],
        baseline: [String: HealthSnapshot],
        consumedSimulation: String?
    ) {
        for (providerID, snapshot) in updated where baseline[providerID] != snapshot {
            health[providerID] = snapshot
        }
        if let consumedSimulation {
            clearSimulationState(for: consumedSimulation)
            if armedProviderID == consumedSimulation {
                armedProviderID = nil
                armedFailure = nil
            }
        }
        record(trace)
    }

    private nonisolated static func updatedHealthSnapshot(
        _ current: HealthSnapshot?,
        success: Bool,
        latency: Int?,
        message: String?
    ) -> HealthSnapshot {
        var snapshot = current ?? HealthSnapshot()
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
        return snapshot
    }

    private func recordHealth(
        providerID: String,
        success: Bool,
        latency: Int?,
        status: Int?,
        message: String?
    ) {
        health[providerID] = Self.updatedHealthSnapshot(
            health[providerID],
            success: success,
            latency: latency,
            message: message
        )
    }

    private nonisolated static func cost(for model: ModelConfig, usage: TokenUsage) -> Double {
        if model.isFree { return 0 }
        let input = (model.inputPerMillion ?? 0) / 1_000_000 * Double(usage.input)
        let output = (model.outputPerMillion ?? 0) / 1_000_000 * Double(usage.output)
        return input + output
    }

    // MARK: - Derived stats

    var providerHealthList: [(ProviderConfig, HealthSnapshot)] {
        config.providers.map { ($0, health[$0.id] ?? HealthSnapshot()) }
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
