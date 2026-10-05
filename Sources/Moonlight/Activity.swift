import AppKit
import Combine
import MoonlightCore

/// Whether anyone can see the app right now.
///
/// A VPN client spends most of its life closed to the menu bar, and until this
/// existed it worked exactly as hard there as with its window open: the uptime
/// clock ticked, the speeds were read from the core every second, the
/// connections page — if that was the page left showing — went on polling, and
/// an idle core was kept warm for a latency button nobody could press. This
/// watches the window and the tray and tells the rest when to stop and when to
/// pick up again.
///
/// "Visible" is the window server's own word for it (`occlusionState`), so a
/// window that is closed, hidden at login, minimised, on another Space or
/// wholly behind other windows all count the same: not on screen.
@MainActor
final class AppActivity: ObservableObject {
    /// The main window is on screen. Views that poll or stream for the eye
    /// follow this.
    @Published private(set) var windowVisible = true
    /// The tray is open. Set by the status item, which is what opens it.
    var trayOpen = false { didSet { report() } }

    private weak var tunnel: TunnelController?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // On the next turn of the run loop: a window that is closing
                // still reads as visible while it says it will close.
                DispatchQueue.main.async { self?.refresh() }
            }
        }
    }

    func attach(_ tunnel: TunnelController) {
        guard self.tunnel !== tunnel else { return }
        self.tunnel = tunnel
        refresh()
    }

    private func refresh() {
        let visible = NSApp.windows.contains { window in
            window.canBecomeMain && !(window is NSPanel) && window.occlusionState.contains(.visible)
        }
        if visible != windowVisible { windowVisible = visible }
        report()
    }

    private func report() {
        tunnel?.setWatched(windowVisible || trayOpen)
    }
}
