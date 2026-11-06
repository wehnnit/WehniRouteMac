import XCTest
@testable import WehniRouteCore

final class RouterTests: XCTestCase {
    private func config(providers: [ProviderConfig], models: [ModelConfig], strategy: Strategy = .auto, allowPaid: Bool = true) -> AppConfig {
        var config = AppConfig()
        config.providers = providers
        config.models = models
        config.routing.strategy = strategy
        config.routing.allowPaidModels = allowPaid
        config.routing.weights = .preset(for: strategy)
        return config
    }

    func testCodingStrategyPrefersClaudeForCode() {
        let anthropic = ProviderConfig(kind: .anthropic)
        let groq = ProviderConfig(kind: .groq)
        let models = [
            ModelConfig(providerID: anthropic.id, modelID: "claude-sonnet-4-5", contextWindow: 200_000, inputPerMillion: 3, outputPerMillion: 15),
            ModelConfig(providerID: groq.id, modelID: "llama-3.3-70b-versatile", contextWindow: 131_072, inputPerMillion: 0, outputPerMillion: 0, isFree: true),
        ]
        let ranked = Router.rank(
            config: config(providers: [anthropic, groq], models: models, strategy: .coding),
            health: [:],
            estimatedInputTokens: 1_200,
            task: .coding
        ).candidates

        XCTAssertEqual(ranked.first?.providerID, "anthropic")
        XCTAssertTrue(ranked.first?.reasons.contains { $0.contains("fit") } ?? false)
    }

    func testCheapStrategyPrefersFreeModel() {
        let anthropic = ProviderConfig(kind: .anthropic)
        let ollama = ProviderConfig(kind: .ollama)
        let models = [
            ModelConfig(providerID: anthropic.id, modelID: "claude-sonnet-4-5", contextWindow: 200_000, inputPerMillion: 3, outputPerMillion: 15),
            ModelConfig(providerID: ollama.id, modelID: "llama3.1", contextWindow: 131_072, inputPerMillion: 0, outputPerMillion: 0, isFree: true),
        ]
        let ranked = Router.rank(
            config: config(providers: [anthropic, ollama], models: models, strategy: .cheap),
            health: [:],
            estimatedInputTokens: 500,
            task: .unknown
        ).candidates

        XCTAssertEqual(ranked.first?.providerID, "ollama")
        XCTAssertTrue(ranked.first?.isFree ?? false)
    }

    func testUnhealthyProviderDropsBelowHealthyOne() {
        let anthropic = ProviderConfig(kind: .anthropic)
        let openai = ProviderConfig(kind: .openai)
        let models = [
            ModelConfig(providerID: anthropic.id, modelID: "claude-sonnet-4-5", contextWindow: 200_000, inputPerMillion: 3, outputPerMillion: 15),
            ModelConfig(providerID: openai.id, modelID: "gpt-4o-mini", contextWindow: 400_000, inputPerMillion: 0.15, outputPerMillion: 0.60),
        ]
        let health = [
            anthropic.id: HealthSnapshot(state: .degraded, consecutiveFailures: 3, avgLatencyMS: 4_000),
            openai.id: HealthSnapshot(state: .healthy, consecutiveFailures: 0, avgLatencyMS: 420),
        ]
        let ranked = Router.rank(
            config: config(providers: [anthropic, openai], models: models, strategy: .reliable),
            health: health,
            estimatedInputTokens: 800,
            task: .coding
        ).candidates

        XCTAssertEqual(ranked.first?.providerID, "openai")
    }

    func testContextOverflowIsRejectedWithReason() {
        let ollama = ProviderConfig(kind: .ollama)
        let model = ModelConfig(providerID: ollama.id, modelID: "tiny", contextWindow: 1_000, isFree: true)
        let result = Router.rank(
            config: config(providers: [ollama], models: [model]),
            health: [:],
            estimatedInputTokens: 5_000,
            task: .coding
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertEqual(result.rejected.first?.modelID, "tiny")
        XCTAssertTrue(result.rejected.first?.reason.contains("Context") ?? false)
    }

    func testPaidPolicyExcludesPaidModels() {
        let anthropic = ProviderConfig(kind: .anthropic)
        let model = ModelConfig(providerID: anthropic.id, modelID: "claude-sonnet-4-5", contextWindow: 200_000, inputPerMillion: 3, outputPerMillion: 15)
        let result = Router.rank(
            config: config(providers: [anthropic], models: [model], allowPaid: false),
            health: [:],
            estimatedInputTokens: 100,
            task: .writing
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.rejected.first?.reason.contains("Paid model") ?? false)
    }

    func testCoolingProviderIsRejected() {
        let openai = ProviderConfig(kind: .openai)
        let model = ModelConfig(providerID: openai.id, modelID: "gpt-4o-mini", contextWindow: 128_000, inputPerMillion: 0.15, outputPerMillion: 0.60)
        let health = [
            openai.id: HealthSnapshot(state: .down, consecutiveFailures: 4, cooldownUntil: Date().addingTimeInterval(60)),
        ]
        let result = Router.rank(
            config: config(providers: [openai], models: [model]),
            health: health,
            estimatedInputTokens: 100,
            task: .coding
        )

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.rejected.first?.reason.contains("Circuit open") ?? false)
    }

    func testRequestedModelGetsABoost() {
        let openai = ProviderConfig(kind: .openai)
        let groq = ProviderConfig(kind: .groq)
        let models = [
            ModelConfig(providerID: openai.id, modelID: "gpt-4o-mini", contextWindow: 128_000, inputPerMillion: 0.15, outputPerMillion: 0.60),
            ModelConfig(providerID: groq.id, modelID: "llama-3.3-70b-versatile", contextWindow: 131_072, isFree: true),
        ]
        let ranked = Router.rank(
            config: config(providers: [openai, groq], models: models, strategy: .fast),
            health: [:],
            estimatedInputTokens: 300,
            task: .fast,
            requestedModel: "gpt-4o-mini"
        ).candidates

        XCTAssertEqual(ranked.first?.modelID, "gpt-4o-mini")
        XCTAssertTrue(ranked.first?.reasons.contains("requested model") ?? false)
    }

    func testClassificationAndTokenEstimate() {
        let messages: [JSONValue] = [
            .object(["role": .string("user"), "content": .string("Please refactor this Swift function and fix the stack trace")]),
        ]
        XCTAssertEqual(Router.classify(messages: messages, tools: nil), .coding)
        XCTAssertGreaterThan(Router.estimateTokens(messages: messages), 5)

        let toolMessages: [JSONValue] = [.object(["role": .string("user"), "content": .string("hi")])]
        XCTAssertEqual(Router.classify(messages: toolMessages, tools: [.object([:])]), .coding)
    }

    func testConfigRoundTripAndDefaultModelSeeding() throws {
        var config = AppConfig()
        let provider = ProviderConfig(kind: .groq)
        config.providers.append(provider)
        config.addDefaultModel(for: provider)
        config.addDefaultModel(for: provider)

        XCTAssertEqual(config.models.filter { $0.providerID == provider.id }.count, 1)
        XCTAssertEqual(config.models.first?.modelID, "llama-3.3-70b-versatile")

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded.providers.first?.id, "groq")
        XCTAssertEqual(decoded.routing.strategy, .auto)
    }

    func testJSONValueRoundTripAndAccessors() throws {
        let value = JSONValue.object([
            "name": .string("WehniRoute"),
            "count": .number(3),
            "free": .bool(true),
            "items": .array([.null, .string("x")]),
        ])
        let decoded = try JSONDecoder().decode(JSONValue.self, from: value.jsonData)
        XCTAssertEqual(decoded["name"]?.stringValue, "WehniRoute")
        XCTAssertEqual(decoded["count"]?.intValue, 3)
        XCTAssertEqual(decoded["free"]?.boolValue, true)
        XCTAssertEqual(decoded["items"]?.arrayValue?.count, 2)
    }
}
