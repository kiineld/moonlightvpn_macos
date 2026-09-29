import Foundation

/// A rule from the apps screen of versions before 1.9 — an app switch, or a
/// rule written beside them — kept only so it can be read once and moved into
/// the user's own rules.
///
/// The apps screen routed with split modes: every connection through the
/// tunnel, only the selected apps, or all but them. The rules page does that
/// job and more — a process rule can go anywhere, not only around the tunnel or
/// through it — so the screen and its modes are gone, and what a user set there
/// is carried over (see ``RoutingRule/carriedOver(from:mode:group:)``).
public struct LegacySplitRule: Codable, Hashable, Sendable {
    /// mihomo's name for the kind, e.g. `PROCESS-NAME`.
    public var kind: String
    public var value: String
    public var enabled: Bool
    /// Set for the rules the app switches generated.
    public var appExecutable: String?

    public init(kind: String, value: String, enabled: Bool = true, appExecutable: String? = nil) {
        self.kind = kind
        self.value = value
        self.enabled = enabled
        self.appExecutable = appExecutable
    }
}

extension RoutingRule {
    /// The apps screen's rules as rules of the user's own, doing what they did.
    ///
    /// - `except` sent what they matched around the tunnel: rules to `DIRECT`.
    /// - `only` sent what they matched through it: rules to `group`, the group
    ///   the subscription routes through. The rest of the traffic now follows
    ///   the subscription's rules rather than going direct — the one thing a
    ///   rule cannot say.
    /// - `all` ignored them, so they arrive switched off, to read and reuse.
    public static func carriedOver(from rules: [LegacySplitRule], mode: String, group: String) -> [RoutingRule] {
        rules.compactMap { rule in
            guard let kind = Kind(rawValue: rule.kind),
                  !rule.value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return RoutingRule(
                kind: kind,
                value: rule.value,
                target: mode == "only" ? group : direct,
                priority: .override,
                enabled: rule.enabled && (mode == "only" || mode == "except")
            )
        }
    }
}
