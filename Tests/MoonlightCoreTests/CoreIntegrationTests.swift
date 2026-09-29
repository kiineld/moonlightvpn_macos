import Foundation
import MoonlightCore

/// Runs the real mihomo binary.
///
/// The unit tests above check that the generated YAML *says* the right thing;
/// only the core can say whether it will *load* it. Every config shape this app
/// can produce goes through `mihomo -t` here, and one of them is started for
/// real so the RESTful API — which is the app's entire control channel — is
/// exercised rather than assumed.
///
/// Skipped with a clear message when the core is absent, since it is fetched
/// rather than committed (`scripts/fetch-mihomo.sh`).
func coreIntegrationTests() {
    let core = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/mihomo/mihomo")

    guard FileManager.default.isExecutableFile(atPath: core.path) else {
        print("· core integration skipped — run scripts/fetch-mihomo.sh first")
        return
    }

    let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("moonlight-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    let panel = """
    proxies:
      - {name: "🇳🇱 Amsterdam", type: ss, server: 127.0.0.1, port: 18081, cipher: aes-256-gcm, password: pw}
      - {name: "🇫🇮 Helsinki",  type: ss, server: 127.0.0.1, port: 18082, cipher: aes-256-gcm, password: pw}
    proxy-groups:
      - {name: "Панель", type: select, proxies: ["Быстрый", "🇳🇱 Amsterdam", "🇫🇮 Helsinki"]}
      - {name: "Быстрый", type: url-test, proxies: ["🇳🇱 Amsterdam", "🇫🇮 Helsinki"], url: "https://www.gstatic.com/generate_204", interval: 300}
    rules:
      - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
      - MATCH,Панель
    """

    // A port unlikely to collide with a core the developer is actually running.
    let controllerPort = 19_797
    let secret = "test-secret"
    // The app's own layout: the core's home is a folder inside the app's.
    let home = workspace.appendingPathComponent("core", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let process = MihomoProcess(binary: core, dataDirectory: home)

    func overrides(_ mode: TunnelMode, _ rules: [RoutingRule] = []) -> MihomoConfig.Overrides {
        MihomoConfig.Overrides(
            controllerPort: controllerPort, secret: secret, mixedPort: 17_897,
            mode: mode, routingRules: rules, dataDirectory: home.path
        )
    }

    // And every kind of the user's own rules, both ways round, pointed at each
    // kind of target.
    let everyOwnRule = RoutingRule.Kind.allCases.enumerated().map { index, kind in
        RoutingRule(kind: kind, value: kind.placeholder,
                    target: ["DIRECT", "REJECT", "Панель"][index % 3],
                    priority: index.isMultiple(of: 2) ? .override : .extend)
    }

    Check.suite("Core · every generated config loads") {
        // TUN is validated but never started: creating a utun interface needs
        // root, and a test suite must not ask for it.
        let shapes: [(String, MihomoConfig.Overrides)] = [
            ("system proxy", overrides(.systemProxy)),
            ("tun", overrides(.tun)),
            ("own rules", overrides(.systemProxy, everyOwnRule)),
            ("tun + own rules", overrides(.tun, everyOwnRule)),
        ]
        for (name, override) in shapes {
            let path = workspace.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: "-")).yaml")
            do {
                let yaml = try MihomoConfig.build(panelYAML: panel, overrides: override)
                try yaml.write(to: path, atomically: true, encoding: .utf8)
                try process.validate(configPath: path)
                Check.isTrue(true, "\(name) config loads")
            } catch {
                Check.isTrue(false, "\(name) config loads — \(error)")
            }
        }
    }

    Check.suite("Core · RESTful API") {
        let path = process.configURL
        do {
            let yaml = try MihomoConfig.build(panelYAML: panel, overrides: overrides(.systemProxy))
            try yaml.write(to: path, atomically: true, encoding: .utf8)
            try process.start(configPath: path)
        } catch {
            Check.isTrue(false, "core starts — \(error)")
            return
        }
        defer { process.stop() }

        let api = MihomoAPI(port: controllerPort, secret: secret)
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            defer { semaphore.signal() }

            guard await api.waitUntilReady(timeout: 40) else {
                Check.isTrue(false, "core answers its API — log:\n\(process.recentLog)")
                return
            }
            Check.isTrue(true, "core answers its API")

            do {
                let groups = try await api.groups()
                let selector = groups.first { $0.name == "Панель" }
                Check.notNil(selector, "the panel's own selector is visible over the API")
                // The selector's list is offered verbatim, groups included: a
                // panel puts its balancers and auto-picker there deliberately,
                // and filtering them out leaves the user picking raw nodes the
                // operator never meant to offer directly.
                let nodes = try await api.nodes(in: "Панель")
                Check.equal(nodes.count, 3, "everything the selector offers is listed")
                Check.equal(nodes.first?.name, "Быстрый", "in the order the selector lists them")
                Check.isTrue(nodes.first?.isGroup == true, "a url-test group is marked as a group")
                Check.equal(nodes.filter { !$0.isGroup }.map(\.name),
                            ["🇳🇱 Amsterdam", "🇫🇮 Helsinki"],
                            "plain nodes keep their names, emoji and all")

                // Selecting is the whole of "pick a server", and the name has to
                // survive being put in a URL path.
                try await api.select(node: "🇫🇮 Helsinki", in: "Панель")
                let after = try await api.groups().first { $0.name == "Панель" }
                Check.equal(after?.now, "🇫🇮 Helsinki", "selection round-trips through the API")

                // Every subscription refresh reloads the running core from the
                // file the app just wrote. mihomo refuses a path outside its
                // home directory, so a config kept anywhere else starts fine and
                // then fails each refresh.
                try await api.reload(path: path.path)
                Check.isTrue(true, "the core reloads the config the app writes")

                let traffic = try await api.totals()
                Check.isTrue(traffic.up >= 0 && traffic.down >= 0, "traffic counters read")

                // An unreachable node reports nil rather than throwing: a
                // timeout is the expected answer for a node that is down.
                let delay = await api.delay(node: "🇳🇱 Amsterdam", timeout: 1500)
                Check.isNil(delay, "an unreachable node measures as unknown, not as an error")
            } catch {
                Check.isTrue(false, "API calls succeed — \(error)")
            }
        }

        _ = semaphore.wait(timeout: .now() + 90)
        Check.isTrue(process.isRunning, "the core stayed up through the whole exchange")
    }
}
