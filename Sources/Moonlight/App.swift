import SwiftUI
import AppKit
import UserNotifications
import MoonlightDesign
import MoonlightCore

@main
struct MoonlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings = AppSettings()
    /// Owned here but not observed here — see ``Services``.
    @StateObject private var services = Services()

    private var tunnel: TunnelController { services.tunnel }

    init() {
        SingleInstance.enforce()
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tunnel)
                .environmentObject(settings)
                .environmentObject(LogStore.shared)
                .onAppear {
                    delegate.tunnel = tunnel
                    delegate.settings = settings
                    delegate.attachStatusItem()
                }
                .task { await LaunchTasks.runOnce(tunnel: tunnel, settings: settings) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Moonlight") {
                ConnectCommand(tunnel: tunnel)

                Button("Refresh subscription") {
                    Task { await tunnel.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // The binding drops writes that do not change the value, which is
        // load-bearing rather than tidiness: SwiftUI writes `isInserted` back on
        // every scene update, `@Published` republishes on *any* assignment, and
        // the two together spin the scene at 100% CPU — starving the main actor
        // badly enough that awaited work (the launch-time subscription refresh)
        // never resumes.
    }
}

/// The controller and the log, created once and handed down — without the
/// app observing either.
///
/// Both used to be `@StateObject`s of the app itself, which subscribes the
/// whole scene to them: every line the core logged and every tick of the
/// uptime re-ran the app's body, rebuilt its window group and its menus, while
/// the connect animation was trying to draw. This object publishes nothing, so
/// the scene never re-runs on their account; the views that show them observe
/// them directly. Still a `@StateObject`, because that is what creates it
/// lazily — after `SingleInstance.enforce()`, which must run before the
/// controller's initialiser reaps anything.
@MainActor
private final class Services: ObservableObject {
    let tunnel = TunnelController()
}

/// "Connect" or "Disconnect" in the menu — the one part of the commands that
/// follows the tunnel, so it observes it on its own.
private struct ConnectCommand: View {
    @ObservedObject var tunnel: TunnelController

    var body: some View {
        Button(tunnel.state.isConnected ? "Disconnect" : "Connect") {
            Task { await tunnel.toggle() }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }
}

// MARK: - Menu bar

enum MenuBarIcon {
    private static let connectedImage = render(alpha: 1)
    private static let idleImage = render(alpha: 0.55)

    static func image(connected: Bool) -> NSImage {
        connected ? connectedImage : idleImage
    }

    /// The crescent and its two dots, from `assets/logo-tile.svg`, in the same
    /// 44-unit box the tile uses.
    private static let shapes: [String] = [
        "M30 22a8.4 8.4 0 1 1-9.4-8.34A10 10 0 0 0 30 22Z",
        "M28.8 12.5a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0 -3.4 0Z",
        "M23.9 8a1.1 1.1 0 1 0 2.2 0a1.1 1.1 0 1 0 -2.2 0Z",
    ]

    /// A template image, so the glyph inverts with the menu bar's own appearance
    /// instead of staying lime on a light bar. Connected is solid; disconnected
    /// is the same shape at lower alpha, which a template image renders as a
    /// lighter mark rather than a different colour.
    private static func render(alpha: CGFloat) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return true }

            let combined = CGMutablePath()
            for d in shapes {
                combined.addPath(SVGPath(d).path(
                    in: CGRect(x: 0, y: 0, width: 44, height: 44), viewBox: 44
                ).cgPath)
            }

            // Fit the glyph's own bounds rather than the 44-unit box: the
            // crescent sits off-centre in the tile, and centring the box would
            // leave the mark visibly high and small in the bar.
            let bounds = combined.boundingBoxOfPath
            guard bounds.width > 0, bounds.height > 0 else { return true }
            let inset: CGFloat = 1.5
            let scale = min((side - inset * 2) / bounds.width,
                            (side - inset * 2) / bounds.height)

            var transform = CGAffineTransform.identity
                .translatedBy(x: (side - bounds.width * scale) / 2,
                              y: (side - bounds.height * scale) / 2)
                .scaledBy(x: scale, y: -scale)          // SVG's y axis runs down
                .translatedBy(x: -bounds.minX, y: -bounds.maxY)

            guard let fitted = combined.copy(using: &transform) else { return true }
            context.addPath(fitted)
            context.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var tunnel: TunnelController?
    var settings: AppSettings?
    private var statusItem: StatusItemController?
    private var alerts: SubscriptionAlerts?
    private var scheduler: SubscriptionScheduler?
    private var quitting = false

    /// Built once both objects exist, which is when the root view appears.
    @MainActor
    func attachStatusItem() {
        guard statusItem == nil, let tunnel, let settings else { return }
        statusItem = StatusItemController(tunnel: tunnel, settings: settings)
        alerts = SubscriptionAlerts(tunnel: tunnel, settings: settings)
        scheduler = SubscriptionScheduler(tunnel: tunnel)
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // The app starts at login when the setting says so and only then. A
        // menu bar app is still running at shutdown, so macOS's "reopen windows
        // when logging back in" brought it back regardless of the switch —
        // which read as the switch not working. The login item is the one way
        // in, and it is registered only while the switch is on.
        NSApp.disableRelaunchOnLogin()

        if LoginLaunch.detect() {
            LoginLaunch.hideFirstWindow = true
            let menuBarIcon = settings?.menuBarIcon ?? Preferences.shared.menuBarIcon
            if let window = NSApp.mainWindowCandidate {
                LoginLaunch.hideFirstWindow = false
                LoginLaunch.tuck(window, menuBarIcon: menuBarIcon)
            }
        }

        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    /// Clicking the Dock icon with no window showing brings one back, which is
    /// the macOS convention and the only way back from "close to menu bar". A
    /// window hidden at login still exists and is shown; one that was closed is
    /// gone, and returning `true` lets SwiftUI make a new one.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let window = NSApp.mainWindowCandidate else { return true }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return false
    }

    /// Closing the window keeps the tunnel up when the menu bar icon is on —
    /// otherwise quitting is the only way to close, and the tunnel would drop
    /// every time someone tidied their desktop.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(settings?.menuBarIcon ?? true)
    }

    /// The tunnel must come down with the app: a core left running would keep
    /// the machine's proxy pointing at a process nothing owns.
    ///
    /// Deferred rather than awaited in `applicationWillTerminate`. That used to
    /// block the main thread on a semaphore while the disconnect waited for
    /// that same main thread, so every quit stalled for the full eight-second
    /// timeout and then exited with the tunnel still up. `.terminateLater` keeps
    /// the run loop turning until the teardown has actually finished.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let tunnel else { return .terminateNow }
        // A second ⌘Q during the teardown waits for the one already under way
        // rather than cutting it short.
        guard !quitting else { return .terminateLater }
        quitting = true
        Task { @MainActor in
            await tunnel.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        // A teardown that hangs must not make the app unquittable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Banners show while the app is frontmost too — the default is to drop
    /// them, which is exactly when someone is looking at the plan.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
