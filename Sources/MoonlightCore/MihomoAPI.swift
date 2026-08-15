import Foundation

/// Client for mihomo's RESTful API — the only channel the app uses to observe
/// or steer a running core.
///
/// The core is never reconfigured by restarting it: switching a node, changing
/// mode, or reloading a new subscription all go through here, so the tunnel
/// stays up across every one of them.
public actor MihomoAPI {

    public struct Traffic: Equatable, Sendable {
        public var up: Int64
        public var down: Int64
    }

    public struct ProxyGroup: Sendable {
        public var name: String
        public var type: String
        public var now: String?
        public var options: [String]
    }

    public enum Failure: LocalizedError {
        case http(Int, String)
        case notRunning

        public var errorDescription: String? {
            switch self {
            case .http(let code, let body):
                return "Core API returned \(code)\(body.isEmpty ? "" : ": \(body)")"
            case .notRunning:
                return "Core is not running"
            }
        }
    }

    private let base: URL
    private let secret: String
    private let session: URLSession

    public init(port: Int, secret: String) {
        base = URL(string: "http://127.0.0.1:\(port)")!
        self.secret = secret

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        // The core is on loopback; a proxy setting the app itself installed must
        // not be applied to it, or switching a node would race the tunnel.
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    /// Polls until the core answers, or gives up. Called right after spawn:
    /// mihomo binds its controller after loading geodata, which on a cold start
    /// includes downloading it.
    public func waitUntilReady(timeout: TimeInterval = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await version()) != nil { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    public func version() async throws -> String {
        let object = try await get("/version") as? [String: Any]
        return object?["version"] as? String ?? "unknown"
    }

    // MARK: - Proxies

    public func groups() async throws -> [ProxyGroup] {
        guard let object = try await get("/proxies") as? [String: Any],
              let proxies = object["proxies"] as? [String: Any] else { return [] }

        return proxies.values.compactMap { value in
            guard let entry = value as? [String: Any],
                  let name = entry["name"] as? String,
                  let type = entry["type"] as? String,
                  let options = entry["all"] as? [String] else { return nil }
            return ProxyGroup(name: name, type: type,
                              now: entry["now"] as? String, options: options)
        }
    }

    /// Every node the config carries, in the order the selector lists them, with
    /// the group's own sub-groups filtered out.
    public func nodes(in group: String) async throws -> [Node] {
        guard let object = try await get("/proxies") as? [String: Any],
              let proxies = object["proxies"] as? [String: Any],
              let selector = proxies[group] as? [String: Any],
              let names = selector["all"] as? [String] else { return [] }

        return names.compactMap { name -> Node? in
            guard let entry = proxies[name] as? [String: Any],
                  let type = entry["type"] as? String else { return nil }
            // Groups appear in `all` alongside nodes; they are selectable but
            // are not places, so the server list must not show them as such.
            guard !Self.groupTypes.contains(type.lowercased()) else { return nil }

            // `history` is the core's own record of past delay probes; its last
            // entry is what the UI shows until a fresh probe replaces it.
            var latency: Int?
            if let history = entry["history"] as? [[String: Any]],
               let last = history.last, let delay = last["delay"] as? Int, delay > 0 {
                latency = delay
            }
            return Node(name: name, type: type, latency: latency)
        }
    }

    static let groupTypes: Set<String> = [
        "selector", "urltest", "fallback", "loadbalance", "relay",
    ]

    /// Points `group` at `node`. This is the whole of "pick a server".
    public func select(node: String, in group: String) async throws {
        _ = try await request(
            "PUT", "/proxies/\(escape(group))",
            body: ["name": node]
        )
    }

    /// Measures one node through the core.
    ///
    /// Returns nil rather than throwing for an unreachable node: a timeout is
    /// the expected answer for a node that is down, not an error the caller
    /// should surface as a failure of the probe.
    public func delay(
        node: String,
        url: String = "https://www.gstatic.com/generate_204",
        timeout: Int = 5000
    ) async -> Int? {
        var components = URLComponents(string: base.absoluteString + "/proxies/\(escape(node))/delay")
        components?.queryItems = [
            URLQueryItem(name: "url", value: url),
            URLQueryItem(name: "timeout", value: String(timeout)),
        ]
        guard let target = components?.url else { return nil }

        var request = URLRequest(url: target)
        request.timeoutInterval = TimeInterval(timeout) / 1000 + 3
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = object["delay"] as? Int, delay > 0 else { return nil }
        return delay
    }

    /// Probes every node concurrently.
    ///
    /// The core multiplexes these itself — each probe is an independent
    /// connection through that node's own outbound — so a full pass costs about
    /// as long as its slowest node rather than the sum. Concurrency is still
    /// capped, because a subscription with sixty nodes would otherwise open
    /// sixty TLS handshakes at once and measure congestion instead of latency.
    public func delays(nodes: [String], concurrency: Int = 8) async -> [String: Int] {
        var results: [String: Int] = [:]
        var index = 0

        await withTaskGroup(of: (String, Int?).self) { group in
            func addNext() {
                guard index < nodes.count else { return }
                let node = nodes[index]
                index += 1
                group.addTask { [self] in (node, await delay(node: node)) }
            }
            for _ in 0..<min(concurrency, nodes.count) { addNext() }

            while let (node, delay) = await group.next() {
                if let delay { results[node] = delay }
                addNext()
            }
        }
        return results
    }

    // MARK: - Config

    /// Live-patches the running core. Used for the mode switch, so toggling TUN
    /// does not drop the tunnel.
    public func patchConfig(_ patch: [String: Any]) async throws {
        _ = try await request("PATCH", "/configs", body: patch)
    }

    /// Reloads from a config file on disk, replacing proxies and rules in place.
    public func reload(path: String) async throws {
        _ = try await request("PUT", "/configs?force=true", body: ["path": path])
    }

    // MARK: - Streams

    /// Cumulative up/down counters, one sample per second.
    ///
    /// mihomo streams these as newline-delimited JSON on a connection it never
    /// closes, so this is an `AsyncStream` rather than a request: the caller
    /// cancels by dropping the iteration.
    public nonisolated func trafficStream() -> AsyncStream<Traffic> {
        lineStream(path: "/traffic") { object in
            guard let up = object["up"] as? Int64 ?? (object["up"] as? NSNumber)?.int64Value,
                  let down = object["down"] as? Int64 ?? (object["down"] as? NSNumber)?.int64Value
            else { return nil }
            return Traffic(up: up, down: down)
        }
    }

    /// Total bytes transferred by the current core process.
    public func totals() async throws -> Traffic {
        guard let object = try await get("/connections") as? [String: Any] else {
            return Traffic(up: 0, down: 0)
        }
        return Traffic(
            up: (object["uploadTotal"] as? NSNumber)?.int64Value ?? 0,
            down: (object["downloadTotal"] as? NSNumber)?.int64Value ?? 0
        )
    }

    private nonisolated func lineStream<T: Sendable>(
        path: String,
        decode: @escaping @Sendable ([String: Any]) -> T?
    ) -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task {
                var request = URLRequest(url: base.appendingPathComponent(path))
                request.timeoutInterval = .infinity
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                do {
                    let (bytes, _) = try await session.bytes(for: request)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let value = decode(object) else { continue }
                        continuation.yield(value)
                    }
                } catch {
                    // The core going away ends the stream; the supervisor is what
                    // notices and reports it, not this.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: -

    private func get(_ path: String) async throws -> Any {
        try await request("GET", path, body: nil)
    }

    @discardableResult
    private func request(_ method: String, _ path: String, body: [String: Any]?) async throws -> Any {
        guard let url = URL(string: base.absoluteString + path) else { throw Failure.notRunning }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notRunning }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    }

    /// Node names carry spaces, slashes and emoji, all of which have to survive
    /// the round trip into a path component.
    private nonisolated func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}
