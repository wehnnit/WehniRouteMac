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

    func testUniquePortsMapDirectlyToKinds() {
        let expectations: [Int: ProviderKind] = [
            1337: .jan, 4891: .gpt4all, 5001: .koboldcpp, 30000: .sglang,
            9997: .xinference, 12434: .dockermodelrunner, 13305: .lemonade,
            4000: .litellm, 11434: .ollama,
        ]
        for (port, kind) in expectations {
            let probes = [LocalProbeResult(path: "/v1/models", status: 200,
                                           json: .object(["data": .array([.object(["id": .string("m")])])]))]
            XCTAssertEqual(LocalEndpointClassifier.classify(port: port, probes: probes), kind)
        }
    }

    func testLLamaCppIsDiscoveredOnBoth8080And9931() {
        let okHealth = LocalProbeResult(path: "/health", status: 200,
                                        json: .object(["status": .string("ok")]))
        XCTAssertEqual(LocalEndpointClassifier.classify(port: 8080, probes: [okHealth]), .llamacpp)
        XCTAssertEqual(LocalEndpointClassifier.classify(port: 9931, probes: [okHealth]), .llamacpp)
        XCTAssertEqual(LocalEngineCatalog.byPort(9931).map(\.kind), [.llamacpp])
    }

    func testPort8080Disambiguation() {
        func models(_ ids: [String]) -> LocalProbeResult {
            .init(path: "/v1/models", status: 200,
                  json: .object(["data": .array(ids.map { .object(["id": .string($0)]) })]))
        }
        // LocalAI answers /readyz
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8080, probes: [
                .init(path: "/readyz", status: 200, json: nil, text: "ok"), models(["gpt4all"]),
            ]),
            .localai
        )
        // TGI answers /health with an empty 200 body
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8080, probes: [
                .init(path: "/health", status: 200, json: nil, text: ""), models(["t5-small"]),
            ]),
            .tgi
        )
        // llama.cpp / llamafile answer /health with {"status":"ok"}
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8080, probes: [
                .init(path: "/health", status: 200, json: .object(["status": .string("ok")]), text: nil), models(["qwen"]),
            ]),
            .llamacpp
        )
        // MLX models betray the MLX server even on 8080
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8080, probes: [
                models(["mlx-community/Llama-3.2-1B-4bit"]),
            ]),
            .mlxlm
        )
        // Nothing identifiable → nil (the scanner keeps its Antigravity fallback)
        XCTAssertNil(LocalEndpointClassifier.classify(port: 8080, probes: [
            .init(path: "/health", status: 404, json: nil, text: nil),
            .init(path: "/v1/models", status: 404, json: nil, text: nil),
        ]))
    }

    func testPort8000Disambiguation() {
        // vLLM exposes Prometheus metrics mentioning itself
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8000, probes: [
                .init(path: "/metrics", status: 200, json: nil, text: "# HELP vllm:num_requests_running vllm:foo\n"),
            ]),
            .vllm
        )
        // llama-cpp-python answers /health with {"status":"ok"}
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 8000, probes: [
                .init(path: "/health", status: 200, json: .object(["status": .string("ok")])),
            ]),
            .llamacpppython
        )
    }

    func testPort5000And1234Disambiguation() {
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 5000, probes: [
                .init(path: "/openapi.json", status: 200, json: .object(["info": .object(["title": .string("TabbyAPI")])])),
            ]),
            .tabbyapi
        )
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 5000, probes: [
                .init(path: "/openapi.json", status: 404, json: nil, text: nil),
                .init(path: "/v1/models", status: 200, json: .object(["data": .array([])])),
            ]),
            .textgenwebui
        )
        // LM Studio's own v0 API marks the real LM Studio on 1234
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 1234, probes: [
                .init(path: "/api/v0/models", status: 200, json: .object(["data": .array([])])),
            ]),
            .lmstudio
        )
        XCTAssertEqual(
            LocalEndpointClassifier.classify(port: 1234, probes: [
                .init(path: "/api/v0/models", status: 404, json: nil, text: nil),
                .init(path: "/v1/models", status: 200, json: .object(["data": .array([.object(["id": .string("m")])])])),
            ]),
            .mistralrs
        )
    }

    func testCatalogCoversEveryLocalEngine() {
        for kind in ProviderKind.localEngines {
            XCTAssertTrue(LocalEngineCatalog.engines.contains { $0.kind == kind },
                          "catalog missing \(kind.rawValue)")
        }
        // Shared ports return multiple candidate engines so the scanner probes
        // every disambiguation path.
        XCTAssertEqual(LocalEngineCatalog.byPort(8080).count, 5)
        XCTAssertEqual(LocalEngineCatalog.byPort(8000).count, 2)
        XCTAssertEqual(LocalEngineCatalog.byPort(5000).count, 2)
        XCTAssertEqual(LocalEngineCatalog.byPort(1234).count, 2)
    }
}
