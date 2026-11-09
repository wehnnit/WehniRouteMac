import Foundation
import WehniRouteCore

enum TraceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case success = "Success"
    case fallback = "Fallback"
    case failed = "Failed"

    var id: String { rawValue }

    func matches(_ trace: Trace) -> Bool {
        switch self {
        case .all: return true
        case .success: return trace.isSuccess && !trace.fallbackUsed
        case .fallback: return trace.fallbackUsed
        case .failed: return !trace.isSuccess
        }
    }
}

/// Coalesced, off-main trace persistence. The store hands over an immutable
/// snapshot; encoding and the atomic file write happen on a utility queue, at
/// most once per second, so a burst of routes never stalls the UI.
final class TracePersistence: @unchecked Sendable {
    private let url: URL
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let coalesceDelay: TimeInterval
    private var snapshot: [Trace] = []
    private var dirty = false
    private var scheduled = false

    init(url: URL, coalesceDelay: TimeInterval = 1.0) {
        self.url = url
        self.coalesceDelay = coalesceDelay
        self.queue = DispatchQueue(label: "com.wehnnit.WehniRoute.trace-writes", qos: .utility)
    }

    /// Records the latest trace list and schedules a single trailing flush.
    func mark(_ traces: [Trace]) {
        lock.lock()
        snapshot = traces
        dirty = true
        let needsSchedule = !scheduled
        if needsSchedule { scheduled = true }
        lock.unlock()

        guard needsSchedule else { return }
        queue.asyncAfter(deadline: .now() + coalesceDelay) { [weak self] in
            self?.flush()
        }
    }

    /// Synchronous flush for quit and the one-time setup write. The encode and
    /// write still run on the utility queue; callers only wait for them.
    func flushNow() {
        queue.sync { self.flush() }
    }

    private func flush() {
        lock.lock()
        let pending = dirty
        let traces = snapshot
        dirty = false
        scheduled = false
        lock.unlock()

        guard pending else { return }
        write(traces)
    }

    private func write(_ traces: [Trace]) {
        do {
            let encoder = JSONEncoder()
            try encoder.encode(traces).write(to: url, options: .atomic)
        } catch {
            // Trace persistence is best-effort; routing must not fail because of it.
        }
    }
}

/// Trace history and its search/filter UI state. Kept separate from `AppStore`
/// so gateway traffic only invalidates the views that actually display traces.
@MainActor
final class TraceStore: ObservableObject {
    @Published private(set) var traces: [Trace] = []
    /// Cached result of `traces` + `search` + `filter`. Recomputed only when one
    /// of those changes, never on every body evaluation.
    @Published private(set) var filteredTraces: [Trace] = []
    @Published var search = "" {
        didSet { rebuildFiltered() }
    }
    @Published var filter: TraceFilter = .all {
        didSet { rebuildFiltered() }
    }
    @Published var selectedTraceID: UUID?

    private static let limit = 500
    private let persistence: TracePersistence

    init(url: URL = SupportDirectory.tracesURL) {
        persistence = TracePersistence(url: url)
        traces = Self.load(from: url)
        rebuildFiltered()
    }

    var selectedTrace: Trace? {
        traces.first { $0.id == selectedTraceID }
    }

    func record(_ trace: Trace) {
        traces.insert(trace, at: 0)
        if traces.count > Self.limit {
            traces.removeLast(traces.count - Self.limit)
        }
        rebuildFiltered()
        persistence.mark(traces)
    }

    func clear() {
        traces = []
        selectedTraceID = nil
        rebuildFiltered()
        persistence.mark(traces)
    }

    func flushNow() {
        persistence.flushNow()
    }

    private func rebuildFiltered() {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeFilter = filter

        if term.isEmpty {
            filteredTraces = activeFilter == .all ? traces : traces.filter(activeFilter.matches)
            return
        }

        filteredTraces = traces.filter { trace in
            guard activeFilter.matches(trace) else { return false }
            let haystack = [
                trace.requestID,
                trace.selectedProviderName ?? "",
                trace.selectedModel ?? "",
                trace.taskType.label,
                trace.endpoint,
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(term)
        }
    }

    private static func load(from url: URL) -> [Trace] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Trace].self, from: data)) ?? []
    }

    // MARK: - Derived stats

    var successRate: Double? {
        guard !traces.isEmpty else { return nil }
        return Double(traces.filter(\.isSuccess).count) / Double(traces.count)
    }

    var averageLatencyMS: Int? {
        let values = traces.map(\.latencyMS).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    var totalCost: Double {
        traces.reduce(0) { $0 + $1.costUSD }
    }

    var totalTokens: Int {
        traces.reduce(0) { $0 + $1.totalTokens }
    }

    var fallbackRate: Double? {
        guard !traces.isEmpty else { return nil }
        return Double(traces.filter(\.fallbackUsed).count) / Double(traces.count)
    }

    var hourRequestCount: Int {
        let cutoff = Date().addingTimeInterval(-3_600)
        return traces.filter { $0.createdAt > cutoff }.count
    }

    func sparklineValues() -> [Double] {
        traces.prefix(24).reversed().map { Double($0.latencyMS) }
    }
}
