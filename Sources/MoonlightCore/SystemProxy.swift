import Foundation

/// Points macOS's own proxy settings at the running core, and puts them back.
///
/// This is the default way traffic reaches the tunnel, because it needs no
/// privileges: `networksetup` writes the same preferences the Network pane does.
/// What it buys is also what it costs — only applications that honour the system
/// proxy are captured. A game with its own socket stack, or anything using
/// QUIC, goes straight out the physical interface. That is the reason TUN mode
/// exists, and the reason the split-tunnel screen is inert here: without an
/// interface to route, there is nothing to route per-process.
public enum SystemProxy {

    /// The services whose settings were changed, and what they were.
    ///
    /// Recorded rather than assumed: a machine with Wi-Fi and a Thunderbolt
    /// dock has several active services, and one of them may already have had a
    /// proxy the user set by hand. Restoring "off" everywhere would silently
    /// delete that.
    public struct Snapshot: Codable, Sendable {
        public struct ServiceState: Codable, Sendable {
            var service: String
            var webEnabled: Bool
            var webServer: String
            var webPort: String
            var secureEnabled: Bool
            var secureServer: String
            var securePort: String
            var socksEnabled: Bool
            var socksServer: String
            var socksPort: String
        }
        public var services: [ServiceState]
    }

    private static let networksetup = "/usr/sbin/networksetup"

    /// Network services that are on and could carry traffic.
    ///
    /// A disabled service is prefixed with `*` in this listing, and setting a
    /// proxy on one is both pointless and slow.
    public static func activeServices() -> [String] {
        let output = run([networksetup, "-listallnetworkservices"])
        return output
            .split(whereSeparator: \.isNewline)
            .dropFirst()                       // "An asterisk (*) denotes…"
            .map(String.init)
            .filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    public static func snapshot() -> Snapshot {
        Snapshot(services: activeServices().map { service in
            let web = readProxy("-getwebproxy", service)
            let secure = readProxy("-getsecurewebproxy", service)
            let socks = readProxy("-getsocksfirewallproxy", service)
            return Snapshot.ServiceState(
                service: service,
                webEnabled: web.enabled, webServer: web.server, webPort: web.port,
                secureEnabled: secure.enabled, secureServer: secure.server, securePort: secure.port,
                socksEnabled: socks.enabled, socksServer: socks.server, socksPort: socks.port
            )
        })
    }

    /// Sets HTTP, HTTPS and SOCKS to the core's mixed port on every active
    /// service. mihomo's mixed listener speaks all three on the one port.
    public static func enable(port: Int, services: [String]? = nil) {
        for service in services ?? activeServices() {
            _ = run([networksetup, "-setwebproxy", service, "127.0.0.1", String(port)])
            _ = run([networksetup, "-setsecurewebproxy", service, "127.0.0.1", String(port)])
            _ = run([networksetup, "-setsocksfirewallproxy", service, "127.0.0.1", String(port)])
            // Loopback and local hostnames must not go through the proxy, or the
            // app's own calls to the core would loop back through the tunnel.
            _ = run([networksetup, "-setproxybypassdomains", service,
                     "127.0.0.1", "localhost", "*.local", "169.254/16"])
        }
    }

    /// Restores what `snapshot()` recorded. Falls back to switching everything
    /// off when there is no snapshot — better a machine with no proxy than one
    /// pointing at a core that is gone.
    public static func restore(_ snapshot: Snapshot?) {
        guard let snapshot else {
            disableAll()
            return
        }
        for state in snapshot.services {
            apply("-setwebproxy", "-setwebproxystate", state.service,
                  state.webEnabled, state.webServer, state.webPort)
            apply("-setsecurewebproxy", "-setsecurewebproxystate", state.service,
                  state.secureEnabled, state.secureServer, state.securePort)
            apply("-setsocksfirewallproxy", "-setsocksfirewallproxystate", state.service,
                  state.socksEnabled, state.socksServer, state.socksPort)
        }
    }

    public static func disableAll() {
        for service in activeServices() {
            _ = run([networksetup, "-setwebproxystate", service, "off"])
            _ = run([networksetup, "-setsecurewebproxystate", service, "off"])
            _ = run([networksetup, "-setsocksfirewallproxystate", service, "off"])
        }
    }

    /// Whether the machine's proxy currently points at this port — used at
    /// launch to notice settings a previous run left behind after a crash.
    public static func isEnabled(port: Int) -> Bool {
        activeServices().contains { service in
            let web = readProxy("-getwebproxy", service)
            return web.enabled && web.server == "127.0.0.1" && web.port == String(port)
        }
    }

    // MARK: -

    private static func apply(
        _ setKey: String, _ stateKey: String, _ service: String,
        _ enabled: Bool, _ server: String, _ port: String
    ) {
        if enabled, !server.isEmpty, !port.isEmpty, port != "0" {
            _ = run([networksetup, setKey, service, server, port])
        } else {
            _ = run([networksetup, stateKey, service, "off"])
        }
    }

    private static func readProxy(_ key: String, _ service: String) -> (enabled: Bool, server: String, port: String) {
        var enabled = false, server = "", port = ""
        for line in run([networksetup, key, service]).split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch parts[0].trimmingCharacters(in: .whitespaces) {
            case "Enabled": enabled = value.lowercased() == "yes"
            case "Server": server = value
            case "Port": port = value
            default: break
            }
        }
        return (enabled, server, port)
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
