import Foundation

/// Links that open the app from a website or a chat.
///
/// `moonlight://install-config?url=<subscription link>` adds a subscription —
/// the form Clash clients use, so a service's "add to app" button needs no
/// Moonlight-specific code. `moonlight://import?url=…` and `moonlight:///import`
/// mean the same, as they do in Flowvy. The nested link should be
/// percent-encoded whole; one that was not, with `&` in it, is still read to
/// the end rather than cut at the first `&`.
///
/// A link never adds anything by itself: any page can open one, and a
/// subscription added unseen would route the machine through whoever wrote
/// the page. The app asks first.
public enum DeepLink: Equatable, Sendable {
    /// Add the subscription at this link.
    case addSubscription(String)

    public static let scheme = "moonlight"
    private static let actions = ["install-config", "import", "add"]

    /// What `url` asks for, or nil when it asks for nothing this app does.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // `moonlight://import?…` has the action as its host; `moonlight:///import?…`
        // as its path.
        let host = components.host?.lowercased() ?? ""
        let action = host.isEmpty
            ? components.path.split(separator: "/").first.map { $0.lowercased() } ?? ""
            : host
        guard Self.actions.contains(action) else { return nil }

        guard let link = Self.nestedLink(components), Self.isSubscriptionLink(link) else { return nil }
        self = .addSubscription(link)
    }

    /// The `url` parameter, decoded. Read from the raw query when it is the
    /// only parameter, so an unencoded link keeps its own `&` and `#` parts.
    private static func nestedLink(_ components: URLComponents) -> String? {
        if let raw = components.percentEncodedQuery, raw.hasPrefix("url=") {
            let value = String(raw.dropFirst("url=".count))
            let decoded = (value.removingPercentEncoding ?? value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty { return decoded }
        }
        let values = (components.queryItems ?? []).filter { $0.name == "url" }.compactMap(\.value)
        guard values.count == 1 else { return nil }
        let value = values[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Only a web address: a link from outside is not trusted with a file
    /// path, or with any other scheme a subscription client might accept.
    private static func isSubscriptionLink(_ link: String) -> Bool {
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
