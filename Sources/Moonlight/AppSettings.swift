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
        launchAtLogin = preferences.launchAtLogin
    }

    func bumpHelperState() { helperGeneration += 1 }

    func toggleTheme() {
        withAnimation(Motion.enter) {
            theme = theme == .dark ? .light : .dark
        }
    }

    /// `SMAppService` is the modern registration and needs no login item plist,
    /// but it is macOS 13+ only — which is this app's floor anyway.
    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration fails for an app running outside /Applications, which
            // is normal during development and not worth an alert.
            NSLog("launch-at-login: \(error.localizedDescription)")
        }
    }
}
