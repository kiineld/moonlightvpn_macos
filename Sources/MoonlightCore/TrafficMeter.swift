import Foundation
import Combine

/// The figures that change every second while connected: how long the tunnel
/// has been up, and how fast it is moving.
///
/// Kept apart from ``TunnelController`` on purpose. `ObservableObject` has no
/// per-property tracking, so while these lived on the controller every tick
/// re-rendered every view watching it — the sidebar, the whole connect page
/// with its server list, the tray — for the sake of two numbers. Only the
/// views that show them watch this.
///
/// It is fed only while something of the app is on screen (see
/// ``TunnelController/setWatched(_:)``): a clock and two speeds nobody can see
/// are not worth waking the processor for every second.
@MainActor
public final class TrafficMeter: ObservableObject {
    @Published public internal(set) var uptime: Int = 0
    @Published public internal(set) var rateUp: Int64 = 0
    @Published public internal(set) var rateDown: Int64 = 0

    public init() {}

    /// Nothing is moving: the clock and the speeds read zero.
    func stop() {
        tick(0)
        rest()
    }

    /// Nobody is looking, so no samples are arriving: the speeds read zero
    /// rather than whatever the last one said.
    func rest() {
        record(up: 0, down: 0)
    }

    func tick(_ seconds: Int) {
        if uptime != seconds { uptime = seconds }
    }

    /// One `/traffic` sample. An idle tunnel sends the same zeros every
    /// second, and publishing them again would redraw the views for nothing.
    func record(up: Int64, down: Int64) {
        if rateUp != up { rateUp = up }
        if rateDown != down { rateDown = down }
    }
}
