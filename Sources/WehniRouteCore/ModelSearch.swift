import Foundation

/// One ranked match from `ModelSearch`. `provider` travels with the model so
/// the UI can group results without a second lookup.
public struct ModelSearchResult: Identifiable, Sendable {
    public let model: ModelConfig
    public let provider: ProviderConfig
    public let score: Int

    public var id: UUID { model.id }

    public init(model: ModelConfig, provider: ProviderConfig, score: Int) {
        self.model = model
        self.provider = provider
        self.score = score
    }
}

/// Pure, dependency-free model search. Used by the Models tab and testable on
/// its own: no SwiftUI, no store, no network.
public enum ModelSearch {
    /// Lowercased whitespace-separated tokens with empties dropped.
    public static func tokenize(_ query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Case- and diacritic-folded form used for exact/prefix ranking. Matching
    /// itself uses `localizedStandardContains`, which compares the same way.
    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    /// Everything the query is compared against, including the virtual
    /// `free` / `paid` / `local` keywords derived from the catalog entry.
    public static func haystack(
        model: ModelConfig,
        providerName: String,
        kind: ProviderKind
    ) -> String {
        var parts = [model.displayName, model.modelID, providerName, kind.displayName]
        if let note = model.tierNote, !note.isEmpty {
            parts.append(note)
        }
        parts.append(model.isFree ? "free" : "paid")
        if kind.isLocal {
            parts.append("local")
        }
        return parts.joined(separator: " ")
    }

    /// All tokens must match (AND), so `llama 70b` narrows rather than widens.
    /// A whitespace-only query matches everything.
    public static func matches(
        model: ModelConfig,
        providerName: String,
        kind: ProviderKind,
        query: String
    ) -> Bool {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return true }
        let haystack = haystack(model: model, providerName: providerName, kind: kind)
        return tokens.allSatisfy { haystack.localizedStandardContains($0) }
    }

    public static func matches(
        model: ModelConfig,
        provider: ProviderConfig,
        query: String
    ) -> Bool {
        matches(model: model, providerName: provider.name, kind: provider.kind, query: query)
    }

    /// Ranking tiers: exact `modelID` > `modelID` / `displayName` prefix >
    /// substring in the name > provider / kind / note / tier-keyword only.
    public static func score(
        model: ModelConfig,
        providerName: String,
        kind: ProviderKind,
        query: String
    ) -> Int {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return 0 }

        let modelID = normalize(model.modelID)
        let name = normalize(model.displayName)
        let full = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        var score = 0

        if !full.isEmpty {
            if full == modelID {
                score += 100
            } else if modelID.hasPrefix(full) {
                score += 60
            } else if name.hasPrefix(full) {
                score += 50
            } else if modelID.contains(full) {
                score += 40
            } else if name.contains(full) {
                score += 30
            }
        }

        for token in tokens {
            score += tokenScore(token, modelID: modelID, name: name)
        }

        // No name or ID token hit: the match came from the provider name,
        // kind, tier note, or a tier keyword.
        return score == 0 ? 1 : score
    }

    public static func score(
        model: ModelConfig,
        provider: ProviderConfig,
        query: String
    ) -> Int {
        score(model: model, providerName: provider.name, kind: provider.kind, query: query)
    }

    private static func tokenScore(_ token: String, modelID: String, name: String) -> Int {
        if token == modelID { return 40 }
        if token == name { return 36 }
        if modelID.hasPrefix(token) { return 30 }
        if name.hasPrefix(token) { return 26 }
        if name.contains(token) { return 20 }
        if modelID.contains(token) { return 18 }
        return 0
    }

    /// Ranked, de-duplicated matches. Ties keep the caller's display order, so
    /// the list is stable across renders.
    public static func results(
        query: String,
        models: [ModelConfig],
        providers: [ProviderConfig]
    ) -> [ModelSearchResult] {
        let lookup = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var ranked: [(index: Int, result: ModelSearchResult)] = []

        for (index, model) in models.enumerated() {
            guard seen.insert(model.id).inserted else { continue }
            guard let provider = lookup[model.providerID] else { continue }
            guard matches(model: model, provider: provider, query: query) else { continue }
            ranked.append((
                index,
                ModelSearchResult(
                    model: model,
                    provider: provider,
                    score: score(model: model, provider: provider, query: query)
                )
            ))
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.result.score != rhs.result.score {
                    return lhs.result.score > rhs.result.score
                }
                return lhs.index < rhs.index
            }
            .map(\.result)
    }
}
