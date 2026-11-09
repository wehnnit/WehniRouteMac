import XCTest
@testable import WehniRouteCore

final class ModelSearchTests: XCTestCase {
    private let anthropic = ProviderConfig(kind: .anthropic)
    private let ollama = ProviderConfig(kind: .ollama)

    private func model(
        provider: ProviderConfig,
        id: String,
        name: String = "",
        isFree: Bool = false,
        note: String? = nil
    ) -> ModelConfig {
        ModelConfig(
            providerID: provider.id,
            modelID: id,
            displayName: name,
            isFree: isFree,
            tierNote: note
        )
    }

    // MARK: - Tokenize

    func testTokenizeLowercasesAndDropsEmpties() {
        XCTAssertEqual(ModelSearch.tokenize("  GPT-4O   Llama "), ["gpt-4o", "llama"])
        XCTAssertEqual(ModelSearch.tokenize("   "), [])
        XCTAssertEqual(ModelSearch.tokenize(""), [])
    }

    // MARK: - Matching

    func testCaseInsensitiveMatch() {
        let entry = model(provider: anthropic, id: "gpt-4o", name: "GPT-4o")
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "GPT-4O"))
    }

    func testDiacriticInsensitiveMatch() {
        let entry = model(provider: anthropic, id: "m-large", name: "Mistrál Large")
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "mistral"))
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "MISTRAL"))
    }

    func testMultiTokenQueryRequiresEveryToken() {
        let big = model(provider: anthropic, id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B")
        let small = model(provider: anthropic, id: "llama-3.1-8b", name: "Llama 3.1 8B")

        XCTAssertTrue(ModelSearch.matches(model: big, provider: anthropic, query: "llama 70b"))
        XCTAssertFalse(ModelSearch.matches(model: small, provider: anthropic, query: "llama 70b"))
    }

    func testMatchesByModelID() {
        let entry = model(provider: anthropic, id: "claude-sonnet-4-5", name: "Claude Sonnet")
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "sonnet-4-5"))
    }

    func testMatchesByDisplayNameOnly() {
        let entry = model(provider: anthropic, id: "m1", name: "Claude Opus 4.5")
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "opus"))
    }

    func testMatchesByProviderName() {
        let entry = model(provider: anthropic, id: "some-model")
        XCTAssertTrue(ModelSearch.matches(model: entry, provider: anthropic, query: "anthropic"))
        XCTAssertFalse(ModelSearch.matches(model: entry, provider: anthropic, query: "ollama"))
    }

    func testTierKeywords() {
        let freeModel = model(provider: ollama, id: "llama3.1", isFree: true)
        let paidModel = model(provider: anthropic, id: "claude-sonnet-4-5", isFree: false)

        XCTAssertTrue(ModelSearch.matches(model: freeModel, provider: ollama, query: "free"))
        XCTAssertFalse(ModelSearch.matches(model: freeModel, provider: ollama, query: "paid"))
        XCTAssertTrue(ModelSearch.matches(model: paidModel, provider: anthropic, query: "paid"))
        XCTAssertFalse(ModelSearch.matches(model: paidModel, provider: anthropic, query: "free"))
    }

    func testLocalKeywordFollowsProviderKind() {
        let local = model(provider: ollama, id: "llama3.1", isFree: true)
        let remote = model(provider: anthropic, id: "claude-sonnet-4-5")

        XCTAssertTrue(ModelSearch.matches(model: local, provider: ollama, query: "local"))
        XCTAssertFalse(ModelSearch.matches(model: remote, provider: anthropic, query: "local"))
    }

    // MARK: - Results

    func testWhitespaceOnlyQueryReturnsEverythingInDisplayOrder() {
        let models = [
            model(provider: anthropic, id: "b-model"),
            model(provider: anthropic, id: "a-model"),
        ]
        let results = ModelSearch.results(query: "   ", models: models, providers: [anthropic])
        XCTAssertEqual(results.map(\.model.modelID), ["b-model", "a-model"])
    }

    func testNoMatchReturnsEmpty() {
        let models = [model(provider: anthropic, id: "claude-sonnet-4-5")]
        XCTAssertTrue(ModelSearch.results(query: "zzzz-not-here", models: models, providers: [anthropic]).isEmpty)
    }

    func testResultsAreDeduplicatedByModelIdentity() {
        let entry = model(provider: anthropic, id: "claude-sonnet-4-5")
        let results = ModelSearch.results(
            query: "claude",
            models: [entry, entry],
            providers: [anthropic]
        )
        XCTAssertEqual(results.count, 1)
    }

    func testModelsWithUnknownProvidersAreSkipped() {
        let models = [model(provider: anthropic, id: "claude-sonnet-4-5")]
        XCTAssertTrue(ModelSearch.results(query: "claude", models: models, providers: []).isEmpty)
    }

    // MARK: - Ranking

    func testExactModelIDBeatsNoteOnlyMatch() {
        let reseller = ProviderConfig(kind: .custom, id: "reseller", name: "GPT-4O Reseller")
        let exact = model(provider: anthropic, id: "gpt-4o", name: "GPT-4o")
        let noteOnly = model(
            provider: reseller,
            id: "resold-model",
            name: "Resold Model",
            note: "gpt-4o compatible weights"
        )

        let results = ModelSearch.results(
            query: "gpt-4o",
            models: [noteOnly, exact],
            providers: [reseller, anthropic]
        )

        XCTAssertEqual(results.first?.model.modelID, "gpt-4o")
        XCTAssertGreaterThan(results[0].score, results[1].score)
    }

    func testPrefixOutranksNameSubstring() {
        let prefixed = model(provider: anthropic, id: "gpt-4o-mini", name: "GPT-4o Mini")
        let midName = model(provider: anthropic, id: "m2", name: "Custom GPT-4o Tuned")

        let results = ModelSearch.results(
            query: "gpt-4o",
            models: [midName, prefixed],
            providers: [anthropic]
        )
        XCTAssertEqual(results.map(\.model.modelID), ["gpt-4o-mini", "m2"])
    }

    func testEqualScoresKeepDisplayOrder() {
        let first = model(provider: anthropic, id: "model-one", name: "Alpha Match")
        let second = model(provider: anthropic, id: "model-two", name: "Beta Match")

        let results = ModelSearch.results(
            query: "match",
            models: [first, second],
            providers: [anthropic]
        )
        XCTAssertEqual(results.map(\.model.modelID), ["model-one", "model-two"])
        XCTAssertEqual(results[0].score, results[1].score)
    }
}
