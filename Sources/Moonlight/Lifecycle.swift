import AppKit
import MoonlightCore

/// One copy of the app at a time.
///
/// Two copies do not coexist: each treats the other's core as an orphan from a
/// crashed session and stops it, restores the system proxy out from under it,
/// and stops the privileged core it is routing through. A copy opened from the
/// DMG while the installed one runs was enough to cut the tunnel.
///
/// Checked before anything else runs — in particular before the
/// `TunnelController` exists, since its initialiser is what reaps cores.
enum SingleInstance {
    static func enforce() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != mine && !$0.isTerminated }) else { return }

        // Opening the running copy's bundle sends it a reopen event, which
        // brings its window back even when it was closed to the menu bar;
        // activating alone would only bring an app with no window forward.
        other.activate(options: [.activateIgnoringOtherApps])
        if let url = other.bundleURL { NSWorkspace.shared.open(url) }
        exit(0)
    }
}

/// Whether macOS started this process at login, rather than a person.
enum LoginLaunch {
    /// Passed by the Monterey LaunchAgent, which has no launch event to read.
    static let argument = "--launched-at-login"

    /// Read from the launch Apple event, so it is only meaningful while
    /// `applicationDidFinishLaunching` is handling that event.
    static func detect() -> Bool {
        if CommandLine.arguments.contains(argument) { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
            == keyAELaunchedAsLogInItem
    }

    /// Set at a login launch, and consumed by the first window that appears —
    /// SwiftUI may create it before or after the delegate hears about the launch.
    static var hideFirstWindow = false

    /// "Клиент стартует свёрнутым": to the menu bar when the icon is there to
    /// bring it back, otherwise to the Dock. Never closed — with no menu bar
    /// icon, closing the last window quits.
    static func tuck(_ window: NSWindow, menuBarIcon: Bool) {
        if menuBarIcon { window.orderOut(nil) } else { window.miniaturize(nil) }
    }
}

/// What the app does once per launch, whatever the windows do.
///
/// This used to be a `.task` on the root view. SwiftUI runs that for every
/// window it creates, so reopening the window after closing it to the menu bar
/// refreshed again and — worse — auto-connected again, reconnecting a tunnel
/// the user had just turned off.
@MainActor
enum LaunchTasks {
    private static var done = false

    static func runOnce(tunnel: TunnelController, settings: AppSettings, updater: Updater) async {
        guard !done else { return }
        done = true
        // Beside the rest rather than after it: a refresh can take a while,
        // and the check has no need of the tunnel. What it finds is announced
        // by `UpdateBanner`.
        Task { await updater.check(silently: true) }
        guard tunnel.hasSubscription else { return }
        // A subscription cached from a previous launch gives the server list
        // something to show before the network answers, so launch only
        // refreshes when the schedule says it is due — "off" means off. With
        // nothing cached there is nothing to run, and it refreshes regardless.
        if tunnel.hasCachedSubscription {
            await tunnel.refreshIfDue()
        } else {
            await tunnel.refresh()
        }
        // The core is warmed by the controller itself; this only decides
        // whether traffic is routed through it.
        if settings.autoConnect { await tunnel.connect() }
    }
}

extension NSApplication {
    /// The app's own window, as opposed to the status item's and the other
    /// helper windows AppKit keeps in `windows`. `windows.first` was sometimes
    /// the status bar's, which made "open" do nothing visible.
    var mainWindowCandidate: NSWindow? {
        windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }
}

/// Refreshes the subscription on the interval chosen in Settings.
///
/// A timer that only compares dates unless something is due, plus a check on
/// wake — a Mac asleep through the due time would otherwise wait for the next
/// tick after it opens.
@MainActor
final class SubscriptionScheduler {
    private let tunnel: TunnelController
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(tunnel: TunnelController) {
        self.tunnel = tunnel
        let timer = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tunnel.refreshIfDue() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // The network takes a few seconds to come back after wake.
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self?.tunnel.refreshIfDue()
            }
        }
    }
}
