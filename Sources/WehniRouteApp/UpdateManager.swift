import AppKit
import CryptoKit
import Foundation

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available
    case downloading
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}

struct UpdateRelease: Equatable {
    let version: String
    let name: String
    let notes: String
    let pageURL: URL
    let zipURL: URL
    let checksumURL: URL?
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var availableRelease: UpdateRelease?
    @Published private(set) var lastChecked: Date?
    @Published var autoUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoUpdateEnabled, forKey: Self.autoUpdateDefaultsKey)
        }
    }

    private static let autoUpdateDefaultsKey = "WehniRoute.autoUpdateEnabled"
    private var started = false
    private var automaticTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.autoUpdateDefaultsKey) == nil {
            defaults.set(true, forKey: Self.autoUpdateDefaultsKey)
        }
        autoUpdateEnabled = defaults.bool(forKey: Self.autoUpdateDefaultsKey)
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Checks GitHub Releases automatically."
        case .checking:
            return "Checking GitHub Releases…"
        case .upToDate:
            return "You are on the latest version."
        case .available:
            if let availableRelease {
                return "Version \(availableRelease.version) is available."
            }
            return "An update is available."
        case .downloading:
            return "Downloading and verifying the update…"
        case .installing:
            return "Installing update and restarting…"
        case .failed(let message):
            return message
        }
    }

    func startAutomaticChecks() {
        guard !started else { return }
        started = true
        guard autoUpdateEnabled else { return }

        automaticTask?.cancel()
        automaticTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.checkForUpdates(userInitiated: false, installAutomatically: true)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 86_400_000_000_000)
                guard !Task.isCancelled else { return }
                await self.checkForUpdates(userInitiated: false, installAutomatically: true)
            }
        }
    }

    func checkForUpdates(userInitiated: Bool, installAutomatically: Bool = true) async {
        guard !state.isBusy else { return }

        state = .checking
        do {
            guard let release = try await GitHubReleaseClient.latest(repository: AppVersion.updateRepository) else {
                state = .upToDate
                lastChecked = Date()
                return
            }

            guard let current = SemanticVersion(AppVersion.short),
                  let candidate = SemanticVersion(release.version) else {
                throw UpdateError.invalidVersion(release.version)
            }

            lastChecked = Date()
            guard candidate > current else {
                availableRelease = nil
                state = .upToDate
                return
            }

            availableRelease = release
            state = .available

            if autoUpdateEnabled && installAutomatically {
                await install(release)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
            Self.appendLog("Update check failed: \(message)")
            if userInitiated {
                Self.appendLog("Manual update check requested")
            }
        }
    }

    func installAvailableUpdate() async {
        guard let availableRelease else { return }
        await install(availableRelease)
    }

    private func install(_ release: UpdateRelease) async {
        guard !state.isBusy else { return }
        state = .downloading
        Self.appendLog("Starting update to \(release.version) from \(release.zipURL.absoluteString)")

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("WehniRouteUpdate-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            let zipURL = try await download(release.zipURL, to: staging)
            guard let checksumURL = release.checksumURL else {
                throw UpdateError.missingChecksum
            }
            let expectedChecksum = try await fetchChecksum(checksumURL)
            let actualChecksum = try sha256(of: zipURL)
            guard actualChecksum == expectedChecksum else {
                throw UpdateError.checksumMismatch
            }

            let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, extracted.path])

            let newApp = extracted.appendingPathComponent("WehniRoute.app", isDirectory: true)
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.missingAppBundle
            }
            try validate(app: newApp, expectedVersion: release.version)

            let currentApp = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.isWritableFile(atPath: currentApp.deletingLastPathComponent().path) else {
                throw UpdateError.readOnlyInstallLocation(currentApp.deletingLastPathComponent().path)
            }

            state = .installing
            try launchReplacementHelper(
                currentApp: currentApp,
                newApp: newApp,
                staging: staging
            )
            Self.appendLog("Update helper launched; terminating current app")
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
            Self.appendLog("Update failed: \(message)")
        }
    }

    private func download(_ url: URL, to directory: URL) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let destination = directory.appendingPathComponent("WehniRoute.zip")
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func fetchChecksum(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let text = String(data: data, encoding: .utf8),
              let token = text.split(whereSeparator: { $0.isWhitespace }).first,
              token.count == 64 else {
            throw UpdateError.invalidChecksum
        }
        return token.lowercased()
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validate(app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String == AppVersion.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              SemanticVersion(version) == SemanticVersion(expectedVersion) else {
            throw UpdateError.invalidAppBundle
        }
        try runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    private func launchReplacementHelper(
        currentApp: URL,
        newApp: URL,
        staging: URL
    ) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wehni-route-update-\(UUID().uuidString).sh")
        let logURL = SupportDirectory.updateLogURL
        try? SupportDirectory.ensureExists()

        let script = """
        #!/bin/sh
        set -eu
        APP=\(shellQuote(currentApp.path))
        NEW=\(shellQuote(newApp.path))
        STAGING=\(shellQuote(staging.path))
        PID=\(ProcessInfo.processInfo.processIdentifier)
        LOG=\(shellQuote(logURL.path))
        BACKUP="${APP}.old.$$"

        {
            echo "waiting for WehniRoute pid $PID"
            while kill -0 "$PID" 2>/dev/null; do
                sleep 0.2
            done
            echo "replacing $APP"
            if mv "$APP" "$BACKUP"; then
                if mv "$NEW" "$APP"; then
                    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
                    rm -rf "$BACKUP"
                    echo "update installed"
                    open "$APP"
                else
                    mv "$BACKUP" "$APP" || true
                    echo "could not move new app into place; restored old app"
                    exit 1
                fi
            else
                echo "could not move old app aside"
                exit 1
            fi
            rm -rf "$STAGING"
            rm -f "$0"
        } >> "$LOG" 2>&1
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(executable, process.terminationStatus)
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appendLog(_ message: String) {
        guard let data = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n".data(using: .utf8) else {
            return
        }
        try? SupportDirectory.ensureExists()
        let url = SupportDirectory.updateLogURL
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private enum GitHubReleaseClient {
    static func latest(repository: String) async throws -> UpdateRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("WehniRoute/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        if http.statusCode == 404 {
            return nil
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let zip = payload.assets.first(where: {
            $0.name.lowercased().hasSuffix(".zip") && !$0.name.lowercased().contains("sha")
        }),
            let zipURL = URL(string: zip.browserDownloadURL)
        else {
            throw UpdateError.missingZipAsset
        }

        let checksum = payload.assets.first(where: {
            let name = $0.name.lowercased()
            return name.hasSuffix(".sha256") || name.hasSuffix(".sha256.txt")
        })
        guard let checksum, let checksumURL = URL(string: checksum.browserDownloadURL) else {
            throw UpdateError.missingChecksum
        }
        guard let pageURL = URL(string: payload.htmlURL) else {
            throw UpdateError.invalidResponse
        }

        return UpdateRelease(
            version: normalizedVersion(payload.tagName),
            name: payload.name ?? payload.tagName,
            notes: payload.body ?? "",
            pageURL: pageURL,
            zipURL: zipURL,
            checksumURL: checksumURL
        )
    }

    private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct SemanticVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let core = withoutPrefix.split(separator: "-").first.map(String.init) ?? withoutPrefix
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else {
            return nil
        }
        components = parts.compactMap { $0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum UpdateError: LocalizedError {
    case invalidVersion(String)
    case invalidResponse
    case httpStatus(Int)
    case missingZipAsset
    case missingChecksum
    case invalidChecksum
    case checksumMismatch
    case missingAppBundle
    case invalidAppBundle
    case readOnlyInstallLocation(String)
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let value):
            return "The release version ‘\(value)’ is not a valid version."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .httpStatus(let status):
            return "GitHub returned HTTP \(status)."
        case .missingZipAsset:
            return "The latest release does not contain a .zip app asset."
        case .missingChecksum:
            return "The latest release does not contain a SHA-256 checksum asset."
        case .invalidChecksum:
            return "The release checksum file is malformed."
        case .checksumMismatch:
            return "The downloaded update failed checksum verification."
        case .missingAppBundle:
            return "The update does not contain WehniRoute.app."
        case .invalidAppBundle:
            return "The update app bundle has the wrong identifier, version, or signature."
        case .readOnlyInstallLocation(let path):
            return "WehniRoute cannot write to \(path). Move the app to a writable Applications folder and try again."
        case .commandFailed(let command, let status):
            return "\(command) failed with status \(status)."
        }
    }
}
