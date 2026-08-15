import Foundation

/// A node the tunnel can select, as it appears in the mihomo config the panel
/// serves. `name` is the identity: it is what the RESTful API takes to switch a
/// selector, so it must round-trip verbatim, flag emoji and all.
public struct Node: Identifiable, Hashable, Codable, Sendable {
    public var name: String
    public var type: String
    public var server: String?
    /// Latency in milliseconds, from the last probe. Nil means never measured —
    /// which the UI shows as `n/a`, not as `0 ms`.
    public var latency: Int?
    /// True for a `url-test`, `fallback` or `load-balance` group the panel put in
    /// its selector. Those are choices the operator built deliberately — a
    /// balancer across several nodes, or an auto-picker — and hiding them leaves
    /// the user picking raw nodes the panel never meant to offer directly.
    public var isGroup: Bool

    public var id: String { name }

    public init(
        name: String, type: String, server: String? = nil,
        latency: Int? = nil, isGroup: Bool = false, protocolLabel: String? = nil
    ) {
        self.protocolLabel = protocolLabel
        self.name = name
        self.type = type
        self.server = server
        self.latency = latency
        self.isGroup = isGroup
    }

    /// How the panel writes this node's transport — "VLESS Reality",
    /// "Hysteria2 TLS". Read from the subscription rather than from the API,
    /// which reports only the bare type.
    public var protocolLabel: String?

    private static let regionalIndicators = UInt32(0x1F1E6)...UInt32(0x1F1FF)

    private var flagScalars: [Unicode.Scalar] {
        Array(name.unicodeScalars.prefix { Self.regionalIndicators.contains($0.value) })
    }

    /// The flag emoji a panel conventionally prefixes to a node name, split off
    /// so the design's separate flag column can render it.
    ///
    /// Nil for an entry with no flag — a cross-country balancer or an
    /// auto-picker — so the row can show a mark instead of an invented one.
    public var flag: String? {
        let scalars = flagScalars
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }

    /// The country the flag stands for, in the app's language.
    ///
    /// A flag emoji is two regional indicators, which are just `A`–`Z` shifted
    /// into their own block — so the ISO code falls straight out of it and
    /// Foundation localises the name. No table to keep up to date.
    public func country(_ locale: AppLocale) -> String? {
        let scalars = flagScalars
        guard scalars.count == 2 else { return nil }
        let code = String(scalars.map {
            Character(Unicode.Scalar($0.value - Self.regionalIndicators.lowerBound + 65)!)
        })
        return Locale(identifier: locale == .ru ? "ru_RU" : "en_US")
            .localizedString(forRegionCode: code)
    }

    /// The node name with the leading flag removed.
    public var title: String {
        let stripped = name.unicodeScalars.drop { Self.regionalIndicators.contains($0.value) }
        let title = String(String.UnicodeScalarView(stripped)).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? name : title
    }

    /// "Швеция · VLESS Reality" — the row's second line. Whatever is known,
    /// joined; a group with no flag simply shows its transport.
    public func subtitle(_ locale: AppLocale) -> String {
        [country(locale), protocolLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

/// What the panel reports about the subscription itself.
///
/// Every field is optional because a missing field has to read as *unknown*
/// rather than as zero — a subscription whose panel omits `total` is unlimited,
/// and showing "0 GB" for it would be a lie the user acts on.
public struct SubscriptionInfo: Equatable, Codable, Sendable {
    public var title: String?
    public var upload: Int64?
    public var download: Int64?
    public var total: Int64?
    public var expire: Date?
    public var deviceLimit: Int?
    public var devicesUsed: Int?

    public init(
        title: String? = nil, upload: Int64? = nil, download: Int64? = nil,
        total: Int64? = nil, expire: Date? = nil,
        deviceLimit: Int? = nil, devicesUsed: Int? = nil
    ) {
        self.title = title
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
        self.deviceLimit = deviceLimit
        self.devicesUsed = devicesUsed
    }

    public var used: Int64? {
        guard upload != nil || download != nil else { return nil }
        return (upload ?? 0) + (download ?? 0)
    }

    public var daysLeft: Int? {
        guard let expire else { return nil }
        let seconds = expire.timeIntervalSinceNow
        return seconds <= 0 ? 0 : Int(ceil(seconds / 86_400))
    }

    /// Fraction of the quota consumed, 0…1. Nil when the plan is unlimited.
    public var usedFraction: Double? {
        guard let total, total > 0, let used else { return nil }
        return min(1, max(0, Double(used) / Double(total)))
    }

    public var isActive: Bool {
        guard let expire else { return true }
        return expire > Date()
    }
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String)

    public var isConnected: Bool { self == .connected }
    public var isBusy: Bool { self == .connecting || self == .disconnecting }
}

/// How traffic reaches the tunnel.
///
/// These are genuinely different mechanisms, not a preference: system proxy
/// rewrites the machine's proxy settings and only captures apps that honour
/// them, while TUN takes a virtual interface and captures everything. Only TUN
/// can enforce per-app rules, which is why the split-tunnel screen is inert
/// without it.
public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    case systemProxy
    case tun
}

/// Which traffic goes through the tunnel.
public enum SplitMode: String, Codable, CaseIterable, Sendable {
    /// Everything.
    case all
    /// Only the selected processes; everything else goes direct.
    case only
    /// The selected processes go direct; everything else is tunnelled.
    case except
}

/// An installed application, addressed by the executable name mihomo's
/// `PROCESS-NAME` rules match on — not by bundle id, which mihomo never sees.
public struct AppEntry: Identifiable, Hashable, Codable, Sendable {
    public var name: String
    public var executable: String
    public var bundleID: String?
    public var path: String

    public var id: String { executable }

    public init(name: String, executable: String, bundleID: String? = nil, path: String) {
        self.name = name
        self.executable = executable
        self.bundleID = bundleID
        self.path = path
    }
}
