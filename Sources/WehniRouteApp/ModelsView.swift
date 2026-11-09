import SwiftUI
import WehniRouteCore

struct ModelsView: View {
    @EnvironmentObject private var store: AppStore

    enum TierFilter: String, CaseIterable, Identifiable {
        case all, free, paid
        var id: String { rawValue }
    }
    @State private var tierFilter: TierFilter = .all
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var seenSearchToken = 0
    @State private var confirmDisableAll = false

    private var enabledModelCount: Int {
        store.config.models.filter(\.enabled).count
    }

    private var canDisableAll: Bool { enabledModelCount > 0 }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchActive: Bool { !trimmedQuery.isEmpty }

    /// The catalog narrowed by the tier picker; search runs inside this set so
    /// results never contradict the visible filter.
    private var visibleModels: [ModelConfig] {
        store.config.models.filter { model in
            switch tierFilter {
            case .all: return true
            case .free: return model.isFree
            case .paid: return !model.isFree
            }
        }
    }

    private var results: [ModelSearchResult] {
        ModelSearch.results(
            query: trimmedQuery,
            models: visibleModels,
            providers: store.config.providers
        )
    }

    private var resultProviderCount: Int {
        Set(results.map(\.provider.id)).count
    }

    private var idleProviderCount: Int {
        Set(visibleModels.map(\.providerID)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(
                eyebrow: "Model catalog",
                title: "Models",
                subtitle: "Expose only the models you want this router to consider. Every model carries its own context window, price, and free-tier flag."
            ) {
                Picker("Tier filter", selection: $tierFilter) {
                    Text("All").tag(TierFilter.all)
                    Text("Free").tag(TierFilter.free)
                    Text("Paid").tag(TierFilter.paid)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .labelsHidden()

                Button {
                    confirmDisableAll = true
                } label: {
                    Label("Disable all", systemImage: "minus.circle")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(!canDisableAll)
                .opacity(canDisableAll ? 1 : 0.45)
                .help(canDisableAll
                    ? "Turn off all \(enabledModelCount) enabled models"
                    : "Every model is already disabled")

                Button {
                    store.showAddModel = true
                } label: {
                    Label("Add model", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.config.providers.isEmpty)
                .opacity(store.config.providers.isEmpty ? 0.45 : 1)
            }

            filterBar

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
                    } else if searchActive {
                        if results.isEmpty {
                            searchEmptyState
                        } else {
                            searchResultsCard
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(store.config.providers) { provider in
                                ProviderModelSection(provider: provider, tierFilter: tierFilter)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ModelSidebar()
                    .frame(width: 292)
            }
        }
        .onAppear {
            // ⌘F may have fired before this tab was built, so consume the
            // token on first appearance as well as on later changes.
            if store.modelSearchToken != seenSearchToken {
                seenSearchToken = store.modelSearchToken
                searchFocused = true
            }
        }
        .onChange(of: store.modelSearchToken) { _, newValue in
            seenSearchToken = newValue
            searchFocused = true
        }
        .confirmationDialog(
            "Disable all \(enabledModelCount) enabled model\(enabledModelCount == 1 ? "" : "s")?",
            isPresented: $confirmDisableAll
        ) {
            Button("Disable all models", role: .destructive) {
                store.setAllModelsEnabled(false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Routing will have no candidates until you re-enable a model. Disabled models stay in the catalog and in search, so you can turn them back on individually.")
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(alignment: .center, spacing: 12) {
            searchField
            Spacer(minLength: 8)
            countLabel
        }
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.faint)

            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onExitCommand {
                    query = ""
                    searchFocused = false
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear model search")
            } else if !searchFocused {
                Text("⌘F")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.stroke, lineWidth: 0.8))
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 300, height: 30)
        .background(Capsule().fill(Color.black.opacity(0.18)))
        .overlay(
            Capsule().stroke(
                searchFocused ? Theme.accent.opacity(0.45) : Theme.stroke,
                lineWidth: 0.8
            )
        )
        .accessibilityLabel("Search models by name, ID, or provider")
    }

    private var countLabel: some View {
        Text(countText)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(searchActive ? Theme.accent : Theme.faint)
            .contentTransition(.numericText())
    }

    private var countText: String {
        if searchActive {
            let count = results.count
            let providers = resultProviderCount
            return "\(count) \(count == 1 ? "match" : "matches") in \(providers) \(providers == 1 ? "provider" : "providers")"
        }
        let count = visibleModels.count
        let providers = idleProviderCount
        return "\(count) \(count == 1 ? "model" : "models") · \(providers) \(providers == 1 ? "provider" : "providers")"
    }

    // MARK: - Search results

    private struct ResultGroup: Identifiable {
        let provider: ProviderConfig
        let results: [ModelSearchResult]
        var id: String { provider.id }
    }

    /// Ranked globally, then bucketed by provider. Group order follows each
    /// provider's best-ranked match; rows inside a group keep rank order.
    private var resultGroups: [ResultGroup] {
        var order: [String] = []
        var providers: [String: ProviderConfig] = [:]
        var buckets: [String: [ModelSearchResult]] = [:]

        for result in results {
            let id = result.provider.id
            if buckets[id] == nil {
                order.append(id)
                providers[id] = result.provider
                buckets[id] = []
            }
            buckets[id]?.append(result)
        }

        return order.compactMap { id in
            guard let provider = providers[id], let bucket = buckets[id] else { return nil }
            return ResultGroup(provider: provider, results: bucket)
        }
    }

    private var searchResultsCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(resultGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        DividerLine()
                    }
                    providerSubheading(group)
                    ForEach(group.results) { result in
                        ModelRow(model: result.model, query: trimmedQuery)
                        if result.id != group.results.last?.id {
                            DividerLine().padding(.leading, 56)
                        }
                    }
                }

                DividerLine()
                freeFootnote
            }
        }
    }

    private func providerSubheading(_ group: ResultGroup) -> some View {
        HStack(spacing: 8) {
            ProviderGlyph(kind: group.provider.kind, size: 20)
            Text(group.provider.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text("\(group.results.count)")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.faint)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.018))
    }

    private var freeFootnote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.faint)
                .padding(.top, 1)
            Text("Free flags come from the provider catalog at import time — a \"free tier\" note means rate-limited, not unlimited.")
                .font(.system(size: 9))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var searchEmptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.08)).frame(width: 56, height: 56)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                Text("No models match “\(trimmedQuery)”")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                Text("Search covers model names, IDs, providers, tiers, and notes. Try a shorter term, or add this ID to the catalog.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                HStack(spacing: 8) {
                    Button("Clear search") {
                        query = ""
                        searchFocused = false
                    }
                    .buttonStyle(GhostButtonStyle())

                    Button {
                        store.pendingModelID = trimmedQuery
                        store.showAddModel = true
                    } label: {
                        Label("Add \"\(trimmedQuery)\" as a model", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.config.providers.isEmpty)
                    .opacity(store.config.providers.isEmpty ? 0.45 : 1)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }
}

// MARK: - Match highlighting

private func highlightedMatch(
    _ text: String,
    query: String,
    size: CGFloat,
    design: Font.Design = .default
) -> AttributedString {
    var attributed = AttributedString(text)
    let tokens = ModelSearch.tokenize(query)
    guard !tokens.isEmpty else { return attributed }

    for token in tokens {
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart...].range(
                  of: token,
                  options: [.caseInsensitive, .diacriticInsensitive]
              ) {
            attributed[range].foregroundColor = Theme.accent
            attributed[range].font = .system(size: size, weight: .bold, design: design)
            if range.upperBound == attributed.endIndex { break }
            searchStart = range.upperBound
        }
    }
    return attributed
}

private struct ProviderModelSection: View {
    @EnvironmentObject private var store: AppStore
    let provider: ProviderConfig
    let tierFilter: ModelsView.TierFilter

    private var models: [ModelConfig] {
        store.models(for: provider.id).filter { model in
            switch tierFilter {
            case .all: return true
            case .free: return model.isFree
            case .paid: return !model.isFree
            }
        }
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
                            Image(systemName: tierFilter == .all ? "tray" : "line.3.horizontal.decrease.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.faint)
                            Text(tierFilter == .all
                                 ? "No models yet. Add one to make this provider eligible."
                                 : "No \(tierFilter == .free ? "free" : "paid") models in this provider.")
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
    var query: String = ""

    private var priceLabel: String {
        if model.isFree { return "Free" }
        guard let input = model.inputPerMillion, let output = model.outputPerMillion else {
            return "Price unset"
        }
        return "\(Format.money(input)) / \(Format.money(output)) M"
    }

    private var tierLabel: String {
        model.tierNote ?? priceLabel
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
                    Text(highlightedMatch(model.displayName, query: query, size: 11))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if model.isFree {
                        Pill(text: "FREE", tint: Theme.green)
                    } else {
                        Pill(text: "PAID", tint: Theme.blue)
                    }
                }
                Text(highlightedMatch(model.modelID, query: query, size: 9, design: .monospaced))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Format.compact(model.contextWindow)) context")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text(tierLabel)
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
