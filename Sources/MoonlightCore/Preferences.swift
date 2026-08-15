import Foundation

/// Everything the app remembers between launches.
///
/// `UserDefaults` rather than a file: these are a couple of dozen scalars, and
/// the one thing that is genuinely sensitive — the subscription URL — is no more
/// exposed here than it would be in a plist this app wrote itself. The keys the
/// nodes come from are never stored at all; they live only in the generated
/// config, which is rewritten on every connect.
public final class Preferences: @unchecked Sendable {

    public static let shared = Preferences()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let subscriptionURL = "subscriptionURL"
        static let hwid = "hwid"
        static let selectedNode = "selectedNode"
        static let autoSelect = "autoSelect"
        static let theme = "theme"
        static let locale = "locale"
        static let tunnelMode = "tunnelMode"
        static let splitMode = "splitMode"
        static let splitApps = "splitApps"
        static let launchAtLogin = "launchAtLogin"
        static let menuBarIcon = "menuBarIcon"
        static let autoConnect = "autoConnect"
        static let notifications = "notifications"
        static let controllerPort = "controllerPort"
        static let mixedPort = "mixedPort"
        static let secret = "coreSecret"
        static let cachedInfo = "cachedSubscriptionInfo"
        static let proxySnapshot = "proxySnapshot"
    }

    public var subscriptionURL: String? {
        get { defaults.string(forKey: Key.subscriptionURL) }
        set { defaults.set(newValue, forKey: Key.subscriptionURL) }
    }

    /// A random UUID minted once. Not a hardware identifier — see
    /// ``DeviceIdentity``.
    public var hwid: String {
        if let existing = defaults.string(forKey: Key.hwid) { return existing }
        let minted = UUID().uuidString
        defaults.set(minted, forKey: Key.hwid)
        return minted
    }

    /// The API secret for this install's core.
    ///
    /// Generated once and kept, so a core left running by a crashed app is still
    /// reachable on the next launch and can be shut down rather than orphaned.
    public var coreSecret: String {
        if let existing = defaults.string(forKey: Key.secret) { return existing }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let minted = Data(bytes).base64EncodedString()
        defaults.set(minted, forKey: Key.secret)
        return minted
    }

    public var selectedNode: String? {
        get { defaults.string(forKey: Key.selectedNode) }
        set { defaults.set(newValue, forKey: Key.selectedNode) }
    }

    public var autoSelect: Bool {
        get { defaults.bool(forKey: Key.autoSelect) }
        set { defaults.set(newValue, forKey: Key.autoSelect) }
    }

    public var theme: Theme {
        get { Theme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .dark }
        set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    public var locale: AppLocale {
        get {
            if let stored = defaults.string(forKey: Key.locale),
               let value = AppLocale(rawValue: stored) { return value }
            // First launch follows the system, which for this audience is
            // usually Russian; the design is Russian-first either way.
            return Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
        }
        set { defaults.set(newValue.rawValue, forKey: Key.locale) }
    }

    public var tunnelMode: TunnelMode {
        get { TunnelMode(rawValue: defaults.string(forKey: Key.tunnelMode) ?? "") ?? .systemProxy }
        set { defaults.set(newValue.rawValue, forKey: Key.tunnelMode) }
    }

    public var splitMode: SplitMode {
        get { SplitMode(rawValue: defaults.string(forKey: Key.splitMode) ?? "") ?? .all }
        set { defaults.set(newValue.rawValue, forKey: Key.splitMode) }
    }

    /// Executable names, as `PROCESS-NAME` matches them.
    public var splitApps: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.splitApps) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.splitApps) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var menuBarIcon: Bool {
        get { defaults.object(forKey: Key.menuBarIcon) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.menuBarIcon) }
    }

    public var autoConnect: Bool {
        get { defaults.bool(forKey: Key.autoConnect) }
        set { defaults.set(newValue, forKey: Key.autoConnect) }
    }

    public var notifications: Bool {
        get { defaults.object(forKey: Key.notifications) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notifications) }
    }

    public var controllerPort: Int {
        get { defaults.object(forKey: Key.controllerPort) as? Int ?? 9797 }
        set { defaults.set(newValue, forKey: Key.controllerPort) }
    }

    public var mixedPort: Int {
        get { defaults.object(forKey: Key.mixedPort) as? Int ?? 7897 }
        set { defaults.set(newValue, forKey: Key.mixedPort) }
    }

    /// The last plan the panel reported, so the subscription screen has numbers
    /// to show before the first refresh of a launch completes.
    public var cachedInfo: SubscriptionInfo? {
        get {
            guard let data = defaults.data(forKey: Key.cachedInfo) else { return nil }
            return try? JSONDecoder().decode(SubscriptionInfo.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.cachedInfo)
        }
    }

    /// The machine's proxy settings from before this app touched them.
    ///
    /// Persisted rather than kept in memory: if the app is force-quit while
    /// connected, this is the only record of what to put back, and the next
    /// launch restores from it.
    public var proxySnapshot: SystemProxy.Snapshot? {
        get {
            guard let data = defaults.data(forKey: Key.proxySnapshot) else { return nil }
            return try? JSONDecoder().decode(SystemProxy.Snapshot.self, from: data)
        }
        set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.proxySnapshot)
        }
    }
}

public enum Theme: String, Codable, CaseIterable, Sendable {
    case dark
    case light
}
