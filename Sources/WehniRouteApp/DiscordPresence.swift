import AppKit
import Darwin
import Foundation
import WehniRouteCore

// MARK: - Discord Rich Presence
//
// The Discord desktop client listens on a local Unix domain socket and speaks
// a small framed-JSON protocol: [opcode u32 LE][length u32 LE][JSON body].
// Handshake is opcode 0 with {"v":1,"client_id":…}; after that, SET_ACTIVITY
// frames (opcode 1) update the presence and opcode 3 pings must be echoed.
// Implemented directly over Darwin sockets — no third-party dependency.

enum DiscordOpCode: UInt32 {
    case handshake = 0
    case frame = 1
    case close = 2
    case ping = 3
    case pong = 4
}

enum DiscordIPCError: Error {
    case notConnected
    case malformedFrame
    case disconnected
}

/// Why a connection attempt ended — surfaced in Settings so the user gets an
/// actionable message instead of a silent "waiting" state.
enum DiscordConnectResult: Equatable {
    case connected
    case noDiscord
    case invalidClientID
    case failed(String)

    var message: String {
        switch self {
        case .connected:
            return "Connected to Discord"
        case .noDiscord:
            return "Discord desktop app not running — presence starts automatically when it opens"
        case .invalidClientID:
            return "Discord rejected the bundled application ID (error 4000) — reopen Discord and try again."
        case .failed(let detail):
            return detail
        }
    }
}

struct DiscordActivity {
    var details: String?          // what is happening: "Routing for Claude Code"
    var state: String?            // specifics: "gemini-2.5-flash · Google AI Studio"
    var startTimestamp: Date?     // elapsed timer
    var largeImageKey: String?
    var largeImageText: String?
    var smallImageKey: String?
    var smallImageText: String?
    var buttons: [(label: String, url: String)] = []
}

final class DiscordIPCConnection: @unchecked Sendable {
    private var fd: Int32 = -1
    private let lock = NSLock()
    private let readerLock = NSLock()
    private var reading = false

    var isReading: Bool {
        readerLock.lock(); defer { readerLock.unlock() }
        return reading
    }

    func setReading(_ value: Bool) {
        readerLock.lock(); defer { readerLock.unlock() }
        reading = value
    }

    static func socketCandidates() -> [String] {
        var candidates: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Discord's macOS client creates its socket in Application Support.
        for index in 0..<10 {
            candidates.append(home.appendingPathComponent("Library/Application Support/discord/discord-ipc-\(index)").path)
        }
        // The documented discovery order (Linux-style environments, WINE, etc.)
        let env = ProcessInfo.processInfo.environment
        for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
            if let base = env[key], !base.isEmpty {
                for index in 0..<3 {
                    candidates.append(URL(fileURLWithPath: base).appendingPathComponent("discord-ipc-\(index)").path)
                }
            }
        }
        for index in 0..<3 {
            candidates.append("/tmp/discord-ipc-\(index)")
        }
        return candidates
    }

    /// Performs the handshake and reports exactly why it failed, if it did.
    func connect(clientID: String) -> DiscordConnectResult {
        disconnect()
        // A leftover socket file from a previous session is common; only a
        // successful connect counts as "Discord is present".
        var sawSocket = false
        var lastFailure: String?
        for path in Self.socketCandidates() where FileManager.default.fileExists(atPath: path) {
            sawSocket = true
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { lastFailure = "socket() failed"; continue }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                close(fd)
                continue
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.copyBytes(from: bytes)
            }

            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else {
                lastFailure = "Discord IPC socket refused the connection"
                close(fd)
                continue
            }

            lock.lock()
            self.fd = fd
            lock.unlock()

            let handshake = """
            {"v":1,"client_id":"\(clientID)"}
            """
            guard send(.handshake, handshake.data(using: .utf8) ?? Data()) else {
                lastFailure = "Discord IPC dropped the handshake write"
                disconnect()
                continue
            }
            // Wait briefly for the READY frame, or for a CLOSE explaining why.
            if let reply = readFrame(timeout: 3) {
                if reply.op == .frame {
                    return .connected
                }
                if reply.op == .close {
                    let decoded = (try? JSONDecoder().decode(JSONValue.self, from: reply.payload))
                    let code = decoded?["code"]?.intValue
                    disconnect()
                    // 4000 = invalid payload / client id rejected by Discord.
                    if code == 4000 { return .invalidClientID }
                    lastFailure = "Discord closed the connection (code \(code ?? 0))"
                    continue
                }
            }
            lastFailure = "Discord did not answer the handshake in time"
            disconnect()
        }
        // A socket on disk that never answers is Discord still starting up, not
        // an absent Discord — say so, because the fix is to wait, not to launch it.
        if sawSocket, let lastFailure {
            return .failed(lastFailure + " — retrying")
        }
        return .noDiscord
    }

    func send(_ op: DiscordOpCode, _ payload: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return false }
        var header = Data()
        var opcode = op.rawValue.littleEndian
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &opcode) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        var frame = header + payload
        return frame.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.send(fd, base.advanced(by: offset), buffer.count - offset, 0)
                if sent <= 0 { return false }
                offset += sent
            }
            return true
        }
    }

    /// Blocking read of one frame; nil on timeout or disconnect.
    func readFrame(timeout: TimeInterval) -> (op: DiscordOpCode, payload: Data)? {
        lock.lock()
        let fd = self.fd
        lock.unlock()
        guard fd >= 0 else { return nil }

        var timeoutValue = timeval(tv_sec: time_t(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, socklen_t(MemoryLayout<timeval>.size))

        func readExact(_ count: Int) -> Data? {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: count)
            while data.count < count {
                let n = Darwin.recv(fd, &buffer, count - data.count, 0)
                if n <= 0 { return nil }
                data.append(contentsOf: buffer[0..<n])
            }
            return data
        }

        guard let header = readExact(8) else { return nil }
        let op = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        let length = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian }
        guard let opCode = DiscordOpCode(rawValue: op), length <= 64_000,
              let payload = readExact(Int(length))
        else { return nil }
        return (opCode, payload)
    }

    func disconnect() {
        lock.lock()
        let fd = self.fd
        self.fd = -1
        lock.unlock()
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }
}

/// Owns the connection lifecycle and translates routing activity into a
/// presence payload. All presence content is deliberately non-secret:
/// harness name, model ID, provider name — never keys or prompts.
@MainActor
final class DiscordPresenceManager: ObservableObject {
    enum PresenceState: Equatable {
        case disabled
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: PresenceState = .disconnected
    /// Human-readable reason for the current (non-connected) state.
    @Published private(set) var statusMessage: String = "Looking for Discord…"
    /// Exactly what Discord last acknowledged — shown in Settings for verification.
    @Published private(set) var lastSentSummary: String = ""

    /// WehniRoute's registered Discord application. Public by design: presence
    /// needs no user configuration, so this ships in the app.
    static let defaultClientID = "1568760703609868408"
    private static let discordBundleID = "com.hnc.Discord"

    private let connection = DiscordIPCConnection()
    private let ioQueue = DispatchQueue(label: "com.wehnnit.WehniRoute.discord-io", qos: .utility)
    private var clientID: String?
    private var lastSignature: String?
    private var retryLoop: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastActivity: DiscordActivity?

    /// Presence is always on. Starts immediately, retries fast while Discord is
    /// absent, and links up the instant Discord launches.
    func start(clientID: String) {
        let newClientID = clientID.isEmpty ? Self.defaultClientID : clientID
        let idChanged = newClientID != self.clientID
        self.clientID = newClientID
        if idChanged {
            connection.disconnect()
            state = .disconnected
            lastSignature = nil
        }
        observeDiscordLifecycle()
        startRetryLoop(clientID: newClientID)
    }

    /// Reconnects the moment Discord appears, instead of waiting for a poll.
    private func observeDiscordLifecycle() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.discordBundleID
                else { return }
                Task { @MainActor in
                    Self.log("Discord launched — connecting immediately")
                    self?.connectNow()
                }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.discordBundleID
                else { return }
                Task { @MainActor in
                    guard let self else { return }
                    Self.log("Discord quit — waiting for it to reopen")
                    self.connection.disconnect()
                    self.state = .disconnected
                    self.statusMessage = DiscordConnectResult.noDiscord.message
                }
            }
        )
    }

    /// Attempts a handshake immediately (used on launch notification).
    private func connectNow() {
        guard let clientID, state != .connecting else { return }
        Task { await self.attemptConnect(clientID: clientID) }
    }

    /// Polls while disconnected so a missed notification still self-heals, and
    /// idles while connected (the socket reader owns liveness then).
    private func startRetryLoop(clientID: String) {
        retryLoop?.cancel()
        retryLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await self.state != .connected {
                    await self.attemptConnect(clientID: clientID)
                    // Fast retry: a fresh connection usually succeeds immediately.
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    /// Presence log appends are serialized on a utility queue so a slow disk
    /// never stalls the UI.
    private nonisolated static let logQueue = DispatchQueue(
        label: "com.wehnnit.WehniRoute.presence-log",
        qos: .utility
    )

    private nonisolated static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) presence: \(message)\n"
        logQueue.async {
            try? SupportDirectory.ensureExists()
            let url = SupportDirectory.url.appendingPathComponent("presence.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }

    private func attemptConnect(clientID: String) async {
        if state != .connecting { state = .connecting }
        let connection = self.connection
        let result = await Task.detached(priority: .utility) { connection.connect(clientID: clientID) }.value
        switch result {
        case .connected:
            state = .connected
            statusMessage = DiscordConnectResult.connected.message
            Self.log("connected (client \(clientID))")
            startReader()
            if let activity = lastActivity { send(activity) }
        default:
            if statusMessage != result.message { Self.log(result.message) }
            state = .disconnected
            statusMessage = result.message
        }
    }

    /// Echoes Discord's pings so the connection stays alive; exits the read
    /// loop when the socket closes so the reconnect timer can take over.
    private func startReader() {
        guard !connection.isReading else { return }
        connection.setReading(true)
        let connection = self.connection
        Task.detached(priority: .utility) { [weak self] in
            defer {
                connection.setReading(false)
                let weakSelf = self
                Task {
                    await MainActor.run { weakSelf?.readingDidEnd() }
                }
            }
            while true {
                guard let frame = connection.readFrame(timeout: 30) else { break }
                if frame.op == .ping {
                    _ = connection.send(.pong, frame.payload)
                }
                if frame.op == .close { break }
            }
            guard let self else { return }
            await MainActor.run {
                self.state = .disconnected
                self.statusMessage = "Discord closed the connection — reconnecting"
            }
        }
    }

    fileprivate func readingDidEnd() {
        // Called on the main actor when the read loop exits.
    }

    /// Updates presence from a successful routing decision.
    /// Presence shown while a route is actively being served.
    func present(harness: String?, model: String?, provider: String?, fallback: Bool, sessionStart: Date) {
        let details = harness.map { "Routing for \($0)" } ?? "Routing model traffic"
        var stateText = [model, provider].compactMap { $0 }.joined(separator: " · ")
        if fallback { stateText = "↩ fallback · " + stateText }
        let activity = DiscordActivity(
            details: String(details.prefix(128)),
            state: String(stateText.prefix(128)),
            startTimestamp: sessionStart,
            largeImageKey: nil,
            largeImageText: nil,
            smallImageKey: nil,
            smallImageText: nil,
            buttons: Self.buttons
        )
        let signature = "\(activity.details ?? "")|\(activity.state ?? "")"
        guard signature != lastSignature else { return }
        lastSignature = signature
        lastActivity = activity
        send(activity)
    }

    /// Presence while you're simply using the app — always on, regardless of
    /// whether a harness is running. Mirrors the tab you're currently in.
    func presentSection(title: String, summary: String, sessionStart: Date) {
        let activity = DiscordActivity(
            details: String("In WehniRoute · \(title)".prefix(128)),
            state: String(summary.prefix(128)),
            startTimestamp: sessionStart,
            largeImageKey: nil,
            largeImageText: nil,
            smallImageKey: nil,
            smallImageText: nil,
            buttons: Self.buttons
        )
        let signature = "\(activity.details ?? "")|\(activity.state ?? "")"
        guard signature != lastSignature else { return }
        lastSignature = signature
        lastActivity = activity
        send(activity)
    }

    /// Shown when the window is in the background, still never blank.
    func presentAway(summary: String, sessionStart: Date) {
        let activity = DiscordActivity(
            details: "WehniRoute",
            state: String(("\(summary) · window in background").prefix(128)),
            startTimestamp: sessionStart,
            largeImageKey: nil,
            largeImageText: nil,
            smallImageKey: nil,
            smallImageText: nil,
            buttons: Self.buttons
        )
        let signature = "\(activity.details ?? "")|\(activity.state ?? "")"
        guard signature != lastSignature else { return }
        lastSignature = signature
        lastActivity = activity
        send(activity)
    }

    /// Discord renders the app icon + name automatically when no assets are
    /// supplied; unknown asset keys are silently dropped, so we send none.
    private static let buttons: [(label: String, url: String)] = [
        ("Get WehniRoute", "https://wehniroute.wehnit-studios.workers.dev"),
        ("GitHub", "https://github.com/wehnnit/WehniRouteMac"),
    ]

    func clearActivity() {
        lastActivity = nil
        lastSignature = nil
        guard state == .connected else { return }
        let payload: [String: Any] = ["cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
        let connection = self.connection
        ioQueue.async {
            _ = connection.send(.frame, data)
        }
    }

    func send(_ activity: DiscordActivity) {
        // Queue while the socket is down: connect() replays lastActivity.
        guard state == .connected else { return }
        var args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        var body: [String: Any] = [:]
        if let details = activity.details { body["details"] = details }
        if let state = activity.state { body["state"] = state }
        if let start = activity.startTimestamp {
            body["timestamps"] = ["start": Int(start.timeIntervalSince1970)]
        }
        var assets: [String: Any] = [:]
        if let key = activity.largeImageKey { assets["large_image"] = key }
        if let text = activity.largeImageText { assets["large_text"] = text }
        if let key = activity.smallImageKey { assets["small_image"] = key }
        if let text = activity.smallImageText { assets["small_text"] = text }
        if !assets.isEmpty { body["assets"] = assets }
        if !activity.buttons.isEmpty {
            body["buttons"] = activity.buttons.map { ["label": $0.label, "url": $0.url] }
        }
        body["instance"] = false
        args["activity"] = body

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": args,
            "nonce": UUID().uuidString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }

        let connection = self.connection
        let detail = activity.details ?? "-"
        let stateText = activity.state ?? "-"
        let summary = "\(activity.details ?? "") — \(activity.state ?? "")"
        ioQueue.async { [weak self] in
            let ok = connection.send(.frame, data)
            Self.log("\(ok ? "sent" : "failed") activity: \(detail) | \(stateText)")
            guard ok else { return }
            Task { @MainActor [weak self] in
                self?.lastSentSummary = summary
            }
        }
    }
}
