import Foundation
import MoonlightCore

/// The three split modes are deliberately *not* symmetric, because preserving
/// the panel's own routing means something different in each. These pin that.
func splitTunnelTests() {
    let panelRules = ["GEOSITE,category-ru,DIRECT", "MATCH,Панель"]

    Check.suite("Split · all") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .all, processes: ["Telegram"],
            selector: "Панель", root: &root
        )
        Check.equal(rules, panelRules, "the panel's rules are untouched")
        Check.isNil(root["sub-rules"], "no sub-rules are introduced")
    }

    Check.suite("Split · except") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .except, processes: ["Telegram", "Bank"],
            selector: "Панель", root: &root
        )
        // Prepending composes cleanly: the named apps never reach the panel's
        // rules, and everything else sees them exactly as written.
        Check.equal(rules.first, "PROCESS-NAME,Telegram,DIRECT", "named apps go direct first")
        Check.equal(rules[1], "PROCESS-NAME,Bank,DIRECT", "each named app gets a rule")
        Check.equal(Array(rules.suffix(2)), panelRules, "the panel's rules follow intact")
    }

    Check.suite("Split · only") {
        var root: [String: Any] = [:]
        let rules = MihomoConfig.applySplit(
            rules: panelRules, mode: .only, processes: ["Telegram"],
            selector: "Панель", root: &root
        )
        // Handing the app to the panel's rules through a SUB-RULE keeps the
        // panel's own direct rules working for it. Pointing the process straight
        // at the selector would force *all* of its traffic through the node,
        // including hosts the panel deliberately routes direct.
        Check.equal(rules.first, "SUB-RULE,(PROCESS-NAME,Telegram),moonlight-panel",
                    "the app is delegated to the panel's rule set")
        Check.equal(rules.last, "MATCH,DIRECT", "everything else goes direct")
        let subRules = root["sub-rules"] as? [String: Any]
        Check.equal((subRules?["moonlight-panel"] as? [String])?.count, 2,
                    "the panel's rules move into the sub-rule verbatim")
    }

    Check.suite("Split · empty selection") {
        var root: [String: Any] = [:]
        // An empty allow-list routes nothing at all, which reads as a broken VPN
        // rather than as a configuration choice.
        let only = MihomoConfig.applySplit(
            rules: panelRules, mode: .only, processes: [], selector: "П", root: &root
        )
        Check.equal(only, panelRules, "an empty 'only' falls back to tunnelling everything")

        let except = MihomoConfig.applySplit(
            rules: panelRules, mode: .except, processes: [], selector: "П", root: &root
        )
        Check.equal(except, panelRules, "an empty 'except' changes nothing")
    }
}
