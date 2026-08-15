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

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tunnel)
                .environmentObject(settings)
                .onAppear {
                    delegate.tunnel = tunnel
                    delegate.settings = settings
                }
                .task {
                    // A subscription cached from a previous launch gives the
                    // server list something to show before the network answers.
                    if tunnel.hasSubscription {
                        await tunnel.refresh()
                        if settings.autoConnect { await tunnel.connect() }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
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
        MenuBarExtra(isInserted: Binding(
            get: { settings.menuBarIcon },
            set: { if $0 != settings.menuBarIcon { settings.menuBarIcon = $0 } }
        )) {
            MenuBarContent()
                .environmentObject(tunnel)
                .environmentObject(settings)
        } label: {
            // A template image so the glyph inverts with the menu bar's own
            // appearance rather than staying lime on a light bar. Both states are
            // drawn once — building an NSImage inside the scene body redraws it
            // on every update.
            Image(nsImage: tunnel.state.isConnected ? MenuBarIcon.connected : MenuBarIcon.idle)
        }
    }
}

// MARK: - Menu bar

private struct MenuBarContent: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Button(tunnel.state.isConnected
               ? L.t(.hintDisconnect, settings.locale)
               : L.t(.hintConnect, settings.locale)) {
            Task { await tunnel.toggle() }
        }
        .disabled(!tunnel.hasSubscription || tunnel.state.isBusy)

        if tunnel.state.isConnected {
            Text("↓ \(Format.rate(tunnel.rateDown, locale: settings.locale))  ↑ \(Format.rate(tunnel.rateUp, locale: settings.locale))")
            Text(Format.duration(tunnel.uptime))
        }
        if let days = tunnel.info.daysLeft {
            Text("\(L.t(.remainingCaps, settings.locale)): \(Format.days(days, locale: settings.locale))")
        }

        Divider()

        // Nodes are listed only while connected: selecting one with the tunnel
        // down would write a preference the user cannot see take effect.
        if tunnel.state.isConnected, !tunnel.nodes.isEmpty {
            Menu(L.t(.servers, settings.locale)) {
                Button(L.t(.auto, settings.locale)) {
                    Task { await tunnel.selectAuto() }
                }
                ForEach(tunnel.nodes.prefix(20)) { node in
                    Button("\(node.flag) \(node.title)") {
                        Task { await tunnel.select(node: node.name) }
                    }
                }
            }
            Divider()
        }

        Button(L.t(.navConnect, settings.locale)) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private enum MenuBarIcon {
    static let connected = image(connected: true)
    static let idle = image(connected: false)

    /// The logo's crescent, drawn at menu-bar size as a template image.
    private static func image(connected: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            let scale = rect.width / 24
            // A crescent: a filled disc with a second disc punched out of it.
            path.appendOval(in: NSRect(x: 4 * scale, y: 4 * scale,
                                       width: 16 * scale, height: 16 * scale))
            path.appendOval(in: NSRect(x: 10 * scale, y: 8 * scale,
                                       width: 15 * scale, height: 15 * scale))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            if !connected {
                // Disconnected reads as an outline rather than a solid mark.
                NSColor.black.withAlphaComponent(0.45).setFill()
                NSRect(origin: .zero, size: rect.size).fill(using: .destinationIn)
            }
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
