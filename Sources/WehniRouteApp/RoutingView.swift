import SwiftUI
import WehniRouteCore

struct RoutingView: View {
    @EnvironmentObject private var store: AppStore

    private var candidates: [Candidate] {
        store.rankedCandidates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Decision engine",
                title: "Routing lab",
                subtitle: "The policy is deterministic and inspectable. Presets move the weights; every score, rejection, and fallback stays visible."
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(Strategy.allCases) { strategy in
                    StrategyCard(
                        strategy: strategy,
                        selected: store.config.routing.strategy == strategy
                    ) {
                        store.applyStrategy(strategy)
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    weightsCard
                    previewCard
                        .frame(width: 372)
                }

                VStack(alignment: .leading, spacing: 12) {
                    weightsCard
                    previewCard
                }
            }
            .padding(.top, 12)

            fallbackCard
                .padding(.top, 12)
        }
    }

    private var weightsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scoring weights")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("Normalized at decision time")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }
                    Spacer()
                    Button("Reset preset") {
                        store.applyStrategy(store.config.routing.strategy)
                    }
                    .buttonStyle(GhostButtonStyle())
                }

                VStack(spacing: 9) {
                    WeightSlider(
                        title: "Task fit",
                        value: store.binding(\.routing.weights.taskFit),
                        tint: Theme.violet
                    )
                    WeightSlider(
                        title: "Provider health",
                        value: store.binding(\.routing.weights.health),
                        tint: Theme.green
                    )
                    WeightSlider(
                        title: "Speed",
                        value: store.binding(\.routing.weights.speed),
                        tint: Theme.amber
                    )
                    WeightSlider(
                        title: "Cost",
                        value: store.binding(\.routing.weights.cost),
                        tint: Theme.accent
                    )
                    WeightSlider(
                        title: "Context headroom",
                        value: store.binding(\.routing.weights.context),
                        tint: Theme.blue
                    )
                    WeightSlider(
                        title: "Quota / locality",
                        value: store.binding(\.routing.weights.quota),
                        tint: Theme.rose
                    )
                }

                DividerLine().opacity(0.7)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                    Text("Higher fit + health wins by default. Cost rises when you choose Cheap.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Candidate preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(candidates.count) eligible")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                }

                Picker("Preview task", selection: $store.previewTask) {
                    ForEach(TaskType.allCases, id: \.self) { task in
                        Text(task.label).tag(task)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No eligible routes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.amber)
                        Text("Connect a provider or relax paid-model and context constraints.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(candidates.prefix(5).enumerated()), id: \.element.id) { index, candidate in
                            CandidateRow(
                                rank: index + 1,
                                candidate: candidate,
                                providerKind: store.provider(id: candidate.providerID)?.kind ?? .custom
                            )
                        }
                    }
                }

                DividerLine().opacity(0.7)

                HStack(spacing: 8) {
                    Text("\(store.rejectedCandidates.count) filtered by policy")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer()
                    Button("Inspect traces") {
                        withAnimation(.snappy(duration: 0.22)) {
                            store.section = .traces
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }

    private var fallbackCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fallback ladder")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("If a provider fails, the next candidate is tried and the attempt is recorded.")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        Text("ATTEMPTS")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(Theme.faint)
                        Stepper(
                            "",
                            value: store.binding(\.routing.fallbackAttempts),
                            in: 1...6
                        )
                        .labelsHidden()
                        Text("\(store.config.routing.fallbackAttempts)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(width: 12)
                    }

                    Toggle(isOn: store.binding(\.routing.allowPaidModels)) {
                        Text("Allow paid models")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .scaleEffect(0.85)
                }

                DividerLine().opacity(0.7)

                if candidates.isEmpty {
                    Text("The ladder is empty until a provider has an enabled model.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(Array(candidates.prefix(store.config.routing.fallbackAttempts).enumerated()), id: \.element.id) { index, candidate in
                            FallbackRung(
                                index: index + 1,
                                candidate: candidate,
                                providerKind: store.provider(id: candidate.providerID)?.kind ?? .custom
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct StrategyCard: View {
    let strategy: Strategy
    let selected: Bool
    let action: () -> Void

    private var tint: Color {
        Color(hex: strategy.accentHex)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.12))
                        Image(systemName: strategy.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 26, height: 26)

                    Spacer()

                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? tint : Theme.faint.opacity(0.6))
                }

                Text(strategy.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(strategy.blurb)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? tint.opacity(0.075) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? tint.opacity(0.42) : Theme.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WeightSlider: View {
    let title: String
    @Binding var value: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
            }
            Slider(value: $value, in: 0...1)
                .tint(tint)
                .controlSize(.mini)
        }
    }
}

private struct CandidateRow: View {
    let rank: Int
    let candidate: Candidate
    let providerKind: ProviderKind

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Text("\(rank)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 12)
                ProviderGlyph(kind: providerKind, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.modelName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(candidate.providerName)
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                Text("\(Int((candidate.score * 100).rounded()))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            ScoreBar(value: candidate.score, tint: Theme.accent, height: 3)
        }
    }
}

private struct FallbackRung: View {
    let index: Int
    let candidate: Candidate
    let providerKind: ProviderKind

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index)")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            ProviderGlyph(kind: providerKind, size: 20)
            Text(candidate.modelName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 0.8))
    }
}
