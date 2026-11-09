import Foundation
import SQLite3
import WehniRouteCore

// MARK: - Local model sources
//
// Tools that already hold model access on this machine — Ollama, LM Studio,
// Jan, llama.cpp, vLLM, Antigravity bridges, TalkNova, and a dozen more
// engines — can feed the router without the user copying anything. We detect
// them, adopt them as providers, and import their catalogs. Nothing here
// talks to the network beyond loopback, except TalkNova's own documented API
// with the user's stored key.

enum LocalSourceKind: String, Sendable, CaseIterable {
    case ollama
    case lmStudio = "lmstudio"
    case jan
    case gpt4all
    case koboldcpp
    case textgenwebui
    case tabbyapi
    case llamacpp
    case llamafile
    case localai
    case tgi
    case mlxlm
    case vllm
    case llamacpppython
    case sglang
    case mistralrs
    case xinference
    case dockermodelrunner
    case lemonade
    case litellm
    case antigravityBridge
    case talkNova

    var displayName: String {
        if kind == nil && self != .talkNova { return "Antigravity bridge" }
        if self == .talkNova { return "TalkNova" }
        return kind?.displayName ?? "Antigravity bridge"
    }

    /// The equivalent provider kind; nil for the two non-engine sources.
    var kind: ProviderKind? {
        switch self {
        case .antigravityBridge: return nil
        case .talkNova: return nil
        default: return ProviderKind(rawValue: rawValue)
        }
    }
}

struct LocalSourceCandidate: Identifiable, Sendable, Equatable {
    var id: String { "\(kind.rawValue):\(baseURL)" }
    var kind: LocalSourceKind
    var name: String
    var baseURL: String
    var apiKey: String?
    var detail: String
    /// True when this source is already a connected provider — the card then
    /// offers a catalog refresh instead of an add button.
    var connected: Bool = false
    var providerID: String?

    static func == (lhs: LocalSourceCandidate, rhs: LocalSourceCandidate) -> Bool {
        lhs.id == rhs.id && lhs.apiKey == rhs.apiKey && lhs.connected == rhs.connected
    }
}

enum LocalSourceScanner {
    /// Probes loopback endpoints and known installs. Every probe is bounded
    /// so a hung local server cannot wedge the scan.
    static func scan() async -> [LocalSourceCandidate] {
        async let engines = scanEngines()
        async let bridges = probeExtraBridgePorts()
        async let talkNova = probeTalkNova()
        return await (engines + bridges + talkNova)
    }

    /// Distinct ports that must be probed, with the specs interested in each.
    private static func portMap() -> [Int: [LocalEngineSpec]] {
        var byPort: [Int: [LocalEngineSpec]] = [:]
        for spec in LocalEngineCatalog.engines {
            for port in spec.ports {
                byPort[port, default: []].append(spec)
            }
        }
        return byPort
    }

    /// Probes every catalog engine on loopback, concurrently. Shared ports
    /// are probed once with all disambiguation paths and classified;
    /// unique ports need a single probe. TalkNova keeps its own probe
    /// (file + key based); the legacy Antigravity bridge ports keep theirs.
    private static func scanEngines() async -> [LocalSourceCandidate] {
        let byPort = portMap()
        // Probe every port concurrently; each port probes its paths
        // concurrently too. A dead port costs one timeout, not N.
        let results: [(port: Int, probes: [LocalProbeResult])] = await withTaskGroup(
            of: (Int, [LocalProbeResult]).self
        ) { group in
            for (port, specs) in byPort {
                let paths = Array(Set(specs.flatMap(\.detectionPaths))).sorted()
                group.addTask {
                    let probes = await withTaskGroup(of: LocalProbeResult.self) { inner in
                        for path in paths {
                            inner.addTask { await probePath(port: port, path: path) }
                        }
                        var collected: [LocalProbeResult] = []
                        for await probe in inner { collected.append(probe) }
                        return collected.sorted { $0.path < $1.path }
                    }
                    return (port, probes)
                }
            }
            var collected: [(Int, [LocalProbeResult])] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }
        }

        var found: [LocalSourceCandidate] = []
        for (port, probes) in results {
            guard probes.contains(where: \.isSuccess) else { continue }
            let specs = byPort[port] ?? []

            if specs.count == 1 {
                found.append(candidate(for: specs[0], port: port, probes: probes))
            } else if let kind = LocalEndpointClassifier.classify(port: port, probes: probes) {
                let spec = specs.first { $0.kind == kind } ?? specs[0]
                found.append(candidate(for: spec, port: port, probes: probes))
            } else if port == 8080 {
                // Unidentified OpenAI-compatible server on 8080: keep the
                // historical Antigravity-bridge behavior as the fallback.
                let models = probes.first { $0.path.hasSuffix("/models") }
                if let count = models?.json?["data"]?.arrayValue?.count, count > 0 {
                    found.append(LocalSourceCandidate(
                        kind: .antigravityBridge,
                        name: "Antigravity bridge",
                        baseURL: "http://127.0.0.1:8080/v1",
                        apiKey: nil,
                        detail: "Unidentified local server · \(count) model\(count == 1 ? "" : "s")"
                    ))
                }
            }
        }
        return found
    }

    /// The non-engine Antigravity bridge ports the previous scanner covered.
    /// These stay out of the engine catalog: they are community proxies, not
    /// inference engines, and adoption maps them to the `custom` kind.
    private static func probeExtraBridgePorts() async -> [LocalSourceCandidate] {
        let known: [(port: Int, name: String)] = [
            (8877, "antigravity-proxy"),
            (11435, "Antigravity local bridge"),
            (8045, "Antigravity Manager proxy"),
        ]
        let results = await withTaskGroup(of: LocalSourceCandidate?.self) { group in
            for entry in known {
                group.addTask {
                    let probe = await probePath(port: entry.port, path: "/v1/models")
                    guard let count = probe.json?["data"]?.arrayValue?.count else { return nil }
                    return LocalSourceCandidate(
                        kind: .antigravityBridge,
                        name: entry.name,
                        baseURL: "http://127.0.0.1:\(entry.port)/v1",
                        apiKey: nil,
                        detail: "Detected · \(count) model\(count == 1 ? "" : "s")"
                    )
                }
            }
            var collected: [LocalSourceCandidate] = []
            for await candidate in group {
                if let candidate { collected.append(candidate) }
            }
            return collected
        }
        return results
    }

    private static func probePath(port: Int, path: String) async -> LocalProbeResult {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            return LocalProbeResult(path: path)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return LocalProbeResult(path: path) }
        let status = http.statusCode
        let json = (200..<300).contains(status)
            ? (try? JSONDecoder().decode(JSONValue.self, from: data))
            : nil
        let text = json == nil && (200..<300).contains(status) ? String(data: data, encoding: .utf8) : nil
        return LocalProbeResult(path: path, status: status, json: json, text: text)
    }

    private static func candidate(for spec: LocalEngineSpec, port: Int, probes: [LocalProbeResult]) -> LocalSourceCandidate {
        let modelsProbe = probes.last { $0.path.hasSuffix("/models") || $0.path.hasSuffix("/api/tags") }
        let count = modelsProbe?.json?["data"]?.arrayValue?.count
            ?? modelsProbe?.json?["models"]?.arrayValue?.count
        let detail: String
        if let count, count > 0 {
            detail = "\(count) model\(count == 1 ? "" : "s") served"
        } else if modelsProbe?.isSuccess == true {
            detail = "server reachable"
        } else {
            detail = spec.blurb
        }
        // Rewrite the port when the engine answered on a non-primary port
        // (llama.cpp on 9931), keeping any path suffix from defaultBaseURL.
        var root = spec.kind.defaultBaseURL
        if let primary = spec.ports.first, port != primary,
           let range = root.range(of: ":\(primary)") {
            root.replaceSubrange(range, with: ":\(port)")
        }
        return LocalSourceCandidate(
            kind: LocalSourceKind(rawValue: spec.kind.rawValue) ?? .localai,
            name: spec.kind.displayName,
            baseURL: root,
            apiKey: nil,
            detail: detail
        )
    }

    private static func probeTalkNova() async -> [LocalSourceCandidate] {
        let installed = FileManager.default.fileExists(atPath: "/Applications/TalkNova.app")
        let key = await TalkNovaKeyReader.readStoredKey()
        guard installed || key != nil else { return [] }
        return [LocalSourceCandidate(
            kind: .talkNova,
            name: "TalkNova",
            baseURL: ProviderKind.talkNova.defaultBaseURL,
            apiKey: key,
            detail: key != nil
                ? "Installed · key detected — one click to connect"
                : "Installed · paste your key from TalkNova → Settings → API access"
        )]
    }
}

/// Reads the personal API key the TalkNova desktop app already stored on this
/// machine. The database is the user's own file (mode 0600, user-owned); we
/// only ever read the key the user themselves provisioned for API access.
enum TalkNovaKeyReader {
    static func readStoredKey() async -> String? {
        await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let db = home.appendingPathComponent("Library/Application Support/TalkNova/talknova.db")
            guard FileManager.default.fileExists(atPath: db.path) else { return nil }

            var handle: OpaquePointer?
            guard sqlite3_open_v2(db.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                return nil
            }
            defer { sqlite3_close(handle) }

            var statement: OpaquePointer?
            let query = "SELECT value FROM settings WHERE key = 'talknova_api_key' LIMIT 1"
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }

            if sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
                let value = String(cString: text)
                return value.hasPrefix("tn-") ? value : nil
            }
            return nil
        }.value
    }
}
