import XCTest
@testable import WehniRouteCore

final class LocalEngineTests: XCTestCase {
    func testAllNewLocalEnginesAreFlaggedLocal() {
        let expected: [ProviderKind] = [
            .jan, .gpt4all, .koboldcpp, .textgenwebui, .tabbyapi, .llamacpp,
            .llamafile, .localai, .tgi, .mlxlm, .vllm, .llamacpppython,
            .sglang, .mistralrs, .xinference, .dockermodelrunner, .lemonade, .litellm,
        ]
        for kind in expected {
            XCTAssertTrue(kind.isLocal, "\(kind.rawValue) must be local")
            XCTAssertEqual(kind.defaultInputPrice, 0, "\(kind.rawValue) is free")
            XCTAssertEqual(kind.defaultOutputPrice, 0, "\(kind.rawValue) is free")
            XCTAssertTrue(kind.defaultModelIsFree, "\(kind.rawValue) default model is free")
            if kind == .tabbyapi {
                XCTAssertTrue(kind.requiresKey, "tabbyapi enforces auth by default")
            } else {
                XCTAssertFalse(kind.requiresKey, "\(kind.rawValue) must not require a key")
            }
        }
        // 18 new engines + ollama + lmstudio. Simulation is deliberately NOT
        // in localEngines: its request path is synthetic, not a loopback API.
        XCTAssertEqual(ProviderKind.localEngines.count, expected.count + 2)
        XCTAssertTrue(ProviderKind.simulation.isLocal, "simulation stays local")
        XCTAssertFalse(ProviderKind.localEngines.contains(.simulation))
    }

    func testDefaultBaseURLsUseLoopback() {
        XCTAssertEqual(ProviderKind.jan.defaultBaseURL, "http://127.0.0.1:1337/v1")
        XCTAssertEqual(ProviderKind.gpt4all.defaultBaseURL, "http://127.0.0.1:4891/v1")
        XCTAssertEqual(ProviderKind.koboldcpp.defaultBaseURL, "http://127.0.0.1:5001/v1")
        XCTAssertEqual(ProviderKind.textgenwebui.defaultBaseURL, "http://127.0.0.1:5000/v1")
        XCTAssertEqual(ProviderKind.tabbyapi.defaultBaseURL, "http://127.0.0.1:5000/v1")
        XCTAssertEqual(ProviderKind.llamacpp.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.llamafile.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.localai.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.tgi.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.mlxlm.defaultBaseURL, "http://127.0.0.1:8080/v1")
        XCTAssertEqual(ProviderKind.vllm.defaultBaseURL, "http://127.0.0.1:8000/v1")
        XCTAssertEqual(ProviderKind.llamacpppython.defaultBaseURL, "http://127.0.0.1:8000/v1")
        XCTAssertEqual(ProviderKind.sglang.defaultBaseURL, "http://127.0.0.1:30000/v1")
        XCTAssertEqual(ProviderKind.mistralrs.defaultBaseURL, "http://127.0.0.1:1234/v1")
        XCTAssertEqual(ProviderKind.xinference.defaultBaseURL, "http://127.0.0.1:9997/v1")
        XCTAssertEqual(ProviderKind.dockermodelrunner.defaultBaseURL, "http://127.0.0.1:12434/engines/v1")
        XCTAssertEqual(ProviderKind.lemonade.defaultBaseURL, "http://127.0.0.1:13305/api/v1")
        XCTAssertEqual(ProviderKind.litellm.defaultBaseURL, "http://127.0.0.1:4000/v1")
    }

    func testDefaultModelIsEmptyLikeLMStudio() {
        for kind in ProviderKind.localEngines where kind != .ollama {
            XCTAssertEqual(kind.defaultModel, "", "\(kind.rawValue) discovers its catalog; no hardcoded model")
        }
    }

    func testRawValuesAreStableAndLowercase() {
        for kind in ProviderKind.localEngines {
            XCTAssertEqual(kind.rawValue, kind.rawValue.lowercased())
            XCTAssertFalse(kind.rawValue.contains(" "), "\(kind.rawValue) must not contain spaces")
            XCTAssertFalse(kind.rawValue.contains("-"), "\(kind.rawValue) must not contain hyphens")
        }
    }

    func testParseCatalogTreatsEveryLocalEngineAsFreeLocal() {
        let body: JSONValue = .object([
            "data": .array([
                .object(["id": .string("qwen2.5-7b-instruct"), "context_length": .num(32768)]),
                .object(["id": .string("llama-3.2-1b")]),
            ])
        ])
        for kind in [ProviderKind.jan, .koboldcpp, .vllm, .mlxlm, .tgi, .localai, .sglang, .litellm, .dockermodelrunner, .lemonade] {
            let provider = ProviderConfig(kind: kind)
            let parsed = ProviderClient.parseCatalogForTesting(body, provider: provider)
            XCTAssertEqual(parsed.count, 2, "\(kind.rawValue) parses both entries")
            XCTAssertTrue(parsed.allSatisfy { $0.tier == .free }, "\(kind.rawValue) models are free")
            // parseCatalog sorts alphabetically, so look models up by ID.
            XCTAssertEqual(parsed.first { $0.modelID == "qwen2.5-7b-instruct" }?.contextWindow, 32768, "\(kind.rawValue) honors context_length")
            XCTAssertEqual(parsed.first { $0.modelID == "llama-3.2-1b" }?.contextWindow, kind.defaultContextWindow, "\(kind.rawValue) falls back to default context")
        }
    }
}
