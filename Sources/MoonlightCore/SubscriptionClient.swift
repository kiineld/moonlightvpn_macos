import Foundation

/// Fetches a Remnawave subscription and returns a mihomo config plus whatever
/// the panel reports about the plan.
///
/// ## Why the mihomo endpoint is tried first
///
/// Remnawave serves a subscription in six shapes, selected by a path suffix:
/// `mihomo`, `clash`, `singbox`, `stash`, `json` (xray) and `v2ray-json`. The
/// order here is not a preference:
///
/// 1. **`/mihomo`** — a Clash.Meta YAML written by the panel operator. It can
///    carry proxy groups, a `url-test` balancer across a dozen nodes, its own
///    DNS and routing rules. This client keeps that config *verbatim* and
///    overrides only the parts it must own (controller, ports, TUN, split
///    rules), because the panel's tuning is usually better than anything
///    generated here.
/// 2. **`/clash`** — the same idea for stock Clash. Slightly fewer features,
///    still a real config with groups intact.
/// 3. **The bare URL** — base64 or plain share links, one URI per node. Every
///    group, balancer and routing rule is flattened away by that format, so a
///    node whose panel entry was a balancer arrives as a single unusable
///    placeholder. This is the last resort, not a peer of the other two.
///
/// A panel with no MIHOMO template configured 404s the first two, which is
/// exactly when the third earns its place.
public struct SubscriptionClient: Sendable {

    public enum Failure: LocalizedError, Equatable {
        case badURL
        case http(Int)
        case empty
        case unusable(String)

        public var errorDescription: String? {
            switch self {
            case .badURL: return "Subscription link is not a valid http(s) URL"
            case .http(let code): return "Panel returned HTTP \(code)"
            case .empty: return "Panel returned an empty subscription"
            case .unusable(let why): return why
            }
        }
    }

    public struct Result: Sendable {
        /// Raw mihomo/Clash YAML, ready for `MihomoConfig` to graft onto.
        public var yaml: String
        public var info: SubscriptionInfo
        /// Which endpoint answered — surfaced in the UI so a base64 fallback
        /// (with its lost groups) is visible rather than silent.
        public var source: Source
    }

    public enum Source: String, Sendable {
        case mihomo
        case clash
        case shareLinks
    }

    private let session: URLSession
    private let device: DeviceIdentity

    public init(session: URLSession? = nil, device: DeviceIdentity) {
        self.session = session ?? Self.makeSession()
        self.device = device
    }

    /// A session that **ignores the machine's proxy settings**.
    ///
    /// This is the macOS counterpart of the Android client excluding itself from
    /// its own tunnel, and it matters for two reasons. While connected in
    /// system-proxy mode the app has pointed the whole machine at its own core,
    /// so a shared session would send the panel request back through the tunnel
    /// it is trying to manage — and a refresh during a half-open tunnel then
    /// hangs instead of failing. It also means a *stale* proxy left by any other
    /// client on the machine cannot swallow this app's requests, which is a
    /// silent hang with no timeout, because the connection is established and
    /// simply never answered.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    public func fetch(_ subscriptionURL: String) async throws -> Result {
        guard let base = Self.normalize(subscriptionURL) else { throw Failure.badURL }

        var lastError: Error = Failure.empty

        for suffix in ["mihomo", "clash"] {
            do {
                let (body, info) = try await get(base.appendingPathComponent(suffix))
                guard Self.looksLikeClashConfig(body) else {
                    throw Failure.unusable("\(suffix) endpoint did not return a Clash config")
                }
                return Result(yaml: body, info: info,
                              source: suffix == "mihomo" ? .mihomo : .clash)
            } catch {
                lastError = error
            }
        }

        // Last resort: share links, with every group and routing rule already
        // flattened out of them by the format itself.
        do {
            let (body, info) = try await get(base)
            if Self.looksLikeClashConfig(body) {
                return Result(yaml: body, info: info, source: .clash)
            }
            let links = ShareLink.decodeList(body)
            guard !links.isEmpty else { throw Failure.unusable("No nodes found in subscription") }
            let proxies = links.compactMap(ShareLink.mihomoProxy)
            guard !proxies.isEmpty else {
                throw Failure.unusable("Subscription has \(links.count) nodes, none of a type mihomo supports")
            }
            return Result(yaml: MihomoConfig.yamlFromProxies(proxies),
                          info: info, source: .shareLinks)
        } catch {
            lastError = error
        }

        throw lastError
    }

    /// `GET <sub>/info` — Remnawave's own JSON, which carries the device count
    /// the response headers do not.
    public func fetchInfo(_ subscriptionURL: String) async -> SubscriptionInfo? {
        guard let base = Self.normalize(subscriptionURL) else { return nil }
        guard let (data, response) = try? await send(base.appendingPathComponent("info")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? SubscriptionInfo.fromRemnawaveInfo(data)
    }

    // MARK: -

    private func get(_ url: URL) async throws -> (String, SubscriptionInfo) {
        let (data, response) = try await send(url)
        guard let http = response as? HTTPURLResponse else { throw Failure.empty }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        guard let body = String(data: data, encoding: .utf8), !body.isEmpty else {
            throw Failure.empty
        }
        return (body, SubscriptionInfo.fromHeaders(http))
    }

    private func send(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Remnawave's device headers. The panel uses these for its device limit
        // and for picking a template when no suffix is given.
        request.setValue(device.hwid, forHTTPHeaderField: "x-hwid")
        request.setValue("macOS", forHTTPHeaderField: "x-device-os")
        request.setValue(device.osVersion, forHTTPHeaderField: "x-ver-os")
        request.setValue(device.model, forHTTPHeaderField: "x-device-model")
        // Panels that route on User-Agent rather than on the suffix still need
        // to see a mihomo client here.
        request.setValue("mihomo/1.19 moonlight/\(device.appVersion)",
                         forHTTPHeaderField: "User-Agent")
        return try await session.data(for: request)
    }

    public static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // A scheme that is already present must be http(s) — prepending
        // `https://` to `file:///etc/passwd` or to a `vless://` node link would
        // turn a rejection into a plausible-looking URL, and a deep link must
        // not be able to point the import flow at either.
        let scheme = text.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression)
        if let scheme {
            let name = text[..<scheme.upperBound].lowercased()
            guard name == "http://" || name == "https://" else { return nil }
        } else {
            text = "https://" + text
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        // A trailing slash would make appendingPathComponent produce `//mihomo`.
        let trimmed = url.absoluteString.hasSuffix("/")
            ? String(url.absoluteString.dropLast())
            : url.absoluteString
        return URL(string: trimmed)
    }

    /// Detected by content, not by `Content-Type` — panels mislabel it, and a
    /// base64 body served as `text/yaml` would otherwise be fed to the parser.
    public static func looksLikeClashConfig(_ body: String) -> Bool {
        body.range(of: #"(?m)^\s*proxies\s*:"#, options: .regularExpression) != nil
    }
}

/// The identity this install presents to the panel.
public struct DeviceIdentity: Sendable {
    /// A random UUID minted once and stored, **not** a hardware identifier. It
    /// gives the panel a stable per-install handle for its device limit while
    /// carrying no hardware identity off the machine. Resetting the app mints a
    /// new one, which is the right trade.
    public var hwid: String
    public var osVersion: String
    public var model: String
    public var appVersion: String

    public init(hwid: String, osVersion: String, model: String, appVersion: String) {
        self.hwid = hwid
        self.osVersion = osVersion
        self.model = model
        self.appVersion = appVersion
    }
}

public extension SubscriptionInfo {

    /// Parses the two headers every panel implements consistently.
    ///
    /// `subscription-userinfo: upload=0; download=0; total=0; expire=0`
    /// `profile-title: <utf8 or base64:…>`
    ///
    /// A zero `total` or `expire` means *unlimited* in this format, not zero, so
    /// both map to nil rather than to 0.
    static func fromHeaders(_ response: HTTPURLResponse) -> SubscriptionInfo {
        var info = SubscriptionInfo()

        if let raw = response.value(forHTTPHeaderField: "subscription-userinfo") {
            for field in raw.split(separator: ";") {
                let parts = field.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = Int64(parts[1].trimmingCharacters(in: .whitespaces))
                switch key {
                case "upload": info.upload = value
                case "download": info.download = value
                case "total": info.total = (value ?? 0) > 0 ? value : nil
                case "expire":
                    if let value, value > 0 {
                        info.expire = Date(timeIntervalSince1970: TimeInterval(value))
                    }
                default: break
                }
            }
        }

        if let title = response.value(forHTTPHeaderField: "profile-title") {
            info.title = Self.decodeTitle(title)
        }
        return info
    }

    /// Remnawave's `/info` JSON. Only the fields the design shows are read; the
    /// rest of the document is left alone so a schema addition cannot break it.
    static func fromRemnawaveInfo(_ data: Data) throws -> SubscriptionInfo {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let response = (root?["response"] as? [String: Any]) ?? root ?? [:]
        let user = (response["user"] as? [String: Any]) ?? response

        var info = SubscriptionInfo()
        info.title = user["username"] as? String
        info.download = (user["trafficUsed"] as? NSNumber)?.int64Value
            ?? (user["usedTrafficBytes"] as? NSNumber)?.int64Value
        if let limit = (user["trafficLimit"] as? NSNumber)?.int64Value
            ?? (user["trafficLimitBytes"] as? NSNumber)?.int64Value, limit > 0 {
            info.total = limit
        }
        if let expire = user["expiresAt"] as? String {
            info.expire = ISO8601DateFormatter.remnawave.date(from: expire)
        }
        if let limit = (user["hwidDeviceLimit"] as? NSNumber)?.intValue, limit > 0 {
            info.deviceLimit = limit
        }
        if let used = (response["devicesUsed"] as? NSNumber)?.intValue
            ?? (user["devicesUsed"] as? NSNumber)?.intValue {
            info.devicesUsed = used
        }
        return info
    }

    /// Fields present in `other` win, field by field — the header values are the
    /// authoritative ones, and a nil there must not erase a good value.
    func merging(_ other: SubscriptionInfo) -> SubscriptionInfo {
        SubscriptionInfo(
            title: other.title ?? title,
            upload: other.upload ?? upload,
            download: other.download ?? download,
            total: other.total ?? total,
            expire: other.expire ?? expire,
            deviceLimit: other.deviceLimit ?? deviceLimit,
            devicesUsed: other.devicesUsed ?? devicesUsed
        )
    }

    private static func decodeTitle(_ raw: String) -> String {
        // Panels send this either plain or as `base64:<payload>`, and some send
        // bare base64 with no prefix.
        if raw.lowercased().hasPrefix("base64:") {
            let payload = String(raw.dropFirst("base64:".count))
            if let data = Data(base64Encoded: payload),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        return raw
    }
}

extension ISO8601DateFormatter {
    static let remnawave: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
