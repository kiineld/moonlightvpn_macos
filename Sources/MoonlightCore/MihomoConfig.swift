import Foundation
import Yams

/// Builds the config mihomo actually runs, from the config the panel serves.
///
/// The panel's document is kept **verbatim** — its `proxies`, `proxy-groups`,
/// `rules` and `dns` are usually better tuned than anything generated here, and
/// a panel that ships a `url-test` balancer or a `geosite:category-ru` direct
/// rule means it. This type overrides only what the client must own:
///
/// - the RESTful API address and secret, which is how the app talks to the core
/// - the local listener port
/// - `allow-lan: false` and a loopback bind — this is a single-machine client,
///   and an unbound listener is an open proxy on the network
/// - the TUN block, when the tunnel runs in TUN mode
/// - split-tunnel rules, prepended (see ``splitRules(mode:processes:)``)
public struct MihomoConfig {

    public struct Overrides: Sendable {
        public var controllerPort: Int
        public var secret: String
        public var mixedPort: Int
        public var mode: TunnelMode
        public var splitMode: SplitMode
        /// Every rule the split screen contributes — the app toggles and the
        /// hand-written ones alike.
        public var splitRules: [SplitRule]
        public var logLevel: String
        /// Where mihomo keeps its geo databases and cache.
        public var dataDirectory: String

        public init(
            controllerPort: Int = 9797,
            secret: String,
            mixedPort: Int = 7897,
            mode: TunnelMode = .systemProxy,
            splitMode: SplitMode = .all,
            splitRules: [SplitRule] = [],
            logLevel: String = "warning",
            dataDirectory: String
        ) {
            self.controllerPort = controllerPort
            self.secret = secret
            self.mixedPort = mixedPort
            self.mode = mode
            self.splitMode = splitMode
            self.splitRules = splitRules
            self.logLevel = logLevel
            self.dataDirectory = dataDirectory
        }
    }

    /// The sub-rule name the `.only` split mode delegates the panel's routing to.
    static let panelSubRule = "moonlight-panel"

    public enum Failure: LocalizedError {
        case notAMapping
        case noProxies

        public var errorDescription: String? {
            switch self {
            case .notAMapping: return "Subscription is not a YAML mapping"
            case .noProxies: return "Subscription contains no proxies"
            }
        }
    }

    /// Grafts `overrides` onto the panel's YAML and returns the result.
    public static func build(panelYAML: String, overrides: Overrides) throws -> String {
        guard var root = try Yams.load(yaml: panelYAML) as? [String: Any] else {
            throw Failure.notAMapping
        }
        let proxies = root["proxies"] as? [[String: Any]] ?? []
        guard !proxies.isEmpty else { throw Failure.noProxies }

        // ── Client-owned general settings ───────────────────────────────────
        root["mixed-port"] = overrides.mixedPort
        root["external-controller"] = "127.0.0.1:\(overrides.controllerPort)"
        root["secret"] = overrides.secret
        root["log-level"] = overrides.logLevel
        root["mode"] = "rule"
        root["allow-lan"] = false
        root["bind-address"] = "127.0.0.1"
        // Ports the panel may have set are removed rather than left listening:
        // one mixed port is the whole surface this client needs.
        for key in ["port", "socks-port", "redir-port", "tproxy-port", "external-ui",
                    "external-controller-tls", "external-controller-unix"] {
            root.removeValue(forKey: key)
        }
        // Always on. It costs a `libproc` lookup per connection, which is cheap,
        // and two things depend on it: `PROCESS-*` split rules, and the
        // connections screen — whose entire question is *which program* is going
        // where. Switching it off when no process rule happened to be configured
        // left that screen showing every connection as "—".
        root["find-process-mode"] = "always"

        // ── Groups ──────────────────────────────────────────────────────────
        // A config from the share-link fallback has no groups; one from a panel
        // template almost always does, and those are left exactly as they are.
        var groups = root["proxy-groups"] as? [[String: Any]] ?? []
        if groups.isEmpty {
            groups = defaultGroups(proxyNames: proxies.compactMap { $0["name"] as? String })
            root["proxy-groups"] = groups
        }

        // ── Routing ─────────────────────────────────────────────────────────
        var rules = root["rules"] as? [String] ?? []
        if rules.isEmpty {
            rules = ["MATCH,\(Self.defaultSelector)"]
        }
        root["rules"] = applySplit(
            rules: rules,
            mode: overrides.splitMode,
            splitRules: overrides.splitRules,
            selector: primarySelectorName(groups: groups, rules: rules),
            root: &root
        )

        // ── TUN ─────────────────────────────────────────────────────────────
        if overrides.mode == .tun {
            root["tun"] = tunBlock()
            // TUN without DNS hijacking leaks every lookup to the resolver the
            // machine had before the interface came up.
            root["dns"] = dnsBlock(existing: root["dns"] as? [String: Any])
        } else {
            root.removeValue(forKey: "tun")
        }

        return try Yams.dump(object: root, sortKeys: true)
    }

    /// A minimal config that carries just a proxy list — the shape the
    /// share-link fallback produces before ``build(panelYAML:overrides:)`` runs.
    public static func yamlFromProxies(_ proxies: [[String: Any]]) -> String {
        let names = proxies.compactMap { $0["name"] as? String }
        let root: [String: Any] = [
            "proxies": proxies,
            "proxy-groups": defaultGroups(proxyNames: names),
            "rules": ["MATCH,\(defaultSelector)"],
        ]
        return (try? Yams.dump(object: root, sortKeys: true)) ?? ""
    }

    public static let defaultSelector = "MOONLIGHT"
    public static let defaultAutoGroup = "MOONLIGHT-AUTO"

    public static func defaultGroups(proxyNames: [String]) -> [[String: Any]] {
        [
            [
                "name": defaultSelector,
                "type": "select",
                "proxies": [defaultAutoGroup] + proxyNames,
            ],
            [
                "name": defaultAutoGroup,
                "type": "url-test",
                "proxies": proxyNames,
                "url": MihomoAPI.probeURL,
                "interval": 300,
                "tolerance": 50,
            ],
        ]
    }

    /// The group the app drives when the user picks a node.
    ///
    /// A panel names its groups whatever it likes, so the group is found the way
    /// the config itself points at it: the target of the catch-all `MATCH` rule,
    /// falling back to the first `select` group. Guessing by name would break on
    /// any panel that localises its group labels.
    public static func primarySelectorName(groups: [[String: Any]], rules: [String]) -> String {
        if let match = rules.last(where: { $0.uppercased().hasPrefix("MATCH,") }) {
            let target = match.dropFirst("MATCH,".count).trimmingCharacters(in: .whitespaces)
            if groups.contains(where: { $0["name"] as? String == target }) { return target }
        }
        if let selector = groups.first(where: { ($0["type"] as? String) == "select" }),
           let name = selector["name"] as? String {
            return name
        }
        return groups.first?["name"] as? String ?? defaultSelector
    }

    // MARK: - Split tunnelling

    /// Composes the split mode with the panel's own routing.
    ///
    /// The three modes are not symmetric, because preserving the panel's rules
    /// means something different in each:
    ///
    /// - **all** — the panel's rules, untouched.
    /// - **except** — the split rules are prepended pointing at `DIRECT`. This
    ///   composes cleanly: what they match never reaches the panel's rules, and
    ///   everything else sees them exactly as written.
    /// - **only** — what the split rules match is handed to the panel's rules
    ///   through a `SUB-RULE`, and everything else falls to `MATCH,DIRECT`.
    ///   Pointing them straight at the selector instead would work, but it would
    ///   force *all* of that traffic through the node — including the hosts the
    ///   panel deliberately routes direct — so a selected browser would lose the
    ///   panel's split for local sites.
    ///
    /// An empty selection in `.only` mode falls back to tunnelling everything:
    /// an empty allow-list routes nothing at all, which reads as a broken VPN
    /// rather than as a configuration choice.
    public static func applySplit(
        rules: [String],
        mode: SplitMode,
        splitRules: [SplitRule],
        selector: String,
        root: inout [String: Any]
    ) -> [String] {
        let active = splitRules.filter {
            $0.enabled && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }

        switch mode {
        case .all:
            return rules

        case .except:
            guard !active.isEmpty else { return rules }
            return active.map { $0.line(target: "DIRECT") } + rules

        case .only:
            guard !active.isEmpty else { return rules }
            var subRules = root["sub-rules"] as? [String: Any] ?? [:]
            subRules[panelSubRule] = rules
            root["sub-rules"] = subRules
            return active.map { "SUB-RULE,\($0.matcher()),\(panelSubRule)" }
                + ["MATCH,DIRECT"]
        }
    }

    // MARK: - TUN

    public static func tunBlock() -> [String: Any] {
        [
            "enable": true,
            // No `device`: macOS requires a `utun` name, and a hardcoded one
            // collides with whichever VPN client already holds it. Letting the
            // core pick the first free index is the only way to be sure.
            // `mixed` is the recommended stack: gvisor's userspace TCP with the
            // system stack's UDP, which avoids gvisor's UDP throughput cost.
            "stack": "mixed",
            "auto-route": true,
            "auto-detect-interface": true,
            "strict-route": false,
            "dns-hijack": ["any:53", "tcp://any:53"],
            "mtu": 1500,
        ]
    }

    /// DNS for TUN mode.
    ///
    /// A panel's own `dns` block is kept if it has one — it may point at a
    /// resolver inside the tunnel on purpose. Only the fields TUN needs are
    /// forced on: without `enable`, mihomo does not answer the queries
    /// `dns-hijack` redirects to it, and the tunnel resolves nothing.
    static func dnsBlock(existing: [String: Any]?) -> [String: Any] {
        var dns = existing ?? [:]
        dns["enable"] = true
        dns["ipv6"] = dns["ipv6"] ?? false
        dns["listen"] = dns["listen"] ?? "127.0.0.1:53535"
        // A fake-ip range keeps DNS out of the round trip for proxied hosts.
        dns["enhanced-mode"] = dns["enhanced-mode"] ?? "fake-ip"
        dns["fake-ip-range"] = dns["fake-ip-range"] ?? "198.18.0.1/16"
        if dns["nameserver"] == nil {
            dns["nameserver"] = ["https://1.1.1.1/dns-query", "https://dns.google/dns-query"]
        }
        return dns
    }
}
