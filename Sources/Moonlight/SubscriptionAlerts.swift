import Foundation
import Combine
import UserNotifications
import MoonlightCore

/// The notifications the settings screen promises: "об окончании подписки и
/// трафика".
///
/// The switch used to be stored and never read — nothing was ever posted,
/// while permission was asked for on every launch regardless of it. Now
/// permission is asked for only once the switch is on, and each warning is sent
/// once: an expiry warning per day left for a given end date, a traffic warning
/// per billing figure until the quota is topped up again.
@MainActor
final class SubscriptionAlerts {
    private let tunnel: TunnelController
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []

    private static let sentKey = "sentSubscriptionAlerts"
    /// Warn this many days out, and again each day after.
    private static let expiryDays = 3
    /// Warn once less than this share of the quota is left.
    private static let lowTraffic = 0.1

    init(tunnel: TunnelController, settings: AppSettings) {
        self.tunnel = tunnel
        self.settings = settings

        settings.$notifications
            .removeDuplicates()
            .sink { [weak self] on in if on { self?.authorize() } }
            .store(in: &cancellables)

        // Debounced: a refresh publishes the figures field by field.
        tunnel.$info
            .combineLatest(settings.$notifications)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] info, on in
                guard on else { return }
                self?.check(info)
            }
            .store(in: &cancellables)
    }

    /// `UNUserNotificationCenter.current()` traps in a process with no bundle,
    /// which is what a debug run straight out of `.build` is.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    private func authorize() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func check(_ info: SubscriptionInfo) {
        guard tunnel.hasSubscription else { return }
        let locale = settings.locale

        if let expire = info.expire, let days = info.daysLeft {
            let stamp = Int(expire.timeIntervalSince1970)
            if days == 0 {
                send(id: "expired-\(stamp)",
                     title: L.t(.notifyExpiredTitle, locale),
                     body: L.t(.notifyExpiredBody, locale))
            } else if days <= Self.expiryDays {
                send(id: "expiring-\(stamp)-\(days)",
                     title: L.t(.notifyExpiringTitle, locale),
                     body: L.t(.notifyExpiringBody, locale)
                        .replacingOccurrences(of: "{days}", with: Format.days(days, locale: locale)))
            }
        }

        if let total = info.total, total > 0, let used = info.used {
            let left = max(0, total - used)
            if left == 0 {
                send(id: "traffic-out-\(total)",
                     title: L.t(.notifyTrafficOutTitle, locale),
                     body: L.t(.notifyTrafficOutBody, locale))
            } else if Double(left) < Double(total) * Self.lowTraffic {
                send(id: "traffic-low-\(total)",
                     title: L.t(.notifyTrafficLowTitle, locale),
                     body: L.t(.notifyTrafficLowBody, locale)
                        .replacingOccurrences(of: "{left}", with: Format.bytes(left, locale: locale))
                        .replacingOccurrences(of: "{total}", with: Format.bytes(total, locale: locale)))
            } else {
                // Topped up: the next time it runs low is a new warning.
                forget { $0.hasPrefix("traffic-") }
            }
        }
    }

    private var sent: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(40)), forKey: Self.sentKey) }
    }

    private func forget(where matches: (String) -> Bool) {
        let kept = sent.filter { !matches($0) }
        if kept.count != sent.count { sent = kept }
    }

    /// Marked as sent only once it has actually been handed to the system, so
    /// a warning raised before permission was granted still arrives after.
    private func send(id: String, title: String, body: String) {
        guard !sent.contains(id), let center else { return }
        center.getNotificationSettings { status in
            guard status.authorizationStatus == .authorized
                    || status.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.sent.contains(id) else { return }
                self.sent.append(id)
            }
        }
    }
}
