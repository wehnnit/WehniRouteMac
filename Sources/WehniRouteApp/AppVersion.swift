import Foundation
import WehniRouteCore

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.1"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "11"
    }

    static let updateRepository = "wehnnit/WehniRouteMac"
    static let updateFeedURL = "https://api.github.com/repos/\(updateRepository)/releases/latest"
    static let bundleIdentifier = "com.wehnnit.WehniRoute"
}

enum SupportDirectory {
    static var url: URL {
        if let override = ProcessInfo.processInfo.environment["WEHNIROUTE_SUPPORT_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WehniRoute", isDirectory: true)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static var configURL: URL { url.appendingPathComponent("native-config.json") }
    static var tracesURL: URL { url.appendingPathComponent("native-traces.json") }
    static var gatewayKeyURL: URL { url.appendingPathComponent("gateway.key") }
    static var updateLogURL: URL { url.appendingPathComponent("update.log") }

    static func ensureExists() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

extension AppConfig {
    static let latestSchemaVersion = 2
}
