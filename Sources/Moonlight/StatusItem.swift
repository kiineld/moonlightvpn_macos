import AppKit
import Combine
import MoonlightCore

/// The menu bar item.
///
/// AppKit rather than SwiftUI's `MenuBarExtra`, which is macOS 13+ — and this
/// app runs on Monterey. One `NSStatusItem` covers every version, and the menu
/// is rebuilt each time it opens, so it reports the tunnel's state at the moment
/// it is read rather than whenever SwiftUI last thought to re-render it.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let tunnel: TunnelController
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []

    init(tunnel: TunnelController, settings: AppSettings) {
        self.tunnel = tunnel
        self.settings = settings
        super.init()

        settings.$menuBarIcon
            .sink { [weak self] shown in self?.setVisible(shown) }
            .store(in: &cancellables)
        // The glyph is solid while connected and faint otherwise, so the bar
        // answers "is it on" without opening anything.
        tunnel.$state
            .sink { [weak self] state in self?.updateIcon(connected: state.isConnected) }
            .store(in: &cancellables)
    }

    private func setVisible(_ shown: Bool) {
        guard shown else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.image(connected: tunnel.state.isConnected)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
    }

    private func updateIcon(connected: Bool) {
        item?.button?.image = MenuBarIcon.image(connected: connected)
    }

    // MARK: - Menu

    /// Rebuilt on every open: the traffic figures and the node list are only
    /// correct at the moment they are read.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let locale = settings.locale

        let toggle = NSMenuItem(
            title: L.t(tunnel.state.isConnected ? .hintDisconnect : .hintConnect, locale),
            action: #selector(toggleTunnel), keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = tunnel.hasSubscription && !tunnel.state.isBusy
        menu.addItem(toggle)

        if tunnel.state.isConnected {
            menu.addItem(info("↓ \(Format.rate(tunnel.rateDown, locale: locale))   ↑ \(Format.rate(tunnel.rateUp, locale: locale))"))
            menu.addItem(info(Format.duration(tunnel.uptime)))
        }
        if let days = tunnel.info.daysLeft {
            menu.addItem(info("\(L.t(.remainingCaps, locale)): \(Format.days(days, locale: locale))"))
        }

        if !tunnel.nodes.isEmpty {
            menu.addItem(.separator())
            let servers = NSMenuItem(title: L.t(.servers, locale), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for node in tunnel.nodes.prefix(25) {
                let title = [node.flag, node.title].compactMap { $0 }.joined(separator: " ")
                let entry = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = node.name
                entry.state = node.name == tunnel.selectedNode ? .on : .off
                submenu.addItem(entry)
            }
            servers.submenu = submenu
            menu.addItem(servers)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: L.t(.navConnect, locale),
                              action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: L.t(.quit, locale),
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleTunnel() { Task { await tunnel.toggle() } }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task { await tunnel.select(node: name) }
    }

    @objc private func openWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
