import Foundation

/// Converts `vless://`, `vmess://`, `trojan://` and `ss://` share links into
/// mihomo proxy entries.
///
/// This is the **fallback** path, used only when a panel serves no Clash config
/// at all (see ``SubscriptionClient``). The format itself throws information
/// away — proxy groups, `url-test` balancers, per-node routing and DNS all
/// flatten to one URI per node — so a config built from here is strictly poorer
/// than one the panel wrote. It is still better than nothing, and for the common
/// case of a flat list of VLESS Reality nodes it is lossless.
public enum ShareLink {

    /// Splits a subscription body into individual links.
    ///
    /// The body is detected by content rather than by `Content-Type`, because
    /// panels mislabel it. Three shapes are accepted: base64 (standard or
    /// URL-safe, padded or not), plain newline-separated links, and a body that
    /// is base64 of newline-separated links.
    public static func decodeList(_ body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let direct = split(trimmed)
        if !direct.isEmpty { return direct }

        if let decoded = decodeBase64(trimmed) {
            return split(decoded)
        }
        return []
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                ["vless://", "vmess://", "trojan://", "ss://"]
                    .contains { line.lowercased().hasPrefix($0) }
            }
    }

    static func decodeBase64(_ text: String) -> String? {
        var payload = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .filter { !$0.isWhitespace }
        // Restore padding the panel may have stripped.
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload),
              let decoded = String(data: data, encoding: .utf8) else { return nil }
        return decoded
    }

    /// A single link as a mihomo proxy mapping, or nil if the scheme or its
    /// parameters are ones mihomo cannot express.
    public static func mihomoProxy(_ link: String) -> [String: Any]? {
        let scheme = link.prefix(while: { $0 != ":" }).lowercased()
        switch scheme {
        case "vless": return vless(link)
        case "vmess": return vmess(link)
        case "trojan": return trojan(link)
        case "ss": return shadowsocks(link)
        default: return nil
        }
    }

    // MARK: - vless

    private static func vless(_ link: String) -> [String: Any]? {
        guard let parts = URIParts(link), let uuid = parts.user else { return nil }
        var proxy: [String: Any] = [
            "name": parts.name,
            "type": "vless",
            "server": parts.host,
            "port": parts.port,
            "uuid": uuid,
            "udp": true,
        ]
        let query = parts.query

        if let flow = query["flow"], !flow.isEmpty { proxy["flow"] = flow }
        if let fingerprint = query["fp"], !fingerprint.isEmpty {
            proxy["client-fingerprint"] = fingerprint
        }

        let security = query["security"]?.lowercased() ?? "none"
        if security == "tls" || security == "reality" {
            proxy["tls"] = true
            if let sni = query["sni"] ?? query["peer"], !sni.isEmpty {
                proxy["servername"] = sni
            }
            if let alpn = query["alpn"], !alpn.isEmpty {
                proxy["alpn"] = alpn.split(separator: ",").map(String.init)
            }
        }
        if security == "reality" {
            // Reality without a public key is unusable — mihomo will refuse the
            // config rather than fall back to plain TLS, so drop the node here
            // where the reason is still visible.
            guard let publicKey = query["pbk"], !publicKey.isEmpty else { return nil }
            var reality: [String: Any] = ["public-key": publicKey]
            if let shortID = query["sid"], !shortID.isEmpty { reality["short-id"] = shortID }
            proxy["reality-opts"] = reality
            // Reality assumes a browser fingerprint; mihomo errors without one.
            if proxy["client-fingerprint"] == nil { proxy["client-fingerprint"] = "chrome" }
        }
        if query["allowInsecure"] == "1" { proxy["skip-cert-verify"] = true }

        applyTransport(&proxy, query: query, host: parts.host)
        return proxy
    }

    // MARK: - vmess

    private static func vmess(_ link: String) -> [String: Any]? {
        // vmess is the odd one out: the whole payload is base64 JSON rather than
        // a URI with a query string.
        let payload = String(link.dropFirst("vmess://".count))
        guard let json = decodeBase64(payload),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = string(object["add"]), !host.isEmpty,
              let uuid = string(object["id"]), !uuid.isEmpty,
              let port = int(object["port"]) else { return nil }

        var proxy: [String: Any] = [
            "name": string(object["ps"]) ?? "\(host):\(port)",
            "type": "vmess",
            "server": host,
            "port": port,
            "uuid": uuid,
            "alterId": int(object["aid"]) ?? 0,
            "cipher": string(object["scy"]) ?? "auto",
            "udp": true,
        ]
        if (string(object["tls"]) ?? "").lowercased() == "tls" {
            proxy["tls"] = true
            if let sni = string(object["sni"]), !sni.isEmpty { proxy["servername"] = sni }
        }

        var query: [String: String] = [:]
        query["type"] = string(object["net"])
        query["path"] = string(object["path"])
        query["host"] = string(object["host"])
        query["serviceName"] = string(object["path"])
        applyTransport(&proxy, query: query, host: host)
        return proxy
    }

    // MARK: - trojan

    private static func trojan(_ link: String) -> [String: Any]? {
        guard let parts = URIParts(link), let password = parts.user else { return nil }
        var proxy: [String: Any] = [
            "name": parts.name,
            "type": "trojan",
            "server": parts.host,
            "port": parts.port,
            "password": password,
            "udp": true,
        ]
        let query = parts.query
        if let sni = query["sni"] ?? query["peer"], !sni.isEmpty { proxy["sni"] = sni }
        if let alpn = query["alpn"], !alpn.isEmpty {
            proxy["alpn"] = alpn.split(separator: ",").map(String.init)
        }
        if query["allowInsecure"] == "1" { proxy["skip-cert-verify"] = true }
        applyTransport(&proxy, query: query, host: parts.host)
        return proxy
    }

    // MARK: - shadowsocks

    private static func shadowsocks(_ link: String) -> [String: Any]? {
        guard let parts = URIParts(link) else { return nil }

        // Two encodings are in the wild: `ss://base64(method:password)@host:port`
        // and `ss://method:password@host:port` with the userinfo percent-encoded.
        var method: String?
        var password: String?
        if let user = parts.user {
            if let decoded = decodeBase64(user), decoded.contains(":") {
                let split = decoded.split(separator: ":", maxSplits: 1)
                method = String(split[0]); password = String(split[1])
            } else if user.contains(":") {
                let split = user.split(separator: ":", maxSplits: 1)
                method = String(split[0]); password = String(split[1])
            }
        }
        guard let method, let password else { return nil }

        return [
            "name": parts.name,
            "type": "ss",
            "server": parts.host,
            "port": parts.port,
            "cipher": method,
            "password": password,
            "udp": true,
        ]
    }

    // MARK: -

    /// Transport is shared across vless/vmess/trojan and is where most malformed
    /// links go wrong, so it lives in one place.
    private static func applyTransport(
        _ proxy: inout [String: Any], query: [String: String], host: String
    ) {
        let network = (query["type"] ?? "tcp").lowercased()
        switch network {
        case "ws":
            proxy["network"] = "ws"
            var options: [String: Any] = [:]
            if let path = query["path"], !path.isEmpty { options["path"] = path }
            // A ws Host header defaults to the SNI, not to the dial address —
            // sending the raw IP here is what breaks CDN-fronted nodes.
            let wsHost = query["host"] ?? proxy["servername"] as? String
            if let wsHost, !wsHost.isEmpty { options["headers"] = ["Host": wsHost] }
            if !options.isEmpty { proxy["ws-opts"] = options }

        case "grpc":
            proxy["network"] = "grpc"
            if let service = query["serviceName"], !service.isEmpty {
                proxy["grpc-opts"] = ["grpc-service-name": service]
            }

        case "http", "h2":
            proxy["network"] = "h2"
            var options: [String: Any] = [:]
            if let path = query["path"], !path.isEmpty { options["path"] = path }
            if let httpHost = query["host"], !httpHost.isEmpty {
                options["host"] = httpHost.split(separator: ",").map(String.init)
            }
            if !options.isEmpty { proxy["h2-opts"] = options }

        default:
            proxy["network"] = "tcp"
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

/// The pieces of a `scheme://user@host:port?query#fragment` share link.
///
/// `URLComponents` is not used: a share link's fragment is the node name and is
/// routinely unescaped UTF-8 with emoji and spaces, which makes the whole URL
/// fail to parse rather than just that component.
public struct URIParts {
    public let user: String?
    public let host: String
    public let port: Int
    public let query: [String: String]
    public let name: String

    public init?(_ link: String) {
        guard let schemeEnd = link.range(of: "://") else { return nil }
        var rest = String(link[schemeEnd.upperBound...])

        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = String(rest[..<hash])
        }

        var queryString = ""
        if let mark = rest.firstIndex(of: "?") {
            queryString = String(rest[rest.index(after: mark)...])
            rest = String(rest[..<mark])
        }

        // The userinfo separator is the *last* `@`: a password may contain one.
        var authority = rest
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at]).removingPercentEncoding ?? String(rest[..<at])
            authority = String(rest[rest.index(after: at)...])
        } else {
            user = nil
        }

        // IPv6 literals are bracketed, so the port is after the last colon that
        // follows a `]` — or after the only colon for a hostname.
        let hostPart: String
        let portPart: String?
        if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
            hostPart = String(authority[authority.index(after: authority.startIndex)..<close])
            let after = authority[authority.index(after: close)...]
            portPart = after.hasPrefix(":") ? String(after.dropFirst()) : nil
        } else if let colon = authority.lastIndex(of: ":") {
            hostPart = String(authority[..<colon])
            portPart = String(authority[authority.index(after: colon)...])
        } else {
            hostPart = authority
            portPart = nil
        }

        guard !hostPart.isEmpty, let port = Int(portPart ?? ""), (1...65535).contains(port) else {
            return nil
        }
        host = hostPart
        self.port = port

        var parsed: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let halves = pair.split(separator: "=", maxSplits: 1)
            guard let key = halves.first else { continue }
            let raw = halves.count > 1 ? String(halves[1]) : ""
            parsed[String(key)] = raw.removingPercentEncoding ?? raw
        }
        query = parsed

        let decoded = fragment.removingPercentEncoding ?? fragment
        name = decoded.isEmpty ? "\(hostPart):\(port)" : decoded
    }
}
