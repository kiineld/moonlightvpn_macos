import Foundation
import MoonlightCore

/// Deployment-specific endpoints.
///
/// Read from `Info.plist` rather than hardcoded, so a fork points these at its
/// own bot and channel by editing `scripts/build-app.sh` — no source change and
/// no rebuild of the Swift.
public enum AppConfig {
    public static var telegramBotURL: URL { url("MLTelegramBotURL", "https://t.me/") }
    public static var telegramChannelURL: URL { url("MLTelegramChannelURL", "https://t.me/") }
    public static var supportURL: URL { url("MLSupportURL", "https://t.me/") }
    public static var releasesURL: URL {
        url("MLReleasesURL", "https://github.com/kiineld/moonlightvpn_macos/releases/latest")
    }

    public static var version: String { Bundle.main.appVersion }
    public static let deviceName = TunnelController.hardwareModel()

    private static func url(_ key: String, _ fallback: String) -> URL {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return URL(string: value?.isEmpty == false ? value! : fallback)!
    }
}
