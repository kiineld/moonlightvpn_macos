import Foundation
import Combine

/// The figures that change every second while connected: how long the tunnel
/// has been up, and how fast and how much it is moving.
///
/// Kept apart from ``TunnelController`` on purpose. `ObservableObject` has no
/// per-property tracking, so while these lived on the controller every tick
/// re-rendered every view watching it — the sidebar, the whole connect page
/// with its server list, the tray — for the sake of two numbers. Only the
/// views that show them watch this.
@MainActor
public final class TrafficMeter: ObservableObject {
    @Published public internal(set) var uptime: Int = 0
    /// Bytes moved by this session, from the core's own counters.
    @Published public internal(set) var sessionUp: Int64 = 0
    @Published public internal(set) var sessionDown: Int64 = 0
    @Published public internal(set) var rateUp: Int64 = 0
    @Published public internal(set) var rateDown: Int64 = 0

    public init() {}

    /// A new session: the clock and the totals start again.
    func start() {
        uptime = 0
        sessionUp = 0
        sessionDown = 0
    }

    /// Nothing is moving: the clock and the speeds read zero.
    func stop() {
        uptime = 0
        rateUp = 0
        rateDown = 0
    }

    /// One `/traffic` sample.
    func record(up: Int64, down: Int64) {
        rateUp = up
        rateDown = down
        sessionUp += up
        sessionDown += down
    }
}
