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
    /// Liquid Glass, or flat surfaces on a solid canvas — see `GlassSurface`.
    @Published var liquidGlass: Bool { didSet { preferences.liquidGlass = liquidGlass } }
    /// Hours between automatic subscription updates, 0 for never; nil until
    /// chosen, meaning the service's own suggestion.
    @Published var autoUpdateHours: Int? {
        didSet { preferences.autoUpdateHours = autoUpdateHours }
    }

    /// Whether the app starts at login — as the *system* has it, not as a
    /// preference remembers it.
    ///
    /// It used to be only the preference, so the switch and reality drifted
    /// apart: a registration that failed (normal for an app run from outside
    /// /Applications) left the switch on with nothing registered, and an item
    /// registered by an older build stayed registered under a switch showing
    /// off. Now the switch is read from the system at launch, and after each
    /// change it settles on what the system actually did.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue, !settlingLaunchAtLogin else { return }
            applyLaunchAtLogin()
            let actual = Self.systemLaunchAtLogin ?? launchAtLogin
            preferences.launchAtLogin = actual
            if actual != launchAtLogin {
                settlingLaunchAtLogin = true
                launchAtLogin = actual
                settlingLaunchAtLogin = false
            }
        }
    }
    private var settlingLaunchAtLogin = false

    /// Bumped after the helper is installed or removed, so views that read
    /// `helperInstalled` (which is a filesystem check, not a published value)
    /// re-evaluate.
    @Published private(set) var helperGeneration = 0

    /// TUN was asked for somewhere without the helper, and the user was sent
    /// to Settings to install it: Settings points at the helper, and switches
    /// to TUN once it is in. Not saved — it means something only on the way
    /// there.
    @Published var tunAwaitingHelper = false

    var palette: Palette { theme == .dark ? .dark : .light }

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        theme = preferences.theme
        locale = preferences.locale
        notifications = preferences.notifications
        autoConnect = preferences.autoConnect
        menuBarIcon = preferences.menuBarIcon
        sidebarCollapsed = preferences.sidebarCollapsed
        liquidGlass = preferences.liquidGlass
        autoUpdateHours = preferences.autoUpdateHours
        launchAtLogin = Self.systemLaunchAtLogin ?? preferences.launchAtLogin
        preferences.launchAtLogin = launchAtLogin
    }

    /// What will actually happen at the next login.
    private static var systemLaunchAtLogin: Bool? {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: return true
            default: return false
            }
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
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
        let plist = Self.launchAgentURL
        let directory = plist.deletingLastPathComponent()

        guard launchAtLogin else {
            _ = try? FileManager.default.removeItem(at: plist)
            return
        }

        let executable = Bundle.main.executableURL?.path ?? ""
        let document: [String: Any] = [
            "Label": Self.launchAgentLabel,
            // The flag is how the app knows to start tucked away: a
            // LaunchAgent start carries no login-item launch event.
            "ProgramArguments": [executable, LoginLaunch.argument],
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

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist")
    }

}
