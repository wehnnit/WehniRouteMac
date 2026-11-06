import SwiftUI
import WehniRouteCore

struct ModelsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Model catalog",
                title: "Models",
                subtitle: "Expose only the models you want this router to consider. Every model carries its own context window, price, and free-tier flag."
            ) {
                Button {
                    store.showAddModel = true
                } label: {
                    Label("Add model", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.config.providers.isEmpty)
                .opacity(store.config.providers.isEmpty ? 0.45 : 1)
            }

            HStack(alignment: .top, spacing: 12) {
                Group {
                    if store.config.providers.isEmpty {
                        GlassCard {
                            EmptyState(
                                symbol: "cpu.fill",
                                title: "No models to configure",
                                message: "Connect a provider first. Its starter model is added automatically, and you can add more exact model IDs here.",
                                actionTitle: "Connect a provider",
                                action: { store.showAddProvider = true }
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(store.config.providers) { provider in
                                ProviderModelSection(provider: provider)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ModelSidebar()
                    .frame(width: 292)
            }
        }
    }
}

private struct ProviderModelSection: View {
    @EnvironmentObject private var store: AppStore
    let provider: ProviderConfig

    private var models: [ModelConfig] {
        store.models(for: provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderGlyph(kind: provider.kind, size: 26)
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(models.count) \(models.count == 1 ? "model" : "models")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                Spacer()
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if models.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                            Text("No models yet. Add one to make this provider eligible.")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                        }
                        .padding(16)
                    } else {
                        ForEach(models) { model in
                            ModelRow(model: model)
                            if model.id != models.last?.id {
                                DividerLine().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ModelRow: View {
    @EnvironmentObject private var store: AppStore
    let model: ModelConfig

    private var priceLabel: String {
        if model.isFree { return "Free" }
        guard let input = model.inputPerMillion, let output = model.outputPerMillion else {
            return "Price unset"
        }
        return "\(Format.money(input)) / \(Format.money(output)) M"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.07))
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if model.isFree {
                        Pill(text: "FREE", tint: Theme.green)
                    }
                }
                Text(model.modelID)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.compact(model.contextWindow)) context")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(priceLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.faint)
            }
            .frame(width: 132, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { model.enabled },
                set: { store.setModelEnabled(model.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(Theme.accent)
            .scaleEffect(0.75)

            Menu {
                Button("Remove model", role: .destructive) {
                    store.removeModel(model)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ModelSidebar: View {
    @EnvironmentObject private var store: AppStore

    private var models: [ModelConfig] { store.config.models }
    private var enabledModels: Int { models.filter(\.enabled).count }
    private var freeModels: Int { models.filter(\.isFree).count }

    var body: some View {
        VStack(spacing: 12) {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("CATALOG")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Theme.faint)
                        Spacer()
                        Pill(text: "\(enabledModels) ACTIVE", tint: enabledModels > 0 ? Theme.green : Theme.faint)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ModelSidebarStat(label: "TOTAL", value: "\(models.count)")
                        ModelSidebarStat(label: "ENABLED", value: "\(enabledModels)")
                        ModelSidebarStat(label: "FREE TIER", value: "\(freeModels)")
                        ModelSidebarStat(label: "PROVIDERS", value: "\(store.config.providers.count)")
                    }

                    DividerLine().opacity(0.7)

                    HStack(spacing: 7) {
                        Button("Add model") {
                            store.showAddModel = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(store.config.providers.isEmpty)

                        Button("Providers") {
                            withAnimation(.snappy(duration: 0.22)) {
                                store.section = .providers
                            }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }

            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("HOW ROUTING USES MODELS")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.faint)

                    ModelNoteRow(symbol: "switch.2", title: "Enabled only", detail: "Disabled models are removed from every candidate list.")
                    ModelNoteRow(symbol: "text.alignleft", title: "Context headroom", detail: "More remaining context improves the fit score.")
                    ModelNoteRow(symbol: "tag.fill", title: "Price and free tier", detail: "Free models win when cost weight is high.")

                    DividerLine().opacity(0.7)

                    Text("Add exact upstream model IDs; routing will only choose from this catalog.")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ModelSidebarStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.stroke, lineWidth: 0.8))
    }
}

private struct ModelNoteRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 13)
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
