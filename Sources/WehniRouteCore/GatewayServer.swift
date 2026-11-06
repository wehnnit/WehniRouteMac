import Darwin
import Foundation

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public var json: JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: body)
    }

    public var bearerToken: String? {
        guard let header = headers["authorization"], header.lowercased().hasPrefix("bearer ") else {
            return nil
        }
        return String(header.dropFirst(7))
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public var streamFrames: [Data]?

    public init(
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data = Data(),
        streamFrames: [Data]? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.streamFrames = streamFrames
    }

    public static func json(_ status: Int, _ value: JSONValue) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: value.jsonData
        )
    }

    public static func error(_ status: Int, message: String, type: String = "wehni_route_error") -> HTTPResponse {
        .json(status, .object([
            "error": .object([
                "message": .string(message),
                "type": .string(type),
            ])
        ]))
    }

    public static func stream(_ frames: [Data], contentType: String) -> HTTPResponse {
        HTTPResponse(
            status: 200,
            headers: [
                "Content-Type": contentType,
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no",
            ],
            streamFrames: frames
        )
    }
}

public enum HTTPRequestParser {
    public static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        return HTTPRequest(
            method: String(parts[0]).uppercased(),
            path: String(parts[1]),
            headers: headers,
            body: body
        )
    }
}

public enum GatewayError: LocalizedError {
    case socket(String)
    case bind(Int32)
    case listen(Int32)

    public var errorDescription: String? {
        switch self {
        case .socket(let detail): return "Could not create gateway socket: \(detail)"
        case .bind(let code): return "Could not bind 127.0.0.1: \(errnoText(code))"
        case .listen(let code): return "Could not listen: \(errnoText(code))"
        }
    }

    private func errnoText(_ code: Int32) -> String {
        String(cString: strerror(code))
    }
}

/// A deliberately small HTTP/1.1 server bound to loopback. It exists so coding
/// agents can point at http://127.0.0.1:<port>/v1; it is not a general-purpose
/// web server. One request per connection, then close.
public final class GatewayServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "com.wehnnit.WehniRoute.gateway", qos: .userInitiated)
    private var listenFD: Int32 = -1
    private var running = false
    private var handler: Handler?

    public var onStateChange: (@Sendable (Bool, String?) -> Void)?

    public init() {}

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    public func start(port: UInt16, handler: @escaping Handler) throws {
        stop()

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw GatewayError.socket(String(cString: strerror(errno)))
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw GatewayError.bind(code)
        }

        guard Darwin.listen(fd, 32) == 0 else {
            let code = errno
            close(fd)
            throw GatewayError.listen(code)
        }

        stateLock.lock()
        listenFD = fd
        self.handler = handler
        running = true
        stateLock.unlock()

        queue.async { [weak self] in
            self?.acceptLoop(fd)
        }
        onStateChange?(true, nil)
    }

    public func stop() {
        stateLock.lock()
        let fd = listenFD
        listenFD = -1
        running = false
        handler = nil
        stateLock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        onStateChange?(false, nil)
    }

    // MARK: - Accept / read / write

    private func acceptLoop(_ fd: Int32) {
        while true {
            var address = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = Darwin.accept(fd, &address, &length)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            configure(client)
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.serve(client)
            }
        }
    }

    private func configure(_ fd: Int32) {
        var timeout = timeval(tv_sec: 20, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    }

    private func serve(_ fd: Int32) async {
        defer { close(fd) }
        guard let request = readRequest(fd) else {
            write(.error(400, message: "Malformed HTTP request"), to: fd)
            return
        }
        guard let handler = currentHandler() else {
            write(.error(503, message: "Gateway is not ready"), to: fd)
            return
        }
        let response = await handler(request)
        write(response, to: fd)
    }

    private func readRequest(_ fd: Int32) -> HTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count < 16 * 1024 * 1024 {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if let request = HTTPRequestParser.parse(data) { return request }
        }
        return HTTPRequestParser.parse(data)
    }

    private func write(_ response: HTTPResponse, to fd: Int32) {
        var headers = response.headers
        if headers.keys.first(where: { $0.lowercased() == "content-type" }) == nil {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(response.status) \(statusText(response.status))\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }

        if let frames = response.streamFrames {
            head += "\r\n"
            writeAll(Data(head.utf8), to: fd)
            for frame in frames {
                writeAll(frame, to: fd)
            }
        } else {
            head += "Content-Length: \(response.body.count)\r\n\r\n"
            var data = Data(head.utf8)
            data.append(response.body)
            writeAll(data, to: fd)
        }
    }

    private func writeAll(_ data: Data, to fd: Int32) {
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

    private func currentHandler() -> Handler? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return handler
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Response"
        }
    }
}
