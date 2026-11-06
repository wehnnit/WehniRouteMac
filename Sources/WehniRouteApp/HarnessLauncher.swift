import AppKit
import Foundation
import SwiftUI

enum HarnessKind: String, CaseIterable, Identifiable {
    case claudeCode = "claude-code"
    case openCode = "opencode"
    case codex
    case hermes
    case pi
    case deepSeek = "deepseek"
    case talkNova = "talknova"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .openCode: return "OpenCode"
        case .codex: return "Codex"
        case .hermes: return "Hermes Agent"
        case .pi: return "Pi"
        case .deepSeek: return "DeepSeek Harness"
        case .talkNova: return "TalkNova"
        }
    }

    var command: String {
        switch self {
        case .claudeCode: return "claude"
        case .openCode: return "opencode"
        case .codex: return "codex"
        case .hermes: return "hermes"
        case .pi: return "pi"
        case .deepSeek: return "dsh"
        case .talkNova: return "TalkNova"
        }
    }

    var launcherCommand: String {
        switch self {
        case .claudeCode: return "claude-wehniroute"
        case .openCode: return "opencode-wehniroute"
        case .codex: return "codex-wehniroute"
        case .hermes: return "hermes-wehniroute"
        case .pi: return "pi-wehniroute"
        case .deepSeek: return "dsh-wehniroute"
        case .talkNova: return "talknova-wehniroute"
        }
    }

    var tagline: String {
        switch self {
        case .claudeCode: return "Anthropic Messages, routed locally"
        case .openCode: return "OpenCode with a generated provider"
        case .codex: return "Codex with an isolated config home"
        case .hermes: return "Hermes with a generated provider home"
        case .pi: return "Pi with a generated provider catalog"
        case .deepSeek: return "DeepSeek Harness, pointed at WehniRoute"
        case .talkNova: return "TalkNova desktop, routed locally"
        }
    }

    var protocolLabel: String {
        switch self {
        case .claudeCode: return "ANTHROPIC"
        case .codex: return "OPENAI · CHAT"
        default: return "OPENAI · CHAT"
        }
    }

    var launchArguments: [String] {
        switch self {
        case .hermes: return ["--provider", "wehni", "-m", "auto"]
        case .pi: return ["--provider", "wehni", "--model", "auto"]
        case .deepSeek: return ["web"]
        default: return []
        }
    }

    var symbol: String {
        switch self {
        case .claudeCode: return "text.bubble.fill"
        case .openCode: return "chevron.left.forwardslash.chevron.right"
        case .codex: return "terminal.fill"
        case .hermes: return "bolt.horizontal.circle.fill"
        case .pi: return "function"
        case .deepSeek: return "wave.3.right"
        case .talkNova: return "bubble.left.and.bubble.right.fill"
        }
    }

    var accent: Color {
        switch self {
        case .claudeCode: return Theme.amber
        case .openCode: return Theme.accent
        case .codex: return Theme.violet
        case .hermes: return Theme.blue
        case .pi: return Theme.green
        case .deepSeek: return Theme.rose
        case .talkNova: return Color(hex: 0x38BDF8)
        }
    }

    var installCommand: String {
        switch self {
        case .claudeCode:
            return "npm install -g @anthropic-ai/claude-code"
        case .openCode:
            return "curl -fsSL https://opencode.ai/install | bash"
        case .codex:
            return "npm install -g @openai/codex"
        case .hermes:
            return "curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
        case .pi:
            return "curl -fsSL https://pi.dev/install.sh | sh"
        case .deepSeek:
            return "npm install -g @deepseek-ai/dsh"
        case .talkNova:
            return "Install TalkNova.app in /Applications (talknova.site)"
        }
    }

    var docsURL: URL {
        switch self {
        case .claudeCode:
            return URL(string: "https://code.claude.com/docs/en/llm-gateway-connect")!
        case .openCode:
            return URL(string: "https://opencode.ai/docs/providers")!
        case .codex:
            return URL(string: "https://developers.openai.com/codex/config")!
        case .hermes:
            return URL(string: "https://hermes-agent.nousresearch.com/docs/getting-started/quickstart")!
        case .pi:
            return URL(string: "https://pi.dev/docs/latest/models")!
        case .deepSeek:
            return URL(string: "https://github.com/deepseek-ai/deepseek-harness")!
        case .talkNova:
            return URL(string: "https://talknova.site")!
        }
    }

    var setupNote: String {
        switch self {
        case .claudeCode:
            return "WehniRoute sets ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN. Claude Code appends /v1/messages itself, so the base URL has no /v1 suffix."
        case .openCode:
            return "WehniRoute writes an isolated opencode.json into a dedicated launch workspace using OpenCode's documented custom-provider shape. OpenCode 2.0.26 does not currently register custom providers in its server runtime, so the card may launch without exposing the generated model until that upstream bug is fixed."
        case .codex:
            return "WehniRoute writes an isolated CODEX_HOME config that uses WehniRoute as a chat-completions provider. Codex is not exercised by the app's local QA."
        case .hermes:
            return "Hermes resolves providers from config.yaml, so WehniRoute writes an isolated HERMES_HOME with a wehni provider and starts Hermes with provider wehni and model auto. Your ~/.hermes config is untouched."
        case .pi:
            return "WehniRoute writes a per-launch Pi agent directory with a wehni provider catalog and points PI_CODING_AGENT_DIR at it. Your ~/.pi config is untouched."
        case .deepSeek:
            return "WehniRoute exports DEEPSEEK_BASE_URL and DEEPSEEK_API_KEY, then opens the DeepSeek Harness web profile. The gateway accepts endpoint paths with or without the /v1 prefix, so dsh connects either way; pick the DeepSeek provider if dsh asks."
        case .talkNova:
            return "TalkNova's desktop client is hardwired to its own cloud service, so WehniRoute cannot capture its chat traffic. Launch here simply opens the app. To actually route TalkNova models through WehniRoute, connect TalkNova as a provider: copy your personal tn-live key from TalkNova → Settings → API access, then use Connect provider → TalkNova. TalkNova's catalog then joins the routing ladder for every other harness."
        }
    }
}

struct HarnessLaunchSpec {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?
}

private enum HarnessLaunchError: LocalizedError {
    case notInstalled(String)
    case gatewayOffline
    case interceptorUnavailable

    var errorDescription: String? {
        switch self {
        case .notInstalled(let command):
            return "Install \(command) first, then refresh the harness list."
        case .gatewayOffline:
            return "Start the WehniRoute gateway before launching a harness."
        case .interceptorUnavailable:
            return "The TalkNova interception proxy could not start. Check that /usr/bin/openssl is available and try again."
        }
    }
}

@MainActor
final class HarnessLauncher: ObservableObject {
    @Published private(set) var detected: [HarnessKind: String] = [:]
    @Published private(set) var installedCommands: Set<HarnessKind> = []
    @Published private(set) var refreshing = false

    func isInstalled(_ harness: HarnessKind) -> Bool {
        detected[harness] != nil
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let found = await withTaskGroup(
            of: (HarnessKind, String?).self,
            returning: [HarnessKind: String].self
        ) { group in
            for harness in HarnessKind.allCases {
                group.addTask {
                    (harness, await Self.resolve(harness))
                }
            }
            var results: [HarnessKind: String] = [:]
            for await (harness, path) in group {
                if let path {
                    results[harness] = path
                }
            }
            return results
        }
        detected = found
        refreshCommandStatus()
        refreshing = false
    }

    func launch(_ harness: HarnessKind, store: AppStore) {
        do {
            guard isInstalled(harness) else {
                throw HarnessLaunchError.notInstalled(harness.command)
            }
            if !store.gatewayStatus.isRunning {
                store.startGateway()
            }
            guard store.gatewayStatus.isRunning else {
                throw HarnessLaunchError.gatewayOffline
            }

            let script = try makeScript(for: harness, store: store)
            try openInTerminal(script)
            store.showToast("Opening \(harness.name) with WehniRoute", kind: .success)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.showToast(message, kind: .error)
        }
    }

    func copyLaunchCommand(_ harness: HarnessKind, store: AppStore) {
        do {
            _ = try makeScript(for: harness, store: store)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(terminalCommand(for: harness), forType: .string)
            store.showToast("Launch command copied", kind: .success)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.showToast(message, kind: .error)
        }
    }

    func installCommands(store: AppStore) {
        let available = HarnessKind.allCases.filter { isInstalled($0) }
        guard !available.isEmpty else {
            store.showToast("Install a harness CLI first, then refresh this list.", kind: .error)
            return
        }

        do {
            let bin = commandURL(for: .claudeCode).deletingLastPathComponent()
            try ensureDirectory(bin)
            for harness in available {
                let script = try makeScript(for: harness, store: store)
                let wrapper = """
                #!/bin/zsh
                exec /bin/zsh \(shellQuote(script.path)) "$@"
                """
                let url = commandURL(for: harness)
                try writeFile(wrapper, to: url)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
            refreshCommandStatus()
            store.showToast("Installed \(available.count) commands in ~/.local/bin. Add that folder to PATH to run them by name.", kind: .success)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            store.showToast(message, kind: .error)
        }
    }

    func terminalCommand(for harness: HarnessKind) -> String {
        if installedCommands.contains(harness) {
            return harness.launcherCommand
        }
        return "/bin/zsh \(shellQuote(scriptPath(for: harness)))"
    }

    func commandURL(for harness: HarnessKind) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
            .appendingPathComponent(harness.launcherCommand)
    }

    func refreshCommandStatus() {
        installedCommands = Set(HarnessKind.allCases.filter {
            FileManager.default.isExecutableFile(atPath: commandURL(for: $0).path)
        })
    }

    func scriptPath(for harness: HarnessKind) -> String {
        let directory = (try? harnessDirectory()) ?? SupportDirectory.url.appendingPathComponent("harnesses", isDirectory: true)
        return directory.appendingPathComponent("\(harness.id).command").path
    }

    private func makeScript(for harness: HarnessKind, store: AppStore) throws -> URL {
        let directory = try harnessDirectory()
        let spec = try makeSpec(for: harness, store: store, directory: directory)
        let scriptURL = directory.appendingPathComponent("\(harness.id).command")

        let exports = spec.environment.keys.sorted().map { key in
            "export \(key)=\(shellQuote(spec.environment[key] ?? ""))"
        }.joined(separator: "\n")

        let command = ([spec.executable] + spec.arguments)
            .map(shellQuote)
            .joined(separator: " ")
        let workingDirectory = spec.workingDirectory.map { "cd \(shellQuote($0))\n" } ?? ""

        let body = """
        #!/bin/zsh
        set -euo pipefail

        \(exports)

        echo "WehniRoute · \(harness.name)"
        echo "Gateway · \(store.gatewayURL)"
        echo ""

        \(workingDirectory)exec \(command) "$@"
        """

        try body.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func makeSpec(for harness: HarnessKind, store: AppStore, directory: URL) throws -> HarnessLaunchSpec {
        let port = store.config.gatewayPort
        let base = "http://127.0.0.1:\(port)"
        let executable = detected[harness] ?? harness.command

        var environment: [String: String] = [
            "OPENAI_BASE_URL": "\(base)/v1",
            "OPENAI_API_KEY": store.gatewayAPIKey,
            "OPENAI_MODEL": "auto",
        ]
        let arguments = harness.launchArguments
        var workingDirectory: String?

        switch harness {
        case .claudeCode:
            environment = [
                "ANTHROPIC_BASE_URL": base,
                "ANTHROPIC_AUTH_TOKEN": store.gatewayAPIKey,
                "ANTHROPIC_MODEL": "auto",
                "ANTHROPIC_SMALL_FAST_MODEL": "auto",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "auto",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "auto",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "auto",
                "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
            ]

        case .openCode:
            let workspace = directory.appendingPathComponent("opencode-workspace", isDirectory: true)
            try ensureDirectory(workspace)
            let configURL = workspace.appendingPathComponent("opencode.json")
            let object: [String: Any] = [
                "$schema": "https://opencode.ai/config.json",
                "model": "wehni/auto",
                "provider": [
                    "wehni": [
                        "name": "WehniRoute",
                        "npm": "@ai-sdk/openai-compatible",
                        "options": [
                            "baseURL": "\(base)/v1",
                            "apiKey": store.gatewayAPIKey,
                        ],
                        "models": [
                            "auto": [
                                "name": "Auto (WehniRoute)",
                                "limit": ["context": 200_000, "output": 32_768],
                            ],
                        ],
                    ],
                ],
            ]
            try writeJSON(object, to: configURL)
            environment["OPENCODE_CONFIG"] = configURL.path
            environment["WEHNIROUTE_API_KEY"] = store.gatewayAPIKey
            workingDirectory = workspace.path

        case .codex:
            let home = directory.appendingPathComponent("codex-home", isDirectory: true)
            try ensureDirectory(home)
            let config = """
            model = "auto"
            model_provider = "wehni"

            [model_providers.wehni]
            name = "WehniRoute"
            base_url = "\(base)/v1"
            env_key = "OPENAI_API_KEY"
            wire_api = "chat"
            """
            try writeFile(config, to: home.appendingPathComponent("config.toml"))
            environment["CODEX_HOME"] = home.path

        case .hermes:
            let home = directory.appendingPathComponent("hermes-home", isDirectory: true)
            try ensureDirectory(home)
            let configURL = home.appendingPathComponent("config.yaml")
            let config = """
            model:
              provider: wehni
              default: auto

            providers:
              wehni:
                name: WehniRoute
                api: \(yamlScalar("\(base)/v1"))
                api_key: \(yamlScalar(store.gatewayAPIKey))
                default_model: auto
                models:
                  - auto
            toolsets:
              - hermes-cli
            """
            try writeFile(config, to: configURL)
            environment["HERMES_HOME"] = home.path
            environment["HERMES_CONFIG"] = configURL.path
            environment["HERMES_ENV"] = home.appendingPathComponent(".env").path
            environment["HERMES_MODEL"] = "auto"

        case .pi:
            let home = directory.appendingPathComponent("pi-agent", isDirectory: true)
            try ensureDirectory(home)
            let object: [String: Any] = [
                "$schema": "https://pi.dev/schemas/models.schema.json",
                "providers": [
                    "wehni": [
                        "name": "WehniRoute",
                        "baseUrl": "\(base)/v1",
                        "api": "openai-completions",
                        "apiKey": store.gatewayAPIKey,
                        "models": [
                            [
                                "id": "auto",
                                "name": "Auto (WehniRoute)",
                                "contextWindow": 200_000,
                                "maxTokens": 32_768,
                            ],
                        ],
                    ],
                ],
            ]
            try writeJSON(object, to: home.appendingPathComponent("models.json"))
            environment["PI_CODING_AGENT_DIR"] = home.path

        case .deepSeek:
            environment["DEEPSEEK_BASE_URL"] = base
            environment["DEEPSEEK_API_KEY"] = store.gatewayAPIKey
            environment["DEEPSEEK_MODEL"] = "auto"

        case .talkNova:
            // TalkNova's desktop client talks only to its own cloud; there is
            // no endpoint override to set. Launching here just opens the app.
            // The real integration is the TalkNova provider preset, which
            // routes its catalog through the gateway for other harnesses.
            break
        }

        return HarnessLaunchSpec(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
    }

    private func openInTerminal(_ script: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", script.path]
        try process.run()
    }

    private func harnessDirectory() throws -> URL {
        let directory = SupportDirectory.url.appendingPathComponent("harnesses", isDirectory: true)
        try ensureDirectory(directory)
        return directory
    }

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeFile(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func yamlScalar(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    nonisolated private static func resolve(_ harness: HarnessKind) async -> String? {
        // Desktop-app harnesses ship as .app bundles rather than PATH commands.
        if let binary = appBundleBinary(harness) {
            return binary
        }
        let command = harness.command
        // 1) Well-known install locations. A GUI app's login shell often lacks
        //    PATH entries that live in ~/.zshrc (interactive-only), so direct
        //    filesystem checks find CLIs that a bare `zsh -lc` cannot.
        if let direct = directMatch(command) {
            return direct
        }
        // 2) Login shell, then interactive shell, each with a timeout so a slow
        //    or blocking profile file cannot wedge the harness list.
        if let found = await shellResolve(command, login: true) {
            return found
        }
        return await shellResolve(command, login: false)
    }

    /// Returns the executable inside an installed desktop-app harness.
    nonisolated private static func appBundleBinary(_ harness: HarnessKind) -> String? {
        guard harness == .talkNova else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for directory in [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ] {
            let binary = directory
                .appendingPathComponent("TalkNova.app", isDirectory: true)
                .appendingPathComponent("Contents/MacOS/TalkNova")
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                return binary.path
            }
        }
        return nil
    }

    nonisolated private static func directMatch(_ command: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        directories.append(contentsOf: [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".opencode/bin").path,
            home.appendingPathComponent(".hermes/node/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".codex/bin").path,
            home.appendingPathComponent(".pi/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ])

        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            let candidate = (directory as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    nonisolated private static func shellResolve(_ command: String, login: Bool) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [login ? "-lc" : "-ic", "command -v \(command)"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return nil
            }

            // Bound the wait: profile files can block indefinitely.
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                return nil
            }
            guard process.terminationStatus == 0 else { return nil }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let lines = text
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Profile files may print noise; prefer a line that resolves to the
            // command itself.
            let match = lines.first { ($0 as NSString).lastPathComponent == command }
                ?? lines.first { $0.contains("/") }
            return match
        }.value
    }
}
