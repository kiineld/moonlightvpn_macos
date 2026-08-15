import Foundation
import Combine

/// One line in the log viewer.
public struct LogEntry: Identifiable, Hashable, Sendable {
    public enum Level: String, CaseIterable, Sendable {
        case debug, info, warning, error

        /// mihomo writes `warning`; most UIs and its own docs say `warn`.
        public init(core raw: String) {
            switch raw.lowercased() {
            case "debug": self = .debug
            case "warn", "warning": self = .warning
            case "err", "error": self = .error
            default: self = .info
            }
        }
    }

    public enum Source: String, CaseIterable, Sendable {
        /// The app's own steps — connecting, refreshing, applying settings.
        case client
        /// mihomo's log stream.
        case core
    }

    public let id = UUID()
    public let at: Date
    public let level: Level
    public let source: Source
    public let message: String

    public init(at: Date = Date(), level: Level, source: Source, message: String) {
        self.at = at
        self.level = level
        self.source = source
        self.message = message
    }
}

/// The log the viewer reads.
///
/// Bounded: a core at debug level emits a line per connection, and an app left
/// running for a week would otherwise hold every one of them. The cap is on
/// entries rather than bytes because that is what the list has to render.
@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()

    @Published public private(set) var entries: [LogEntry] = []

    private let limit = 2_000
    private var coreStream: Task<Void, Never>?

    public init() {}

    public func append(_ level: LogEntry.Level, _ source: LogEntry.Source, _ message: String) {
        entries.append(LogEntry(level: level, source: source, message: message))
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    /// The app's own narration of what it is doing, which is the half of the log
    /// that explains *why* the core did something.
    public func client(_ message: String, level: LogEntry.Level = .info) {
        append(level, .client, message)
    }

    public func clear() { entries.removeAll() }

    /// Follows the core's own log stream.
    ///
    /// Restartable: the stream dies with the core, and the core is swapped when
    /// the tunnel moves between system-proxy and TUN.
    public func followCore(_ api: MihomoAPI) {
        coreStream?.cancel()
        coreStream = Task { [weak self] in
            for await line in api.logStream() {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.append(LogEntry.Level(core: line.type), .core, line.payload)
                }
            }
        }
    }

    public func stopFollowingCore() {
        coreStream?.cancel()
        coreStream = nil
    }
}
