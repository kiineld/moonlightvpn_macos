import Foundation
import MoonlightCore

private func rule(_ kind: SplitRule.Kind, _ value: String, app: String? = nil) -> SplitRule {
    SplitRule(kind: kind, value: value, appExecutable: app)
}

/// The three split modes are deliberately *not* symmetric, because preserving
/// the panel's own routing means something different in each. These pin that,
/// and the rule grammar each kind produces.
func splitTunnelTests() {
    let panelRules = ["GEOSITE,category-ru,DIRECT", "MATCH,Панель"]

    Check.suite("Split · all") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .all,
            splitRules: [rule(.processName, "Telegram")],
            selector: "Панель", root: &root
        )
        Check.equal(rules, panelRules, "the panel's rules are untouched")
        Check.isNil(root["sub-rules"], "no sub-rules are introduced")
    }

    Check.suite("Split · except") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .except,
            splitRules: [rule(.processName, "Telegram"), rule(.domainSuffix, "bank.ru")],
            selector: "Панель", root: &root
        )
        // Prepending composes cleanly: what these match never reaches the
        // panel's rules, and everything else sees them exactly as written.
        Check.equal(rules.first, "PROCESS-NAME,Telegram,DIRECT", "process rule goes direct first")
        Check.equal(rules[1], "DOMAIN-SUFFIX,bank.ru,DIRECT", "domain rules sit alongside process ones")
        Check.equal(Array(rules.suffix(2)), panelRules, "the panel's rules follow intact")
    }

    Check.suite("Split · only") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .only,
            splitRules: [rule(.processName, "Telegram")],
            selector: "Панель", root: &root
        )
        // Delegating through a SUB-RULE keeps the panel's own direct rules
        // working for the app. Pointing it straight at the selector would force
        // all of its traffic through the node.
        Check.equal(rules.first, "SUB-RULE,(PROCESS-NAME,Telegram),moonlight-panel",
                    "the match is delegated to the panel's rule set")
        Check.equal(rules.last, "MATCH,DIRECT", "everything else goes direct")
        Check.equal((root["sub-rules"] as? [String: Any])?["moonlight-panel"] as? [String],
                    panelRules, "the panel's rules move into the sub-rule verbatim")
    }

    Check.suite("Split · empty and disabled") {
        var root: [String: Any] = [:]
        // An empty allow-list routes nothing at all, which reads as a broken VPN
        // rather than as a configuration choice.
        Check.equal(
            MihomoConfig.applySplit(rules: panelRules, mode: .only, splitRules: [],
                                    selector: "П", root: &root),
            panelRules, "an empty 'only' falls back to tunnelling everything")

        var disabled = rule(.processName, "Telegram")
        disabled.enabled = false
        Check.equal(
            MihomoConfig.applySplit(rules: panelRules, mode: .except, splitRules: [disabled],
                                    selector: "П", root: &root),
            panelRules, "a disabled rule contributes nothing")

        Check.equal(
            MihomoConfig.applySplit(rules: panelRules, mode: .except,
                                    splitRules: [rule(.domain, "   ")],
                                    selector: "П", root: &root),
            panelRules, "a blank value contributes nothing")
    }

    Check.suite("Split · rule grammar") {
        // Address rules carry no-resolve, or every connection would trigger a
        // DNS lookup just to test it against a CIDR.
        Check.equal(rule(.ipCIDR, "192.168.1.0/24").line(target: "DIRECT"),
                    "IP-CIDR,192.168.1.0/24,DIRECT,no-resolve", "IP-CIDR carries no-resolve")
        Check.equal(rule(.geoip, "ru").line(target: "DIRECT"),
                    "GEOIP,ru,DIRECT,no-resolve", "GEOIP carries no-resolve")
        Check.equal(rule(.domain, "example.com").line(target: "G"),
                    "DOMAIN,example.com,G", "domain rules carry no parameter")
        // no-resolve is a rule parameter; the matcher position does not take one.
        Check.equal(rule(.ipCIDR, "192.168.1.0/24").matcher(),
                    "(IP-CIDR,192.168.1.0/24)", "the matcher form drops no-resolve")

        Check.isTrue(SplitRule.Kind.processName.needsProcessMatching, "process rules need TUN")
        Check.isTrue(SplitRule.Kind.processPathRegex.needsProcessMatching, "path regex needs TUN")
        Check.isTrue(!SplitRule.Kind.domainSuffix.needsProcessMatching,
                     "domain rules work under a system proxy too")
        Check.isTrue(!SplitRule.Kind.ipCIDR.needsProcessMatching, "address rules work in both modes")
    }

    Check.suite("Split · validation") {
        // A bad rule does not fail alone: mihomo refuses the whole config, so
        // the tunnel stops rather than the rule being skipped.
        Check.equal(SplitRule.validate(kind: .domain, value: "  "), .empty, "blank is rejected")
        Check.equal(SplitRule.validate(kind: .domain, value: "a,b"), .containsComma,
                    "a comma would silently become a different rule")
        Check.equal(SplitRule.validate(kind: .dstPort, value: "70000"), .badPort, "port range")
        Check.equal(SplitRule.validate(kind: .dstPort, value: "https"), .badPort, "port must be numeric")
        Check.equal(SplitRule.validate(kind: .ipCIDR, value: "192.168.1.0"), .badCIDR,
                    "a CIDR needs a prefix length")
        Check.isNil(SplitRule.validate(kind: .ipCIDR, value: "192.168.1.0/24"), "a valid CIDR passes")
        Check.isNil(SplitRule.validate(kind: .domainRegex, value: #"^.*\.discord\.(com|gg)$"#),
                    "a valid regex passes")
        Check.notNil(SplitRule.validate(kind: .domainRegex, value: "(unclosed"), "a bad regex is caught")
        Check.isNil(SplitRule.validate(kind: .processName, value: "Google Chrome"),
                    "spaces in a process name are fine")
    }
}
