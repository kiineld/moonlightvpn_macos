import Foundation

/// Loopback TCP ports: whether one can be listened on, and which nearby one can.
///
/// The core listens on two — its API and its proxy listener — and failing to
/// get one is not fatal to it: it logs the error and carries on without that
/// listener. A core like that looks alive and never answers, which is where
/// "the core did not answer" came from whenever another client (or this app's
/// own core from a moment ago, still on its way out) held the port. So the
/// ports are checked before the core is started, and moved when they are
/// someone else's.
public enum LocalPort {

    /// Whether `port` on 127.0.0.1 can be bound right now.
    ///
    /// Asked the way the core will ask: with address reuse on, as Go's
    /// listener sets it. Without it, connections the last core closed a moment
    /// ago would hold the port "in use" for half a minute, and every restart
    /// would look like a conflict.
    public static func isFree(_ port: Int) -> Bool {
        guard (1...65_535).contains(port) else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// The first free port at or after `port`, leaving out `avoiding` — the
    /// core's other listener, which is not bound yet and so still reads free.
    public static func firstFree(from port: Int, avoiding: Set<Int> = [], span: Int = 200) -> Int? {
        (port..<min(port + span, 65_536)).first { !avoiding.contains($0) && isFree($0) }
    }
}

/// How often the core may be brought back before the app stops and says so.
///
/// A core that dies once — killed under memory pressure, tripped by a network
/// change — is restarted and nobody needs to hear about it. One that dies every
/// time it starts would otherwise be restarted for ever, the tunnel flickering
/// while the window says it is connecting; past the limit the app gives up and
/// says what happened.
public struct RestartBudget: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var spent: [Date] = []

    public init(limit: Int = 3, window: TimeInterval = 120) {
        self.limit = limit
        self.window = window
    }

    /// Takes one restart from the budget; false when there is none left.
    public mutating func spend(at now: Date = Date()) -> Bool {
        spent.removeAll { now.timeIntervalSince($0) >= window }
        guard spent.count < limit else { return false }
        spent.append(now)
        return true
    }
}

/// The core was started and its API never answered — it died on the way up,
/// could not bind its controller, or hung. Starting it again is worth a try,
/// which is what sets this apart from a config the core refuses.
public struct CoreUnresponsive: LocalizedError {
    /// The tail of the core's own log, for the app's.
    public let log: String

    public init(log: String) {
        self.log = log
    }

    public var errorDescription: String? {
        "Core did not answer after starting" + (log.isEmpty ? "" : "\n\(log)")
    }
}

/// How the controller sets this Mac's proxy: through `networksetup` in the
/// app, and not at all in the test suite, which drives a real core through a
/// connect and must leave the machine's network settings alone.
public struct ProxyControl: Sendable {
    public var snapshot: @Sendable () -> SystemProxy.Snapshot
    public var enable: @Sendable (_ port: Int) -> Void
    public var restore: @Sendable (SystemProxy.Snapshot) -> Void
    public var disable: @Sendable (_ port: Int) -> Void

    public static let system = ProxyControl(
        snapshot: { SystemProxy.snapshot() },
        enable: { SystemProxy.enable(port: $0) },
        restore: { SystemProxy.restore($0) },
        disable: { SystemProxy.disable(pointingAt: $0) }
    )

    /// Changes nothing.
    public static let none = ProxyControl(
        snapshot: { SystemProxy.Snapshot(services: []) },
        enable: { _ in },
        restore: { _ in },
        disable: { _ in }
    )
}
