import Foundation
import MoonlightCore

/// The user's own rules: what each kind accepts, the line it writes, and where
/// it lands among the subscription's rules.
func routingRuleTests() {
    let panelRules = ["GEOSITE,category-ru,DIRECT", "MATCH,Панель"]
    let targets: Set<String> = ["DIRECT", "REJECT", "Панель"]

    func rule(_ kind: RoutingRule.Kind, _ value: String, _ target: String = "DIRECT",
              _ priority: RoutingRule.Priority = .override) -> RoutingRule {
        RoutingRule(kind: kind, value: value, target: target, priority: priority)
    }

    Check.suite("Own rules · validation") {
        for kind in RoutingRule.Kind.allCases {
            Check.isNil(RoutingRule.validate(kind: kind, value: kind.placeholder),
                        "\(kind.rawValue)'s own placeholder is valid")
        }
        Check.equal(RoutingRule.validate(kind: .domain, value: "  "), .empty, "a blank value is refused")
        Check.equal(RoutingRule.validate(kind: .domain, value: "a.com,b.com"), .containsComma,
                    "a comma would turn it into a different rule")
        Check.equal(RoutingRule.validate(kind: .domainRegex, value: "(unclosed"), .badRegex,
                    "a regex that does not compile is refused")
        Check.isNil(RoutingRule.validate(kind: .dstPort, value: "80/443/1000-2000"),
                    "ports, ranges and lists of them")
        Check.equal(RoutingRule.validate(kind: .dstPort, value: "70000"), .badPort, "past 65535")
        Check.equal(RoutingRule.validate(kind: .srcPort, value: "2000-1000"), .badPort,
                    "a range that runs backwards")
        Check.equal(RoutingRule.validate(kind: .ipCIDR, value: "10.0.0.0"), .badCIDR,
                    "an address with no prefix length")
        Check.equal(RoutingRule.validate(kind: .ipCIDR, value: "300.0.0.0/8"), .badCIDR,
                    "an octet past 255")
        Check.equal(RoutingRule.validate(kind: .ipCIDR6, value: "10.0.0.0/8"), .badCIDR,
                    "IP-CIDR6 takes IPv6 only")
        Check.equal(RoutingRule.validate(kind: .ipASN, value: "AS13335"), .badASN, "the number alone")
        Check.equal(RoutingRule.validate(kind: .network, value: "icmp"), .badNetwork, "tcp or udp")
    }

    Check.suite("Own rules · grammar") {
        Check.equal(rule(.domainSuffix, "kinokino.vip").line, "DOMAIN-SUFFIX,kinokino.vip,DIRECT",
                    "a domain rule as mihomo writes it")
        Check.equal(rule(.ipCIDR, "10.0.0.0/8", "REJECT").line, "IP-CIDR,10.0.0.0/8,REJECT,no-resolve",
                    "address rules do not resolve the domain to test it")
        Check.equal(rule(.processName, "Telegram", "Панель").line, "PROCESS-NAME,Telegram,Панель",
                    "a group is a target like any other")
    }

    Check.suite("Own rules · placement") {
        let placed = MihomoConfig.placeOwnRules(
            [rule(.domainSuffix, "a.com"), rule(.domainSuffix, "b.com", "Панель", .extend)],
            around: panelRules, targets: targets
        )
        Check.equal(placed.before, ["DOMAIN-SUFFIX,a.com,DIRECT"], "override goes before")
        Check.equal(placed.rules, ["GEOSITE,category-ru,DIRECT", "DOMAIN-SUFFIX,b.com,Панель", "MATCH,Панель"],
                    "extend goes after the subscription's rules but before its catch-all")

        let noCatchAll = MihomoConfig.placeOwnRules(
            [rule(.domain, "c.com", "DIRECT", .extend)], around: ["DOMAIN,x.com,DIRECT"], targets: targets)
        Check.equal(noCatchAll.rules.last, "DOMAIN,c.com,DIRECT", "with no MATCH, extend is appended")

        var off = rule(.domain, "off.com")
        off.enabled = false
        let skipped = MihomoConfig.placeOwnRules(
            [off, rule(.domain, "gone.com", "Removed group"), rule(.domain, "bad,value")],
            around: panelRules, targets: targets)
        Check.isTrue(skipped.before.isEmpty,
                     "switched off, pointing at a missing group, or invalid: none is written")
        Check.equal(skipped.rules, panelRules, "and the subscription's rules are untouched")
    }

    Check.suite("Own rules · in the config") {
        let panel = """
        proxies:
          - {name: "A", type: ss, server: 127.0.0.1, port: 1, cipher: aes-256-gcm, password: pw}
        proxy-groups:
          - {name: "Панель", type: select, proxies: ["A"]}
        rules:
          - GEOSITE,category-ru,DIRECT
          - MATCH,Панель
        """
        func built(_ split: SplitMode, _ splitRules: [SplitRule]) -> [String] {
            let yaml = (try? MihomoConfig.build(panelYAML: panel, overrides: MihomoConfig.Overrides(
                secret: "s", splitMode: split, splitRules: splitRules,
                routingRules: [rule(.domainSuffix, "own.com", "REJECT"),
                               rule(.domainSuffix, "late.com", "Панель", .extend)],
                dataDirectory: "/tmp"))) ?? ""
            return MihomoConfig.routingInputs(panelYAML: yaml).rules
        }
        let all = built(.all, [])
        Check.equal(all.first, "DOMAIN-SUFFIX,own.com,REJECT", "override comes first")
        Check.equal(all.suffix(2).first, "DOMAIN-SUFFIX,late.com,Панель", "extend sits before MATCH")

        let except = built(.except, [SplitRule(kind: .processName, value: "Telegram")])
        Check.equal(Array(except.prefix(2)), ["DOMAIN-SUFFIX,own.com,REJECT", "PROCESS-NAME,Telegram,DIRECT"],
                    "overrides come before the split rules too")

        let only = built(.only, [SplitRule(kind: .processName, value: "Telegram")])
        Check.equal(only.first, "DOMAIN-SUFFIX,own.com,REJECT", "in 'only' mode too")
        Check.equal(only.last, "MATCH,DIRECT", "the split's catch-all still ends the list")
    }

    Check.suite("Own rules · the subscription's rules, read") {
        let plain = ProfileRule(line: "DOMAIN-SUFFIX,google.com,Панель")
        Check.equal([plain.kind, plain.value, plain.target], ["DOMAIN-SUFFIX", "google.com", "Панель"],
                    "type, value, target")
        let noResolve = ProfileRule(line: "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve")
        Check.equal(noResolve.target, "DIRECT", "no-resolve is a parameter, not the target")
        let logical = ProfileRule(line: "AND,((DOMAIN,x.com),(NETWORK,udp)),REJECT")
        Check.equal([logical.kind, logical.value, logical.target],
                    ["AND", "((DOMAIN,x.com),(NETWORK,udp))", "REJECT"],
                    "commas inside a logical rule stay in its value")
        let match = ProfileRule(line: "MATCH,Панель")
        Check.equal([match.kind, match.value, match.target], ["MATCH", "", "Панель"],
                    "the catch-all has nothing to match on")
    }

    Check.suite("Own rules · stored") {
        let original = [rule(.geoip, "ru", "DIRECT", .extend)]
        let data = try? JSONEncoder().encode(original)
        let decoded = data.flatMap { try? JSONDecoder().decode([RoutingRule].self, from: $0) }
        Check.equal(decoded, original, "round-trips through the preferences' JSON")
    }
}
