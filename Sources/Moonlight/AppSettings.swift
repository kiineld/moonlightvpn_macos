import SwiftUI
import ServiceManagement
import MoonlightCore
import MoonlightDesign

/// The preferences the UI binds to directly.
///
/// Separate from ``Preferences`` because these need to be observable: flipping
/// the theme or the language has to repaint every screen, which a plain
/// `UserDefaults` wrapper cannot drive.
@MainActor
final class AppSettings: ObservableObject {
    private let preferences: Preferences

    @Published var theme: Theme { didSet { preferences.theme = theme } }
    @Published var locale: AppLocale { didSet { preferences.locale = locale } }
    @Published var notifications: Bool { didSet { preferences.notifications = notifications } }
    @Published var autoConnect: Bool { didSet { preferences.autoConnect = autoConnect } }
    @Published var menuBarIcon: Bool { didSet { preferences.menuBarIcon = menuBarIcon } }
    @Published var sidebarCollapsed: Bool {
        didSet { preferences.sidebarCollapsed = sidebarCollapsed }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != preferences.launchAtLogin else { return }
            preferences.launchAtLogin = launchAtLogin
            applyLaunchAtLogin()
        }
    }

    /// Bumped after the helper is installed or removed, so views that read
    /// `helperInstalled` (which is a filesystem check, not a published value)
    /// re-evaluate.
    @Published private(set) var helperGeneration = 0

    var palette: Palette { theme == .dark ? .dark : .light }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        theme = preferences.theme
        locale = preferences.locale
        notifications = preferences.notifications
        autoConnect = preferences.autoConnect
        menuBarIcon = preferences.menuBarIcon
        sidebarCollapsed = preferences.sidebarCollapsed
        launchAtLogin = preferences.launchAtLogin
    }

    func bumpHelperState() { helperGeneration += 1 }

    func toggleTheme() {
        withAnimation(Motion.enter) {
            theme = theme == .dark ? .light : .dark
        }
    }

    /// Registers or removes the login item.
    ///
    /// `SMAppService` is the modern, plist-free way to do this and is macOS 13+.
    /// On Monterey the equivalent is a LaunchAgent the app writes itself —
    /// `SMLoginItemSetEnabled` would need a separate helper bundle, which is far
    /// more machinery for the same result.
    private func applyLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return
            } catch {
                // Registration fails for an app running outside /Applications,
                // which is normal during development.
                NSLog("launch-at-login: \(error.localizedDescription)")
                return
            }
        }
        applyLaunchAgent()
    }

    /// The macOS 12 path: a LaunchAgent in the user's own directory.
    private func applyLaunchAgent() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plist = directory.appendingPathComponent("\(Self.launchAgentLabel).plist")

        guard launchAtLogin else {
            _ = try? FileManager.default.removeItem(at: plist)
            return
        }

        let executable = Bundle.main.executableURL?.path ?? ""
        let document: [String: Any] = [
            "Label": Self.launchAgentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Not KeepAlive: this starts the app at login, it does not resurrect
            // an app the user deliberately quit.
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: document, format: .xml, options: 0
            )
            try data.write(to: plist)
        } catch {
            NSLog("launch-at-login: \(error.localizedDescription)")
        }
    }

    private static let launchAgentLabel = "vpn.moonlight.desktop.login"

}
