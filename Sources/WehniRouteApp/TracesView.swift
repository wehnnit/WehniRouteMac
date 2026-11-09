import AppKit
import SwiftUI
import WehniRouteCore

private func traceStatusTint(_ status: Int) -> Color {
    if (200..<300).contains(status) { return Theme.green }
    if status >= 500 { return Theme.rose }
    return Theme.amber
}

private func outcomeTint(_ outcome: AttemptOutcome) -> Color {
    switch outcome {
    case .success: return Theme.green
    case .httpError: return Theme.amber
    case .networkError: return Theme.rose
    case .simulated: return Theme.violet
    case .skipped: return Theme.faint
    }
}

struct TracesView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var traces: TraceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Decision log",
                title: "Traces",
                subtitle: "Every gateway call records the classifier, candidate order, attempts, latency, tokens, and cost. Nothing is sampled away."
            ) {
                HStack(spacing: 8) {
                    Pill(text: "\(traces.traces.count) RECORDS", tint: Theme.accent)
                    Menu {
                        Button("Clear all records", role: .destructive) {
                            store.clearTraces()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 27, height: 27)
                            .background(Circle().fill(Color.white.opacity(0.045)))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 0.8))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            HStack(alignment: .top, spacing: 12) {
                listCard
                inspectorCard
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if traces.selectedTraceID == nil {
                traces.selectedTraceID = traces.traces.first?.id
            }
        }
    }

    private var listCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                Picker("Filter", selection: $traces.filter) {
                    ForEach(TraceFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)

                DividerLine()

                if traces.filteredTraces.isEmpty {
                    EmptyState(
                        symbol: "waveform.path.ecg",
                        title: "No matching decisions",
                        message: "Route a request through the gateway or change the filter. Simulation calls work offline.",
                        actionTitle: "Open providers",
                        action: { store.section = .providers }
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(traces.filteredTraces) { trace in
                                TraceListRow(
                                    trace: trace,
                                    isSelected: traces.selectedTraceID == trace.id,
                                    onSelect: { traces.selectedTraceID = trace.id }
                                )
                                if trace.id != traces.filteredTraces.last?.id {
                                    DividerLine().padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
    }

    private var inspectorCard: some View {
        GlassCard(padding: 0) {
            if let trace = traces.selectedTrace {
                ScrollView(.vertical, showsIndicators: false) {
                    TraceDetail(trace: trace)
                        .padding(16)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                EmptyState(
                    symbol: "sidebar.right",
                    title: "Select a decision",
                    message: "Pick a trace to inspect its candidate order, fallback attempts, request shape, and exact outcome."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TraceListRow: View {
    let trace: Trace
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(traceStatusTint(trace.status))
                    .frame(width: 5, height: 5)
                    .shadow(color: traceStatusTint(trace.status).opacity(0.7), radius: 3)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(trace.taskType.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if trace.fallbackUsed {
                            Pill(text: "FALLBACK", tint: Theme.amber)
                        }
                    }
                    Text(trace.selectedProviderName ?? "No route selected")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Text(trace.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.latency(trace.latencyMS))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text("HTTP \(trace.status)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(traceStatusTint(trace.status))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accent.opacity(0.065) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TraceDetail: View {
    let trace: Trace

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header

            if let error = trace.errorSummary, !error.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.rose)
                        .padding(.top, 1)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.rose.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.rose.opacity(0.18), lineWidth: 1))
            }

            metadataGrid

            selectedRoute

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(
                    "ATTEMPT TIMELINE",
                    trailing: trace.attempts.count == 1 ? "1 attempt" : "\(trace.attempts.count) attempts"
                )
                if trace.attempts.isEmpty {
                    Text("No provider was attempted.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(trace.attempts) { attempt in
                            AttemptRow(attempt: attempt)
                        }
                    }
                }
            }

            previewSection("REQUEST PREVIEW", text: trace.requestPreview)

            if !trace.responsePreview.isEmpty {
                previewSection("RESPONSE PREVIEW", text: trace.responsePreview)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(trace.requestID)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                Text("\(trace.endpoint) · \(trace.createdAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }

            Spacer()

            HStack(spacing: 6) {
                if trace.fallbackUsed {
                    Pill(text: "FALLBACK", tint: Theme.amber)
                }
                Pill(
                    text: "HTTP \(trace.status)",
                    tint: traceStatusTint(trace.status),
                    icon: trace.isSuccess ? "checkmark" : "exclamationmark"
                )
            }
        }
    }

    private var metadataGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
            spacing: 7
        ) {
            MetadataTile(label: "TASK", value: trace.taskType.label)
            MetadataTile(label: "STRATEGY", value: trace.strategy.displayName)
            MetadataTile(label: "LATENCY", value: Format.latency(trace.latencyMS))
            MetadataTile(label: "INPUT", value: "\(trace.inputTokens) tok")
            MetadataTile(label: "OUTPUT", value: "\(trace.outputTokens) tok")
            MetadataTile(label: "COST", value: Format.money(trace.costUSD))
        }
    }

    private var selectedRoute: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("SELECTED ROUTE")
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.accent.opacity(0.08))
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(trace.selectedModel ?? "No model selected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(trace.selectedProviderName ?? "No provider") · requested \(trace.requestedModel)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.latency(trace.latencyMS))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                    Text(Format.money(trace.costUSD))
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
        }
    }

    private func previewSection(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.20)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.stroke, lineWidth: 0.8))
        }
    }
}

private struct AttemptRow: View {
    let attempt: TraceAttempt

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(outcomeTint(attempt.outcome))
                .frame(width: 5, height: 5)
                .shadow(color: outcomeTint(attempt.outcome).opacity(0.6), radius: 2)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attempt.providerName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Pill(text: attempt.outcome.label.uppercased(), tint: outcomeTint(attempt.outcome))
                    Spacer()
                    if let status = attempt.status {
                        Text("HTTP \(status)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.faint)
                    }
                    Text(Format.latency(attempt.latencyMS))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                }
                Text(attempt.model)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                if let detail = attempt.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(attempt.outcome == .success ? Theme.faint : Theme.rose.opacity(0.9))
                        .lineLimit(2)
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.022)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 0.7))
    }
}

private struct MetadataTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 0.7))
    }
}

private struct SectionLabel: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.faint)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}
