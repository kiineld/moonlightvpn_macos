import AppKit
import SwiftUI
import Combine
import MoonlightCore

/// The menu bar item, and the tray it opens.
///
/// AppKit rather than SwiftUI's `MenuBarExtra`, which is macOS 13+ — and this
/// app runs on Monterey. An `NSStatusItem` with an `NSPopover` covers every
/// version; the popover hosts ``TrayView``, which observes the tunnel directly,
/// so the speeds and latencies in it move while it is open.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private var item: NSStatusItem?
    private let tunnel: TunnelController
    private let settings: AppSettings
    private let popover = NSPopover()
    private let tray = TrayState()
    private var cancellables: Set<AnyCancellable> = []

    init(tunnel: TunnelController, settings: AppSettings) {
        self.tunnel = tunnel
        self.settings = settings
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let root = TrayView(tray: tray, openWindow: { [weak self] in self?.openWindow() })
            .environmentObject(tunnel)
            .environmentObject(settings)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: TrayMetrics.width, height: TrayMetrics.height)

        settings.$menuBarIcon
            .sink { [weak self] shown in self?.setVisible(shown) }
            .store(in: &cancellables)
        // The glyph is solid while connected and faint otherwise, so the bar
        // answers "is it on" without opening anything.
        tunnel.$state
            .sink { [weak self] state in self?.updateIcon(connected: state.isConnected) }
            .store(in: &cancellables)
        // Pinned, a click elsewhere leaves it open; only the item closes it.
        tray.$pinned
            .sink { [weak self] pinned in
                self?.popover.behavior = pinned ? .applicationDefined : .transient
            }
            .store(in: &cancellables)
        settings.$theme
            .sink { [weak self] theme in
                self?.popover.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
            }
            .store(in: &cancellables)
    }

    private func setVisible(_ shown: Bool) {
        guard shown else {
            popover.performClose(nil)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image(connected: tunnel.state.isConnected)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
    }

    private func updateIcon(connected: Bool) {
        item?.button?.image = MenuBarIcon.image(connected: connected)
    }

    // MARK: - Tray

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        // As tall as the design wants, but never past the screen it opens on.
        let room = (sender.window?.screen?.visibleFrame.height ?? 900) - 24
        popover.contentSize = NSSize(width: TrayMetrics.width, height: min(TrayMetrics.height, room))
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        // Key, so the search field takes typing without the app coming forward
        // and pulling its window up behind the tray.
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        tray.pinned = false
    }

    private func openWindow() {
        if !tray.pinned { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.mainWindowCandidate {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // SwiftUI discards a window once it is closed, so after "close to
            // menu bar" there was nothing here to bring forward and the item did
            // nothing. A reopen event — which is what opening our own bundle
            // sends a running app — is what makes it build a new one.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }
}
