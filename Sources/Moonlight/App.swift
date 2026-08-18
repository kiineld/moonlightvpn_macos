import SwiftUI
import AppKit
import UserNotifications
import MoonlightDesign
import MoonlightCore

@main
struct MoonlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings = AppSettings()
    @StateObject private var tunnel = TunnelController()
    @StateObject private var logs = LogStore.shared

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tunnel)
                .environmentObject(settings)
                .environmentObject(logs)
                .onAppear {
                    delegate.tunnel = tunnel
                    delegate.settings = settings
                    delegate.attachStatusItem()
                }
                .task {
                    // A subscription cached from a previous launch gives the
                    // server list something to show before the network answers.
                    if tunnel.hasSubscription {
                        await tunnel.refresh()
                        // The core is warmed by the controller itself; this only
                        // decides whether traffic is routed through it.
                        if settings.autoConnect { await tunnel.connect() }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Moonlight") {
                Button(tunnel.state.isConnected ? "Disconnect" : "Connect") {
                    Task { await tunnel.toggle() }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var tunnel: TunnelController?
    var settings: AppSettings?
    private var statusItem: StatusItemController?

    /// Built once both objects exist, which is when the root view appears.
    @MainActor
    func attachStatusItem() {
        guard statusItem == nil, let tunnel, let settings else { return }
        statusItem = StatusItemController(tunnel: tunnel, settings: settings)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NSApp.setActivationPolicy(.regular)
    }

    /// Clicking the Dock icon with no window open reopens one, which is the
    /// macOS convention and the only way back from "close to menu bar".
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }

    /// Closing the window keeps the tunnel up when the menu bar icon is on —
    /// otherwise quitting is the only way to close, and the tunnel would drop
    /// every time someone tidied their desktop.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(settings?.menuBarIcon ?? true)
    }

    /// The tunnel must come down with the app: a core left running would keep
    /// the machine's proxy pointing at a process nothing owns.
    func applicationWillTerminate(_ notification: Notification) {
        guard let tunnel else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await tunnel.disconnect()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 8)
    }
}
