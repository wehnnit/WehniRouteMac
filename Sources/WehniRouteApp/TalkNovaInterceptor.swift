import Darwin
import Foundation
import Security
import WehniRouteCore

// MARK: - TalkNova interception
//
// TalkNova's desktop client hardwires its cloud endpoints at compile time, so it
// cannot be pointed at WehniRoute through configuration. Its backend, however,
// issues every HTTPS call through urllib.request.urlopen with the default
// opener and a TLS context that honors SSL_CERT_FILE. That means a launch
// environment can set HTTPS_PROXY + SSL_CERT_FILE, and a local loopback proxy
// can intercept only talknova.site: /v1/chat/completions and /v1/models are
// relayed to the WehniRoute gateway (so TalkNova's picker shows WehniRoute Auto
// and chat consumes no TalkNova usage), while every other talknova.site path —
// account, usage, login exchange — is relayed to the real service untouched.
// Other hosts tunnel blindly without TLS inspection.

enum TalkNovaProxyError: LocalizedError {
    case opensslFailed(String, Int32)
    case missingIdentity
    case p12ImportFailed(OSStatus)
    case tlsHandshakeFailed(OSStatus)
    case tlsClosed
    case cannotListen

    var errorDescription: String? {
        switch self {
        case .opensslFailed(let step, let status):
            return "Certificate generation failed (\(step), status \(status))."
        case .missingIdentity:
            return "TalkNova interception identity is missing."
        case .p12ImportFailed(let status):
            return "Could not import the interception identity (\(status))."
        case .tlsHandshakeFailed(let status):
            return "TalkNova TLS handshake failed (\(status))."
        case .tlsClosed:
            return "TalkNova TLS connection closed."
        case .cannotListen:
            return "Could not start the TalkNova interception proxy."
        }
    }
}

/// Generates and caches the local CA and the talknova.site leaf certificate.
/// The CA key never leaves Application Support (mode 0600).
enum TalkNovaCertAuthority {
    struct Material {
        let caBundleURL: URL
        let p12URL: URL
        let p12Passphrase: String
    }

    static var directory: URL {
        SupportDirectory.url.appendingPathComponent("talknova-proxy", isDirectory: true)
    }

    static var caBundleURL: URL { directory.appendingPathComponent("ca-bundle.pem") }

    static func ensure() throws -> Material {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let caKey = directory.appendingPathComponent("ca.key")
        let caCert = directory.appendingPathComponent("ca.pem")
        let leafKey = directory.appendingPathComponent("leaf.key")
        let leafCert = directory.appendingPathComponent("leaf.pem")
        let p12 = directory.appendingPathComponent("leaf.p12")
        let passphrase = "wehniroute-local"

        if !fm.fileExists(atPath: caCert.path) || !fm.fileExists(atPath: caKey.path) {
            try runOpenssl(
                "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-nodes",
                "-days", "3650",
                "-keyout", caKey.path, "-out", caCert.path,
                "-subj", "/CN=WehniRoute Local Intercept CA"
            )
        }

        if !fm.fileExists(atPath: leafCert.path) || !fm.fileExists(atPath: leafKey.path) || !fm.fileExists(atPath: p12.path) {
            let csr = directory.appendingPathComponent("leaf.csr")
            let ext = directory.appendingPathComponent("leaf.ext")
            try """
            subjectAltName=DNS:talknova.site
            basicConstraints=CA:FALSE
            keyUsage=digitalSignature,keyEncipherment
            extendedKeyUsage=serverAuth
            """.write(to: ext, atomically: true, encoding: .utf8)
            try runOpenssl(
                "req", "-new", "-newkey", "rsa:2048", "-sha256", "-nodes",
                "-keyout", leafKey.path, "-out", csr.path,
                "-subj", "/CN=talknova.site"
            )
            try runOpenssl(
                "x509", "-req", "-in", csr.path,
                "-CA", caCert.path, "-CAkey", caKey.path, "-CAcreateserial",
                "-days", "825", "-sha256",
                "-extfile", ext.path, "-out", leafCert.path
            )
            try runOpenssl(
                "pkcs12", "-export",
                "-inkey", leafKey.path, "-in", leafCert.path, "-certfile", caCert.path,
                "-out", p12.path,
                "-passout", "pass:\(passphrase)"
            )
            try? fm.removeItem(at: csr)
        }

        // SSL_CERT_FILE replaces TalkNova's trust store for urllib, so the
        // bundle must also carry the real roots: TalkNova bundles certifi, and
        // the system bundle is the fallback.
        let realBundle: String?
        let talkNovaCertifi = URL(fileURLWithPath: "/Applications/TalkNova.app/Contents/Resources/certifi/cacert.pem")
        if fm.fileExists(atPath: talkNovaCertifi.path) {
            realBundle = talkNovaCertifi.path
        } else if fm.fileExists(atPath: "/etc/ssl/cert.pem") {
            realBundle = "/etc/ssl/cert.pem"
        } else {
            realBundle = nil
        }

        if !fm.fileExists(atPath: caBundleURL.path) {
            var combined = try String(contentsOf: caCert, encoding: .utf8)
            if let realBundle, let roots = try? String(contentsOfFile: realBundle, encoding: .utf8) {
                combined += "\n" + roots
            }
            try combined.write(to: caBundleURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: caBundleURL.path)
        }

        for url in [caKey, leafKey, p12] {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }

        return Material(caBundleURL: caBundleURL, p12URL: p12, p12Passphrase: passphrase)
    }

    private static func runOpenssl(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TalkNovaProxyError.opensslFailed(detail.isEmpty ? arguments.joined(separator: " ") : detail, process.terminationStatus)
        }
    }
}

// MARK: - TLS over a raw socket (SecureTransport)

/// Blocking TLS wrapper around a POSIX socket. Server mode presents the
/// intercepted talknova.site identity; client mode uses system trust.
final class TLSConnection {
    enum Mode {
        case server(identity: SecIdentity)
        case client
    }

    private let fd: Int32
    private var context: SSLContext?
    private var ioState: TLSIOState?
    private(set) var handshakeComplete = false

    init(fd: Int32) {
        self.fd = fd
    }

    func handshake(mode: Mode) throws {
        let state = TLSIOState(fd: fd)
        ioState = state

        let context: SSLContext
        switch mode {
        case .server(let identity):
            guard let ctx = SSLCreateContext(nil, .serverSide, .streamType) else {
                throw TalkNovaProxyError.missingIdentity
            }
            SSLSetCertificate(ctx, [identity] as CFArray)
            context = ctx
        case .client:
            guard let ctx = SSLCreateContext(nil, .clientSide, .streamType) else {
                throw TalkNovaProxyError.missingIdentity
            }
            context = ctx
        }
        SSLSetIOFuncs(context, { connection, data, length in
            TLSIOState.readCallback(connection: connection, data: data, length: length)
        }, { connection, data, length in
            TLSIOState.writeCallback(connection: connection, data: data, length: length)
        })
        SSLSetConnection(context, state.connectionRef)
        self.context = context

        let deadline = Date().addingTimeInterval(20)
        while true {
            let status = SSLHandshake(context)
            if status == errSSLWouldBlock {
                if Date() > deadline { throw TalkNovaProxyError.tlsHandshakeFailed(status) }
                usleep(10_000)
                continue
            }
            guard status == noErr else { throw TalkNovaProxyError.tlsHandshakeFailed(status) }
            break
        }
        handshakeComplete = true
    }

    /// Returns bytes read; empty on graceful close. Blocks up to `idleTimeout`.
    func read(idleTimeout: TimeInterval = 30) throws -> Data {
        guard let context else { throw TalkNovaProxyError.missingIdentity }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let capacity = buffer.count
        let deadline = Date().addingTimeInterval(idleTimeout)
        while Date() < deadline {
            var processed: Int = 0
            let status = buffer.withUnsafeMutableBytes { pointer -> OSStatus in
                SSLRead(context, pointer.baseAddress!, capacity, &processed)
            }
            if status == noErr {
                if processed == 0 { continue }
                return Data(buffer[0..<processed])
            }
            if status == errSSLWouldBlock {
                if Date() > deadline { return Data() }
                continue
            }
            if status == errSSLClosedGraceful || status == errSSLClosedAbort { return Data() }
            throw TalkNovaProxyError.tlsHandshakeFailed(status)
        }
        return Data()
    }

    func write(_ data: Data) throws {
        guard let context else { throw TalkNovaProxyError.missingIdentity }
        var offset = 0
        while offset < data.count {
            var processed: Int = 0
            let status = data.withUnsafeBytes { pointer -> OSStatus in
                guard let base = pointer.baseAddress else { return errSecParam }
                return SSLWrite(context, base, data.count - offset, &processed)
            }
            if status == noErr {
                if processed == 0 { throw TalkNovaProxyError.tlsClosed }
                offset += processed
                continue
            }
            if status == errSSLWouldBlock {
                usleep(10_000)
                continue
            }
            throw TalkNovaProxyError.tlsHandshakeFailed(status)
        }
    }

    func close() {
        if let context {
            SSLClose(context)
        }
        context = nil
        ioState = nil
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}

/// Holds the fd and implements the SecureTransport IO callbacks.
private final class TLSIOState {
    let fd: Int32

    var connectionRef: SSLConnectionRef {
        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
    }

    init(fd: Int32) {
        self.fd = fd
    }

    static func readCallback(connection: SSLConnectionRef?, data: UnsafeMutableRawPointer?, length: UnsafeMutablePointer<Int>?) -> OSStatus {
        guard let connection, let data, let length else { return errSecParam }
        let state = Unmanaged<TLSIOState>.fromOpaque(UnsafeRawPointer(connection)).takeUnretainedValue()
        let requested = length.pointee
        let count = Darwin.recv(state.fd, data, requested, 0)
        if count > 0 {
            length.pointee = count
            return noErr
        }
        if count == 0 { return errSSLClosedGraceful }
        return errno == EAGAIN || errno == EWOULDBLOCK ? errSSLWouldBlock : errSSLClosedAbort
    }

    static func writeCallback(connection: SSLConnectionRef?, data: UnsafeRawPointer?, length: UnsafeMutablePointer<Int>?) -> OSStatus {
        guard let connection, let data, let length else { return errSecParam }
        let state = Unmanaged<TLSIOState>.fromOpaque(UnsafeRawPointer(connection)).takeUnretainedValue()
        let requested = length.pointee
        let count = Darwin.send(state.fd, data, requested, 0)
        if count >= 0 {
            length.pointee = count
            return count == 0 ? errSSLWouldBlock : noErr
        }
        return errno == EAGAIN || errno == EWOULDBLOCK ? errSSLWouldBlock : errSSLClosedAbort
    }
}

// MARK: - The intercept proxy

/// Loopback HTTP CONNECT proxy that MITMs talknova.site only.
final class TalkNovaInterceptor: @unchecked Sendable {
    private let stateLock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var identity: SecIdentity?
    private var gatewayPort = 20_128
    private var gatewayKey = ""
    private(set) var port: Int?

    func start() throws {
        stop()
        let material = try TalkNovaCertAuthority.ensure()
        identity = try Self.importIdentity(p12URL: material.p12URL, passphrase: material.p12Passphrase)

        var chosen: Int?
        for candidate in [20_129, 20_130, 20_131, 20_132, 20_133] {
            if let fd = Self.listenFD(port: UInt16(candidate)) {
                chosen = candidate
                stateLock.lock()
                listenFD = fd
                running = true
                stateLock.unlock()
                DispatchQueue(label: "com.wehnnit.WehniRoute.talknova-proxy", qos: .userInitiated).async { [weak self] in
                    self?.acceptLoop(fd)
                }
                break
            }
        }
        guard let bound = chosen else { throw TalkNovaProxyError.cannotListen }
        port = bound
    }

    func stop() {
        stateLock.lock()
        let fd = listenFD
        listenFD = -1
        running = false
        stateLock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        port = nil
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    func update(gatewayPort: Int, gatewayKey: String) {
        stateLock.lock()
        self.gatewayPort = gatewayPort
        self.gatewayKey = gatewayKey
        stateLock.unlock()
    }

    private var currentGatewayPort: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return gatewayPort
    }

    private var currentGatewayKey: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return gatewayKey
    }

    // MARK: Setup helpers

    private static func importIdentity(p12URL: URL, passphrase: String) throws -> SecIdentity {
        let data = try Data(contentsOf: p12URL)
        var items: CFArray?
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]] else {
            throw TalkNovaProxyError.p12ImportFailed(status)
        }
        guard let identity = array.first?[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw TalkNovaProxyError.missingIdentity
        }
        return identity
    }

    private static func listenFD(port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = Darwin.accept(fd, &address, &length)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            var timeout = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            Task.detached(priority: .userInitiated) { [weak self] in
                self?.serve(client)
            }
        }
    }

    // MARK: Per-connection handling

    private func serve(_ fd: Int32) {
        let connection = PlainConnection(fd: fd)
        defer { connection.close() }

        guard let head = connection.readHead() else { return }
        guard head.requestLine.uppercased().hasPrefix("CONNECT ") else {
            connection.writeAll(Data("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n".utf8))
            return
        }
        let authority = head.requestLine
            .split(separator: " ", omittingEmptySubsequences: true)
            .dropFirst().first.map(String.init) ?? ""
        let host = authority.split(separator: ":").first.map(String.init)?.lowercased() ?? ""

        guard host == "talknova.site" else {
            // Blind tunnel: no TLS inspection; the client talks end to end.
            let portPart = authority.split(separator: ":").dropFirst().first.flatMap { Int($0) } ?? 443
            connection.writeAll(Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8))
            guard let upstream = PlainConnection.connect(host: host, port: portPart) else { return }
            tunnel(clientFD: fd, upstreamFD: upstream.fd)
            return
        }

        // MITM talknova.site
        connection.writeAll(Data("HTTP/1.1 200 Connection established\r\n\r\n".utf8))
        guard let identity else { return }
        let tls = TLSConnection(fd: fd)
        do {
            try tls.handshake(mode: .server(identity: identity))
        } catch {
            tls.close()
            return
        }

        // urllib issues one request per connection; handle one, then close.
        guard let (request, raw) = readRequest(client: tls),
              let routed = route(request: request, raw: raw) else {
            tls.close()
            return
        }
        do {
            try tls.write(routed)
        } catch {
            // client went away
        }
        tls.close()
    }

    /// Reads one decrypted HTTP request; returns the parsed request plus the
    /// exact raw bytes so they can be forwarded verbatim.
    private func readRequest(client: TLSConnection) -> (HTTPRequest, Data)? {
        var data = Data()
        while data.count < 16 * 1024 * 1024 {
            let chunk = (try? client.read(idleTimeout: data.isEmpty ? 60 : 20)) ?? Data()
            if chunk.isEmpty { return nil }
            data.append(chunk)
            if let request = HTTPRequestParser.parse(data) {
                return (request, data)
            }
        }
        return nil
    }

    /// Routes one decrypted request. Chat and models go to the WehniRoute
    /// gateway with rewritten Host/Authorization; everything else is relayed
    /// to the real talknova.site over TLS with system trust.
    private func route(request: HTTPRequest, raw: Data) -> Data? {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let gatewayRoutes: Set<String> = [
            "/v1/chat/completions", "/chat/completions", "/v1/v1/chat/completions",
            "/v1/models", "/models", "/v1/v1/models",
        ]
        let routedToGateway = gatewayRoutes.contains(path)

        if routedToGateway {
            let rewritten = rewrittenForGateway(raw)
            guard let upstream = PlainConnection.connect(host: "127.0.0.1", port: currentGatewayPort) else {
                return Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
            }
            defer { upstream.close() }
            upstream.writeAll(rewritten)
            return upstream.readAll()
        }

        guard let upstream = PlainConnection.connect(host: "talknova.site", port: 443) else {
            return Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
        }
        let upstreamTLS = TLSConnection(fd: upstream.fd)
        defer { upstreamTLS.close() }
        do {
            try upstreamTLS.handshake(mode: .client)
            try upstreamTLS.write(raw)
            var forwarded = Data()
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                let chunk = try upstreamTLS.read(idleTimeout: 45)
                if chunk.isEmpty { break }
                forwarded.append(chunk)
            }
            return forwarded
        } catch {
            return Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
        }
    }

    private func rewrittenForGateway(_ raw: Data) -> Data {
        var text = String(decoding: raw, as: UTF8.self)
        guard let range = text.range(of: "\r\n\r\n") else { return raw }
        let head = String(text[..<range.lowerBound])
        let body = String(text[range.upperBound...])
        var lines = head.components(separatedBy: "\r\n")
        for index in lines.indices {
            let lower = lines[index].lowercased()
            if lower.hasPrefix("host:") {
                lines[index] = "Host: 127.0.0.1:\(currentGatewayPort)"
            } else if lower.hasPrefix("authorization:") {
                lines[index] = "Authorization: Bearer \(currentGatewayKey)"
            }
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    private func tunnel(clientFD: Int32, upstreamFD: Int32) {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            Self.pump(from: upstreamFD, to: clientFD)
            Darwin.shutdown(clientFD, SHUT_RDWR)
            group.leave()
        }
        Self.pump(from: clientFD, to: upstreamFD)
        Darwin.shutdown(upstreamFD, SHUT_RDWR)
        group.wait()
    }

    private static func pump(from: Int32, to: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let capacity = buffer.count
        while true {
            let count = buffer.withUnsafeMutableBytes { pointer -> Int in
                Darwin.recv(from, pointer.baseAddress, capacity, 0)
            }
            if count <= 0 { return }
            var offset = 0
            while offset < count {
                let sent = buffer.withUnsafeBytes { pointer -> Int in
                    guard let base = pointer.baseAddress else { return -1 }
                    return Darwin.send(to, base.advanced(by: offset), count - offset, 0)
                }
                if sent <= 0 { return }
                offset += sent
            }
        }
    }
}

// MARK: - Plain socket helpers

final class PlainConnection {
    let fd: Int32

    init(fd: Int32) {
        self.fd = fd
    }

    static func connect(host: String, port: Int) -> PlainConnection? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            return nil
        }
        return PlainConnection(fd: fd)
    }

    func readHead() -> (requestLine: String, raw: Data)? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while data.count < 65_536 {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { return nil }
            data.append(contentsOf: buffer[0..<count])
            if let range = data.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: data[..<range.lowerBound], as: UTF8.self)
                let requestLine = head.components(separatedBy: "\r\n").first ?? ""
                return (requestLine, data)
            }
        }
        return nil
    }

    func writeAll(_ data: Data) {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.send(fd, base.advanced(by: offset), buffer.count - offset, 0)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    func readAll() -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    func close() {
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }
}
