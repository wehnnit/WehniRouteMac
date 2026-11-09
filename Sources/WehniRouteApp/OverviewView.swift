import SwiftUI
import WehniRouteCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var traces: TraceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(.top, 18)

            if store.config.providers.isEmpty {
                SetupBanner()
                    .padding(.top, 18)
            }

            metrics
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    TrafficCard()
                    RecentTracesCard()
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 12) {
                    ProviderHealthCard()
                    PolicyCard()
                }
                .frame(width: 312)
            }
            .padding(.top, 12)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Pill(text: "LOCAL-FIRST", tint: Theme.accent)
                    Pill(text: "OPENAI + ANTHROPIC", tint: Theme.violet)
                    Pill(
                        text: store.config.routing.strategy.displayName.uppercased(),
                        tint: Color(hex: store.config.routing.strategy.accentHex)
                    )
                }

                Text("Route with intent.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.text, Color(hex: 0xBFE9E2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)

                Text("One endpoint for every model. Every request leaves an explainable decision.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 16)

            VStack(alignment: .trailing, spacing: 7) {
                Text("CURRENT ENDPOINT")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.faint)
                HStack(spacing: 7) {
                    Circle()
                        .fill(store.gatewayStatus.isRunning ? Theme.green : Theme.rose)
                        .frame(width: 5, height: 5)
                        .shadow(color: (store.gatewayStatus.isRunning ? Theme.green : Theme.rose).opacity(0.8), radius: 4)
                    Text(store.gatewayURL)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                }
                Text("\(store.config.enabledProviders.count) providers · \(store.config.enabledModels.count) models")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.faint)
                Button("Copy endpoint") { store.copyGatewayURL() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }

    private var metrics: some View {            LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            MetricCard(
                title: "Requests",
                value: "\(traces.traces.count)",
                detail: "\(traces.hourRequestCount) in the last hour",
                symbol: "arrow.up.right",
                tint: Theme.accent,
                values: requestSpark
            )
            MetricCard(
                title: "Success",
                value: traces.successRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                detail: "\(traces.traces.filter(\.isSuccess).count) clean routes",
                symbol: "checkmark.seal.fill",
                tint: Theme.green,
                values: successSpark
            )
            MetricCard(
                title: "Avg latency",
                value: traces.averageLatencyMS.map(Format.latency) ?? "—",
                detail: "end-to-end route time",
                symbol: "speedometer",
                tint: Theme.amber,
                values: traces.sparklineValues()
            )
            MetricCard(
                title: "Spend",
                value: Format.money(traces.totalCost),
                detail: "\(Format.compact(traces.totalTokens)) tokens routed",
                symbol: "creditcard.fill",
                tint: Theme.violet,
                values: costSpark
            )
        }
    }

    private var requestSpark: [Double] {
        let samples = Array(traces.traces.prefix(24).reversed())
        guard !samples.isEmpty else { return [] }
        return samples.enumerated().map { Double($1.totalTokens + $0 + 1) }
    }

    private var successSpark: [Double] {
        let samples = Array(traces.traces.prefix(24).reversed())
        guard !samples.isEmpty else { return [] }
        return samples.map { $0.isSuccess ? 1 : 0 }
    }

    private var costSpark: [Double] {
        let samples = Array(traces.traces.prefix(24).reversed())
        guard !samples.isEmpty else { return [] }
        return samples.map { $0.costUSD + 0.001 }
    }
}

private struct SetupBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.22), Theme.violet.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("Connect your first provider")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Add an API key or start with the offline simulation. Keys stay in the macOS Keychain.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    SetupStep(index: "1", label: "Connect")
                    SetupStep(index: "2", label: "Route")
                    SetupStep(index: "3", label: "Inspect")
                }
                .padding(.top, 2)
            }

            Spacer()

            Button("Connect provider") { store.showAddProvider = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.trailing, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.09), Theme.violet.opacity(0.06), Theme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.accent.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct SetupStep: View {
    let index: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(index)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.035)))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 0.7))
    }
}

private struct TrafficCard: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var traces: TraceStore

    private var samples: [Trace] {
        Array(traces.traces.prefix(28).reversed())
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route latency")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Each point is a gateway decision")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        LegendDot(color: Theme.accent, label: "latency")
                        LegendDot(color: Theme.violet.opacity(0.8), label: "route")
                    }
                }

                ZStack {
                    TrafficChart(traces: samples)
                        .frame(height: 104)
                    if samples.count < 2 {
                        VStack(spacing: 5) {
                            Text("Waiting for the first route")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.muted)
                            Text("Send a request to the gateway, or arm a simulation.")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }

                HStack(spacing: 0) {
                    TrafficStat(label: "p50", value: traces.averageLatencyMS.map(Format.latency) ?? "—")
                    TrafficDivider()
                    TrafficStat(label: "fallback", value: traces.fallbackRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    TrafficDivider()
                    TrafficStat(label: "tokens", value: Format.compact(traces.totalTokens))
                }
            }
        }
    }
}

private struct TrafficChart: View {
    let traces: [Trace]

    var body: some View {
        Canvas { context, size in
            let gridLines = 4
            for index in 0...gridLines {
                let y = size.height * CGFloat(index) / CGFloat(gridLines)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(Color.white.opacity(0.045)), lineWidth: 0.7)
            }

            let values = traces.map { Double(max($0.latencyMS, 20)) }
            guard values.count > 1 else { return }
            let rawMax = values.max() ?? 100
            let rawMin = values.min() ?? 0
            let maxValue = max(rawMax * 1.15, rawMax + 20)
            let minValue = max(0, rawMin - max(20, rawMin * 0.15))
            let span = max(maxValue - minValue, 1)
            let stepX = size.width / CGFloat(values.count - 1)

            var line = Path()
            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))

            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * stepX,
                    y: size.height - (CGFloat((value - minValue) / span) * (size.height - 12)) - 6
                )
                if index == 0 {
                    line.move(to: point)
                    area.addLine(to: point)
                } else {
                    line.addLine(to: point)
                    area.addLine(to: point)
                }
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                line,
                with: .linearGradient(
                    Gradient(colors: [Theme.violet.opacity(0.7), Theme.accent]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.faint)
        }
    }
}

private struct TrafficStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrafficDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 10)
    }
}

private struct RecentTracesCard: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var traces: TraceStore

    private var recent: [Trace] {
        Array(traces.traces.prefix(5))
    }

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Recent decisions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button("View log") {
                        withAnimation(.snappy(duration: 0.22)) {
                            store.section = .traces
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)

                DividerLine()

                if recent.isEmpty {
                    EmptyState(
                        symbol: "waveform.path.ecg",
                        title: "No decisions yet",
                        message: "Route a request through the local gateway and the full decision record appears here.",
                        actionTitle: "Open provider setup",
                        action: { store.section = .providers }
                    )
                } else {
                    ForEach(recent) { trace in
                        CompactTraceRow(trace: trace) {
                            traces.selectedTraceID = trace.id
                            store.section = .traces
                        }
                        if trace.id != recent.last?.id {
                            DividerLine().padding(.leading, 17)
                        }
                    }
                }
            }
        }
    }
}

private struct CompactTraceRow: View {
    let trace: Trace
    let action: () -> Void

    private var tint: Color {
        trace.isSuccess ? Theme.green : (trace.status >= 500 ? Theme.rose : Theme.amber)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .shadow(color: tint.opacity(0.7), radius: 3)
                    .padding(.leading, 3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(trace.taskType.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if trace.fallbackUsed {
                            Pill(text: "FALLBACK", tint: Theme.amber)
                        }
                    }
                    Text(trace.selectedProviderName ?? "No route")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                Text(trace.selectedModel ?? trace.requestedModel)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .trailing)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.latency(trace.latencyMS))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text(trace.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                }
                .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProviderHealthCard: View {
    @EnvironmentObject private var store: AppStore

    private var items: [HealthItem] {
        store.config.providers.map {
            HealthItem(provider: $0, snapshot: store.health[$0.id] ?? HealthSnapshot())
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Provider health")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button("Manage") { store.section = .providers }
                        .buttonStyle(GhostButtonStyle())
                }

                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No providers connected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        Text("Health appears after a provider is tested or routed.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(items) { item in
                        HealthRow(item: item)
                        if item.id != items.last?.id {
                            DividerLine().opacity(0.6)
                        }
                    }
                }
            }
        }
    }
}

private struct HealthItem: Identifiable {
    let provider: ProviderConfig
    let snapshot: HealthSnapshot
    var id: String { provider.id }
}

private struct HealthRow: View {
    let item: HealthItem

    private var score: Double {
        switch item.snapshot.state {
        case .healthy: return 1
        case .degraded: return 0.42
        case .down: return 0.08
        case .unknown: return 0.5
        }
    }

    private var tint: Color {
        switch item.snapshot.state {
        case .healthy: return Theme.green
        case .degraded: return Theme.amber
        case .down: return Theme.rose
        case .unknown: return Theme.faint
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ProviderGlyph(kind: item.provider.kind, size: 27)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.provider.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text)
                    StatusDot(state: item.snapshot.state, size: 5)
                }
                ScoreBar(value: score, tint: tint, height: 3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.snapshot.avgLatencyMS.map(Format.latency) ?? "—")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(item.snapshot.state.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PolicyCard: View {
    @EnvironmentObject private var store: AppStore

    private var topCandidate: Candidate? {
        store.rankedCandidates.first
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Current policy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Pill(
                        text: store.config.routing.strategy.displayName.uppercased(),
                        tint: Color(hex: store.config.routing.strategy.accentHex)
                    )
                }

                Text(store.config.routing.strategy.blurb)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                DividerLine().opacity(0.7)

                if let candidate = topCandidate {
                    HStack(spacing: 12) {
                        ScoreRing(value: candidate.score, tint: Theme.accent, size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.modelName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Text(candidate.providerName)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                            Text(candidate.reasons.prefix(2).joined(separator: " · "))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.faint)
                                .lineLimit(2)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No eligible candidate")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.amber)
                        Text("Connect a model or relax the routing policy.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.vertical, 4)
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

private struct ScoreRing: View {
    let value: Double
    var tint: Color = Theme.accent
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.45), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("fit")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(width: size, height: size)
    }
}
