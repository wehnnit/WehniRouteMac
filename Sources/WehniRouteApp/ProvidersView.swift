import SwiftUI
import WehniRouteCore

struct ProvidersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingRemoval: ProviderConfig?

    private var sourcesStrip: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("DETECTED ON THIS MAC")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button {
                        Task { await store.scanLocalSources() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(IconButtonStyle())
                    .disabled(store.scanningSources)
                    .help("Rescan local sources")
                }

                if store.scanningSources {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Probing loopback ports and known installs…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 330), spacing: 10)], spacing: 10) {
                        ForEach(store.detectedSources) { source in
                            SourceCard(source: source)
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Connections",
                title: "Providers",
                subtitle: "Connect the models you already trust. WehniRoute keeps every key in the macOS Keychain and routes through a single local endpoint."
            ) {
                Picker("Tier", selection: Binding(
                    get: { store.tierMode },
                    set: { store.setTierMode($0) }
                )) {
                    ForEach(TierMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .labelsHidden()
                .help(TierMode.allCases.first { $0 == store.tierMode }?.blurb ?? "")

                HStack(spacing: 8) {
                    Button {
                        Task {
                            for provider in store.config.providers {
                                await store.testProvider(provider)
                            }
                        }
                    } label: {
                        Label("Refresh health", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GhostButtonStyle())

                    Button {
                        store.showAddProvider = true
                    } label: {
                        Label("Connect provider", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }

            if store.detectedSources.isEmpty && !store.scanningSources {
                HStack(spacing: 10) {
                    Image(systemName: "sensor.tag.radiowaves.right.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                    Text("Scan for local model sources — Ollama, LM Studio, Jan, GPT4All, KoboldCpp, llama.cpp, vLLM, MLX and more, plus Antigravity bridges and TalkNova")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button {
                        Task { await store.scanLocalSources() }
                    } label: {
                        Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
            }

            if store.scanningSources || !store.detectedSources.isEmpty {
                sourcesStrip
            }

            HStack(alignment: .top, spacing: 12) {
                Group {
                    if store.config.providers.isEmpty {
                        GlassCard {
                            EmptyState(
                                symbol: "point.3.connected.trianglepath.dotted",
                                title: "No providers connected",
                                message: "Start with Anthropic, OpenAI, or the offline simulation. You can add multiple accounts and custom OpenAI-compatible endpoints.",
                                actionTitle: "Connect a provider",
                                action: { store.showAddProvider = true }
                            )
                        }
                    } else {
                        let visible = store.config.providers.filter { store.providerMatchesTier($0) }
                        if visible.isEmpty {
                            GlassCard {
                                EmptyState(
                                    symbol: "line.3.horizontal.decrease.circle",
                                    title: "Nothing to route in this tier",
                                    message: "No connected provider contributes enabled models to the \(store.tierMode.label.lowercased()) tier. Connect one or switch the tier mode above."
                                )
                            }
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(visible) { provider in
                                    ProviderCard(provider: provider) {
                                        pendingRemoval = provider
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ProviderSidebar()
                    .frame(width: 292)
            }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "provider")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { provider in
            Button("Remove provider", role: .destructive) {
                store.removeProvider(provider)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { _ in
            Text("This removes the provider, its models, its health state, and its Keychain entry. The API key cannot be recovered from WehniRoute.")
        }
    }
}

struct ProviderCard: View {
    @EnvironmentObject private var store: AppStore
    let provider: ProviderConfig
    let onRemove: () -> Void

    @State private var hovering = false

    private var snapshot: HealthSnapshot {
        store.health[provider.id] ?? HealthSnapshot()
    }

    private var models: [ModelConfig] {
        store.models(for: provider.id).filter(\.enabled)
    }

    @ViewBuilder
    private var tierBadges: some View {
        let free = models.filter(\.isFree).count
        let paid = models.count - free
        if free > 0 {
                            Pill(text: "\(free) FREE", tint: Theme.green)
        }
        if paid > 0 {
                            Pill(text: "\(paid) PAID", tint: Theme.blue)
        }
    }

    private var isTesting: Bool {
        store.testingProviderID == provider.id
    }

    private var statusTint: Color {
        switch snapshot.state {
        case .healthy: return Theme.green
        case .degraded: return Theme.amber
        case .down: return Theme.rose
        case .unknown: return Theme.faint
        }
    }

    private var authLabel: String {
        if !provider.kind.requiresKey { return "No key" }
        return "Keychain"
    }

    private var authTint: Color {
        if !provider.kind.requiresKey { return Theme.muted }
        return Theme.green
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 10) {
                    ProviderGlyph(kind: provider.kind, size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if provider.kind.isLocal {
                                Pill(text: "LOCAL", tint: Theme.violet)
                            }
                            tierBadges
                        }
                        Text(provider.kind.tagline)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                    }

                    Spacer()

                    Pill(text: snapshot.state.label.uppercased(), tint: statusTint)

                    Menu {
                        Button("Test connection") {
                            Task { await store.testProvider(provider) }
                        }
                        Menu("Simulate next call") {
                            ForEach(SimulatedFailure.allCases) { failure in
                                Button(failure.label) {
                                    store.armSimulation(failure, on: provider.id)
                                }
                            }
                        }
                        if provider.simulatedFailure != nil {
                            Button("Clear simulation") {
                                store.clearSimulation()
                            }
                        }
                        Divider()
                        Button("Remove provider", role: .destructive, action: onRemove)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                HStack(spacing: 6) {
                    Pill(text: provider.apiFormat.label.uppercased(), tint: Theme.blue)
                    if provider.simulatedFailure != nil {
                        Pill(text: "SIM ARMED", tint: Theme.amber)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { provider.enabled },
                        set: { store.setProviderEnabled(provider.id, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .scaleEffect(0.8)
                }

                DividerLine().opacity(0.7)

                HStack(spacing: 18) {
                    ProviderStat(label: "MODELS", value: "\(models.count)")
                    ProviderStat(
                        label: "LATENCY",
                        value: snapshot.avgLatencyMS.map(Format.latency) ?? "—"
                    )
                    ProviderStat(label: "AUTH", value: authLabel, tint: authTint)
                }

                DividerLine().opacity(0.7)

                HStack(spacing: 8) {
                    Text(provider.baseURL)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        Task { await store.testProvider(provider) }
                    } label: {
                        HStack(spacing: 4) {
                            if isTesting {
                                ProgressView().controlSize(.small).scaleEffect(0.7)
                            }
                            Text(isTesting ? "Testing" : "Test")
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .disabled(isTesting)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(hovering ? Theme.accent.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .hoverLift()
    }
}

private struct ProviderStat: View {
    let label: String
    let value: String
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

private struct ProviderSidebar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var traces: TraceStore

    var body: some View {
        VStack(spacing: 12) {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("Connection guide")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Pill(text: "KEYCHAIN", tint: Theme.green)
                    }

                    Text("A provider is one upstream API. Keys stay in Keychain; models and routing stay in this app.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    DividerLine().opacity(0.7)

                    ProviderGuideRow(index: "01", title: "Connect", detail: "Paste a key or point at a local endpoint.")
                    ProviderGuideRow(index: "02", title: "Enable models", detail: "Pick the exact model IDs the router may use.")
                    ProviderGuideRow(index: "03", title: "Route", detail: "Health, price, and context decide the winner.")

                    DividerLine().opacity(0.7)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                        Text("Keys are never written to native-config.json.")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ROUTING IMPACT")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.faint)

                    HStack(spacing: 0) {
                        ProviderImpactStat(label: "PROVIDERS", value: "\(store.config.providers.count)")
                        ProviderImpactDivider()
                        ProviderImpactStat(label: "MODELS", value: "\(store.config.models.count)")
                        ProviderImpactDivider()
                        ProviderImpactStat(label: "TRACES", value: "\(traces.traces.count)")
                    }

                    Button("Open routing lab") {
                        withAnimation(.snappy(duration: 0.22)) {
                            store.section = .routing
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}

private struct ProviderGuideRow: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProviderImpactStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderImpactDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 9)
    }
}


private struct SourceCard: View {
    @EnvironmentObject private var store: AppStore
    let source: LocalSourceCandidate
    @State private var adopting = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if source.connected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.green)
                    }
                }
                Text(source.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if source.connected {
                Button {
                    adopting = true
                    Task {
                        await store.adoptLocalSource(source)
                        await store.scanLocalSources()
                        adopting = false
                    }
                } label: {
                    Text(adopting ? "…" : "Refresh catalog")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(adopting)
                .help("Re-scan this source's catalog and import anything new")
            } else {
                Button {
                    adopting = true
                    Task {
                        await store.adoptLocalSource(source)
                        await store.scanLocalSources()
                        adopting = false
                    }
                } label: {
                    Text(adopting ? "…" : "Use")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(adopting)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private var icon: String {
        if let kind = source.kind.kind {
            return kind.symbol
        }
        switch source.kind {
        case .antigravityBridge: return "arrow.triangle.branch"
        case .talkNova: return "bubble.left.and.bubble.right.fill"
        default: return "server.rack"
        }
    }
}
