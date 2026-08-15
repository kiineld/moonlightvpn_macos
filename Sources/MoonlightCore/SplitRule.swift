import Foundation

/// One user-authored routing rule.
///
/// The app list on the split screen is a convenience over `PROCESS-NAME`; this
/// is the general form, so a rule can also match a process the scanner never
/// found, a domain, a regex, a CIDR or a port. Every kind here is validated
/// against the real core in the test suite, both as a plain rule and inside the
/// `SUB-RULE` matcher that "only these" mode uses — mihomo accepts different
/// grammars in the two positions, and a rule that only works in one is a config
/// the core refuses to load.
public struct SplitRule: Identifiable, Hashable, Codable, Sendable {

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case processName = "PROCESS-NAME"
        case processNameRegex = "PROCESS-NAME-REGEX"
        case processPath = "PROCESS-PATH"
        case processPathRegex = "PROCESS-PATH-REGEX"
        case domain = "DOMAIN"
        case domainSuffix = "DOMAIN-SUFFIX"
        case domainKeyword = "DOMAIN-KEYWORD"
        case domainRegex = "DOMAIN-REGEX"
        case ipCIDR = "IP-CIDR"
        case geosite = "GEOSITE"
        case geoip = "GEOIP"
        case dstPort = "DST-PORT"

        /// Whether the core has to identify the process behind a connection to
        /// evaluate this. Only TUN mode can — under a system proxy the core is
        /// handed a socket with no process behind it. Domain and address rules
        /// work in both modes, which is why the warning is per-rule rather than
        /// per-screen.
        public var needsProcessMatching: Bool {
            switch self {
            case .processName, .processNameRegex, .processPath, .processPathRegex:
                return true
            default:
                return false
            }
        }

        /// Address rules carry `no-resolve` so a domain is not resolved just to
        /// test it against a CIDR — that would send a DNS query for every
        /// connection and defeat the point of matching on address.
        var wantsNoResolve: Bool {
            self == .ipCIDR || self == .geoip
        }

        public var placeholder: String {
            switch self {
            case .processName: return "Telegram"
            case .processNameRegex: return "(?i).*chrome.*"
            case .processPath: return "/Applications/Safari.app/Contents/MacOS/Safari"
            case .processPathRegex: return "(?i).*/steam.*"
            case .domain: return "example.com"
            case .domainSuffix: return "openai.com"
            case .domainKeyword: return "google"
            case .domainRegex: return #"^.*\.discord\.(com|gg)$"#
            case .ipCIDR: return "192.168.1.0/24"
            case .geosite: return "youtube"
            case .geoip: return "ru"
            case .dstPort: return "443"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var value: String
    public var enabled: Bool
    /// Set for rules the app list generated, so removing an app removes its rule
    /// and a hand-written rule for the same process is left alone.
    public var appExecutable: String?

    public init(
        id: UUID = UUID(), kind: Kind, value: String,
        enabled: Bool = true, appExecutable: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.enabled = enabled
        self.appExecutable = appExecutable
    }

    public var isFromAppList: Bool { appExecutable != nil }

    /// The rule as mihomo's rule grammar writes it, pointed at `target`.
    public func line(target: String) -> String {
        let suffix = kind.wantsNoResolve ? ",no-resolve" : ""
        return "\(kind.rawValue),\(value),\(target)\(suffix)"
    }

    /// The rule as a `SUB-RULE` matcher expression.
    ///
    /// `no-resolve` is *not* included: it is a rule parameter, and the matcher
    /// position does not take one.
    public func matcher() -> String {
        "(\(kind.rawValue),\(value))"
    }

    // MARK: Validation

    public enum Invalid: LocalizedError, Equatable {
        case empty
        case containsComma
        case badRegex(String)
        case badPort
        case badCIDR

        public var errorDescription: String? {
            switch self {
            case .empty: return "The rule has no value"
            case .containsComma:
                return "A value cannot contain a comma — mihomo splits rules on it"
            case .badRegex(let why): return "Not a valid regular expression: \(why)"
            case .badPort: return "Not a valid port"
            case .badCIDR: return "Not a valid CIDR block, e.g. 192.168.1.0/24"
            }
        }
    }

    /// Checked before a rule can be added, because a bad one does not fail
    /// alone: mihomo refuses the whole config, so the tunnel stops working
    /// rather than the rule being skipped.
    public static func validate(kind: Kind, value: String) -> Invalid? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        // mihomo parses a rule by splitting on commas, so a comma anywhere in
        // the value silently turns into a different rule.
        guard !value.contains(",") else { return .containsComma }

        switch kind {
        case .processNameRegex, .processPathRegex, .domainRegex:
            do {
                _ = try NSRegularExpression(pattern: value)
            } catch {
                return .badRegex(error.localizedDescription)
            }
        case .dstPort:
            guard let port = Int(value), (1...65535).contains(port) else { return .badPort }
        case .ipCIDR:
            let parts = value.split(separator: "/")
            guard parts.count == 2, let bits = Int(parts[1]), (0...128).contains(bits),
                  !parts[0].isEmpty else { return .badCIDR }
        default:
            break
        }
        return nil
    }
}
