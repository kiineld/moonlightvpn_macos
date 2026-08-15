import Foundation
import Combine
import Yams

/// The single object the UI drives and observes.
///
/// It owns the order things happen in, which for a tunnel is not
/// interchangeable — the comments on ``connect()`` say why each step is where it
/// is. Everything below it (the core process, the helper, the REST API, the
/// panel) is stateless with respect to the others.
@MainActor
public final class TunnelController: ObservableObject {

    // MARK: Published state

    @Published public private(set) var state: ConnectionState = .disconnected
    @Published public private(set) var nodes: [Node] = []
    @Published public private(set) var info = SubscriptionInfo()
    @Published public private(set) var subscriptionSource: SubscriptionClient.Source?
    @Published public private(set) var uptime: Int = 0
    /// Bytes moved by this session, from the core's own counters.
    @Published public private(set) var sessionUp: Int64 = 0
    @Published public private(set) var sessionDown: Int64 = 0
    @Published public private(set) var rateUp: Int64 = 0
    @Published public private(set) var rateDown: Int64 = 0
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isPinging = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var lastRefresh: Date?

    @Published public var selectedNode: String?
    @Published public var autoSelect: Bool

    // MARK: Collaborators

    private let preferences: Preferences
    private let core: MihomoProcess
    private let helper = HelperClient()
    private let subscriptions: SubscriptionClient
    private var api: MihomoAPI

    private let support: URL
    private let coreBinary: URL
    private var configURL: URL { support.appendingPathComponent("config.yaml") }
    private var panelURL: URL { support.appendingPathComponent("subscription.yaml") }

    /// The proxy group the app steers. Discovered from the running core rather
    /// than assumed — see ``MihomoConfig/primarySelectorName(groups:rules:)``.
    private var selectorGroup: String?
    private var trafficTask: Task<Void, Never>?
    private var uptimeTimer: Timer?
    private var startedAt: Date?
    /// Which transport actually started the core, so teardown undoes the same
    /// one even if the preference changed while connected.
    private var activeMode: TunnelMode?

    public init(preferences: Preferences = .shared, bundle: Bundle = .main) {
        self.preferences = preferences
        self.subscriptions = SubscriptionClient(device: DeviceIdentity(
            hwid: preferences.hwid,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: Self.hardwareModel(),
            appVersion: bundle.appVersion
        ))

        support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonlight", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        coreBinary = bundle.coreBinaryURL
        core = MihomoProcess(
            binary: bundle.coreBinaryURL,
            dataDirectory: support.appendingPathComponent("core", isDirectory: true)
        )
        api = MihomoAPI(port: preferences.controllerPort, secret: preferences.coreSecret)

        selectedNode = preferences.selectedNode
        autoSelect = preferences.autoSelect
        // Cached figures outlive the subscription they describe, and a fresh
        // install that inherited them from a removed plan would show days and
        // traffic for a subscription that is not there.
        if preferences.subscriptionURL?.isEmpty == false {
            info = preferences.cachedInfo ?? SubscriptionInfo()
        } else {
            preferences.cachedInfo = nil
            info = SubscriptionInfo()
        }

        core.onUnexpectedExit = { [weak self] status in
            Task { @MainActor in
                self?.handleCoreExit(status)
            }
        }

        recoverFromCrash()
    }

    public var hasSubscription: Bool {
        preferences.subscriptionURL?.isEmpty == false
    }

    public var subscriptionURL: String? { preferences.subscriptionURL }
    public var tunnelMode: TunnelMode { preferences.tunnelMode }
    public var helperInstalled: Bool { HelperInstaller.isInstalled && helper.isInstalled }

    /// The core's own log tail, for the settings screen's diagnostics.
    public var coreLog: String {
        activeMode == .tun ? ((try? helper.status().log) ?? "") : core.recentLog
    }

    // MARK: - Subscription

    /// Adds a subscription and fetches it. The design promises a link from the
    /// bot "adds itself", so this both stores and loads rather than only storing.
    @discardableResult
    public func importSubscription(_ url: String) async -> Bool {
        guard SubscriptionClient.normalize(url) != nil else {
            lastError = "That does not look like a subscription link"
            return false
        }
        preferences.subscriptionURL = url
        return await refresh()
    }

    public func removeSubscription() async {
        if state != .disconnected { await disconnect() }
        preferences.subscriptionURL = nil
        preferences.cachedInfo = nil
        preferences.selectedNode = nil
        try? FileManager.default.removeItem(at: panelURL)
        nodes = []
        info = SubscriptionInfo()
        subscriptionSource = nil
        selectedNode = nil
    }

    @discardableResult
    public func refresh() async -> Bool {
        guard let url = preferences.subscriptionURL, !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await subscriptions.fetch(url)
            try result.yaml.write(to: panelURL, atomically: true, encoding: .utf8)
            subscriptionSource = result.source

            // The `/info` endpoint carries the device count the headers do not,
            // but the headers are what every panel implements consistently — so
            // info first, headers layered on top, field by field.
            var merged = (await subscriptions.fetchInfo(url) ?? SubscriptionInfo())
                .merging(result.info)
            merged.title = merged.title ?? info.title
            info = merged
            preferences.cachedInfo = merged
            lastRefresh = Date()
            lastError = nil

            if state.isConnected {
                // Reload in place rather than reconnecting: a refresh should not
                // drop a working tunnel.
                try await reloadRunningCore()
            } else {
                nodes = try nodesFromPanelConfig()
            }
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Connect

    public func toggle() async {
        state.isConnected ? await disconnect() : await connect()
    }

    public func connect() async {
        guard !state.isBusy, !state.isConnected else { return }
        guard hasSubscription else {
            lastError = "Add a subscription first"
            return
        }
        state = .connecting
        lastError = nil

        do {
            let mode = preferences.tunnelMode
            let panelYAML = try loadPanelYAML()
            let yaml = try MihomoConfig.build(panelYAML: panelYAML, overrides: overrides(mode: mode))

            switch mode {
            case .systemProxy:
                // Validate before starting: `mihomo -t` names the offending key,
                // whereas a core that dies at startup leaves only an exit status.
                try yaml.write(to: configURL, atomically: true, encoding: .utf8)
                try core.validate(configPath: configURL)
                try core.start(configPath: configURL)

            case .tun:
                try helper.version()
                try helper.start(config: yaml)
            }
            activeMode = mode

            guard await api.waitUntilReady() else {
                throw MihomoProcess.Failure.exited(0, coreLog)
            }

            // A TUN interface that fails to come up does not stop the core: it
            // keeps running and keeps answering its API, so without this check
            // the app reports a healthy tunnel while nothing is routed through
            // it. The interface is established shortly after the API binds, so
            // the log is given a moment to catch up.
            if mode == .tun {
                try await Task.sleep(nanoseconds: 700_000_000)
                if let reason = MihomoProcess.tunFailure(in: coreLog) {
                    throw MihomoProcess.Failure.exited(0, reason)
                }
            }

            // The selector has to exist before a node can be picked, and picking
            // has to happen before traffic is let in — otherwise the first
            // seconds go through whatever node the config happened to list first.
            try await discoverSelector()
            await applySelection()

            // System proxy goes on last, once the core is answering. Setting it
            // first would break every app on the machine for as long as the core
            // took to come up, including this one.
            if mode == .systemProxy {
                if preferences.proxySnapshot == nil {
                    preferences.proxySnapshot = SystemProxy.snapshot()
                }
                SystemProxy.enable(port: preferences.mixedPort)
            }

            startedAt = Date()
            uptime = 0
            sessionUp = 0
            sessionDown = 0
            beginMonitoring()
            state = .connected
        } catch {
            lastError = error.localizedDescription
            await teardown()
            state = .failed(error.localizedDescription)
        }
    }

    public func disconnect() async {
        guard state != .disconnected else { return }
        state = .disconnecting
        await teardown()
        state = .disconnected
    }

    /// Teardown runs in the reverse order of ``connect()``: proxy settings go
    /// back before the core stops, so no window exists where the machine points
    /// at a listener that is already gone.
    private func teardown() async {
        trafficTask?.cancel()
        trafficTask = nil
        uptimeTimer?.invalidate()
        uptimeTimer = nil

        if activeMode == .systemProxy || activeMode == nil {
            SystemProxy.restore(preferences.proxySnapshot)
            preferences.proxySnapshot = nil
        }

        switch activeMode {
        case .tun: try? helper.stop()
        case .systemProxy, .none: core.stop()
        }
        activeMode = nil

        uptime = 0
        rateUp = 0
        rateDown = 0
        startedAt = nil
    }

    // MARK: - Selection

    public func select(node: String) async {
        selectedNode = node
        autoSelect = false
        preferences.selectedNode = node
        preferences.autoSelect = false
        await applySelection()
    }

    /// "Авто" — hand the choice to the config's own latency group if it has one,
    /// and otherwise pick the fastest node this app has measured.
    public func selectAuto() async {
        autoSelect = true
        preferences.autoSelect = true
        await applySelection()
    }

    private func applySelection() async {
        guard let group = selectorGroup, state != .disconnected else { return }
        do {
            let target: String?
            if autoSelect {
                target = try await autoTarget(in: group)
            } else {
                // A node saved from a previous subscription may be gone; falling
                // back to the first one beats leaving the selector wherever the
                // core happened to put it.
                target = nodes.contains(where: { $0.name == selectedNode })
                    ? selectedNode
                    : nodes.first?.name
            }
            guard let target else { return }
            try await api.select(node: target, in: group)
            if !autoSelect { selectedNode = target }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The config's own `url-test`/`fallback` group if it has one — the panel
    /// keeps that measured and it re-picks on its own. Failing that, the fastest
    /// node from the last probe.
    private func autoTarget(in group: String) async throws -> String? {
        let groups = try await api.groups()
        if let selector = groups.first(where: { $0.name == group }) {
            let latencyGroup = groups.first {
                selector.options.contains($0.name) &&
                ["URLTest", "Fallback", "LoadBalance"].contains($0.type)
            }
            if let latencyGroup { return latencyGroup.name }
        }
        let measured = nodes.compactMap { node in node.latency.map { ($0, node.name) } }
        return measured.min(by: { $0.0 < $1.0 })?.1 ?? nodes.first?.name
    }

    private func discoverSelector() async throws {
        let groups = try await api.groups()
        let selectors = groups.filter { $0.type == "Selector" }

        // The config's rules are the authority on which group is *the* one; the
        // running core does not expose them, so the generated config is re-read.
        let yaml = activeMode == .tun
            ? try loadPanelYAML()
            : (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if let rules = (try? Yams.load(yaml: yaml) as? [String: Any])?["rules"] as? [String] {
            let name = MihomoConfig.primarySelectorName(
                groups: selectors.map { ["name": $0.name, "type": "select"] },
                rules: rules
            )
            if selectors.contains(where: { $0.name == name }) {
                selectorGroup = name
            }
        }
        if selectorGroup == nil { selectorGroup = selectors.first?.name }
        guard let selectorGroup else {
            throw MihomoConfig.Failure.noProxies
        }
        nodes = try await api.nodes(in: selectorGroup)
    }

    private func reloadRunningCore() async throws {
        let yaml = try MihomoConfig.build(
            panelYAML: try loadPanelYAML(),
            overrides: overrides(mode: activeMode ?? preferences.tunnelMode)
        )
        switch activeMode {
        case .tun:
            // The helper owns its config file, so a reload there is a restart of
            // the core it supervises — the tunnel blips, which is the cost of not
            // letting an unprivileged process write a root-read path.
            try helper.start(config: yaml)
            _ = await api.waitUntilReady()
        default:
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
            try core.validate(configPath: configURL)
            try await api.reload(path: configURL.path)
        }
        try await discoverSelector()
        await applySelection()
    }

    // MARK: - Latency

    /// Measures every node.
    ///
    /// While the tunnel is up the probes go through the running core. While it
    /// is **down** they go through a throwaway one: the outbounds a probe needs
    /// do not exist until a core is running, but nothing about that requires the
    /// core to be *the* tunnel. A second instance on its own ports, with no
    /// system proxy applied and no TUN block, measures the same nodes and
    /// touches no system state.
    ///
    /// This is why the button is live when disconnected — picking a server is
    /// exactly when the latencies matter, and requiring a connection first made
    /// the numbers useless for the choice they inform.
    public func pingAll() async {
        guard !isPinging else { return }
        if nodes.isEmpty { nodes = (try? nodesFromPanelConfig()) ?? [] }
        guard !nodes.isEmpty else { return }

        isPinging = true
        defer { isPinging = false }

        let measured: [String: Int]
        if state.isConnected {
            measured = await api.delays(nodes: nodes.map(\.name))
        } else {
            measured = await probeWithThrowawayCore()
        }

        for index in nodes.indices {
            nodes[index].latency = measured[nodes[index].name]
        }
        if autoSelect { await applySelection() }
    }

    /// Starts a core purely to measure, then stops it.
    ///
    /// Its ports are offset from the tunnel's so a probe can never collide with
    /// a core this app is already running, and it shares the tunnel's data
    /// directory so the geo databases are not downloaded a second time.
    private func probeWithThrowawayCore() async -> [String: Int] {
        let port = preferences.controllerPort + 1000
        let secret = preferences.coreSecret
        let probeConfig = support.appendingPathComponent("probe.yaml")

        do {
            let yaml = try MihomoConfig.build(
                panelYAML: try loadPanelYAML(),
                overrides: MihomoConfig.Overrides(
                    controllerPort: port,
                    secret: secret,
                    mixedPort: preferences.mixedPort + 1000,
                    // Never TUN: a probe must not create an interface or touch
                    // the routing table.
                    mode: .systemProxy,
                    splitMode: .all,
                    dataDirectory: support.appendingPathComponent("core").path
                )
            )
            try yaml.write(to: probeConfig, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            return [:]
        }

        let prober = MihomoProcess(
            binary: coreBinary,
            dataDirectory: support.appendingPathComponent("core", isDirectory: true)
        )
        do {
            try prober.start(configPath: probeConfig)
        } catch {
            lastError = error.localizedDescription
            return [:]
        }
        defer { prober.stop() }

        let probeAPI = MihomoAPI(port: port, secret: secret)
        guard await probeAPI.waitUntilReady(timeout: 25) else {
            lastError = "Could not start a core to measure with"
            return [:]
        }
        return await probeAPI.delays(nodes: nodes.map(\.name))
    }

    // MARK: - Settings that change the config

    public func setTunnelMode(_ mode: TunnelMode) async {
        guard mode != preferences.tunnelMode else { return }
        preferences.tunnelMode = mode
        // A mode change swaps which process owns the core, so it cannot be a
        // live patch — it is a reconnect, and only if one was up.
        if state.isConnected {
            await disconnect()
            await connect()
        }
    }

    public func setSplitMode(_ mode: SplitMode) async {
        preferences.splitMode = mode
        await reapplyRouting()
    }

    public func setSplitRules(_ rules: [SplitRule]) async {
        preferences.splitRules = rules
        await reapplyRouting()
    }

    public var splitMode: SplitMode { preferences.splitMode }
    public var splitRules: [SplitRule] { preferences.splitRules }

    private func reapplyRouting() async {
        guard state.isConnected else { return }
        do {
            try await reloadRunningCore()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Monitoring

    private func beginMonitoring() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.uptime = Int(Date().timeIntervalSince(startedAt))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        uptimeTimer = timer

        trafficTask = Task { [api] in
            // mihomo's /traffic emits per-second deltas, so the session totals
            // are accumulated here rather than read back from /connections —
            // which resets whenever a connection closes.
            for await sample in api.trafficStream() {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.rateUp = sample.up
                    self.rateDown = sample.down
                    self.sessionUp += sample.up
                    self.sessionDown += sample.down
                }
            }
        }
    }

    private func handleCoreExit(_ status: Int32) {
        guard state.isConnected || state == .connecting else { return }
        let detail = core.recentLog.split(whereSeparator: \.isNewline).suffix(3).joined(separator: "\n")
        lastError = "Core stopped unexpectedly (status \(status))\(detail.isEmpty ? "" : "\n\(detail)")"
        Task { await teardown(); state = .failed(lastError ?? "Core stopped") }
    }

    /// A force-quit while connected leaves the machine's proxy pointing at a
    /// core that no longer exists, which reads to the user as "the internet is
    /// broken". The snapshot outlives the process precisely so this can be
    /// undone on the next launch.
    private func recoverFromCrash() {
        guard let snapshot = preferences.proxySnapshot else { return }
        SystemProxy.restore(snapshot)
        preferences.proxySnapshot = nil
    }

    // MARK: -

    private func overrides(mode: TunnelMode) -> MihomoConfig.Overrides {
        MihomoConfig.Overrides(
            controllerPort: preferences.controllerPort,
            secret: preferences.coreSecret,
            mixedPort: preferences.mixedPort,
            mode: mode,
            // Per-process rules need an interface to route; in system-proxy mode
            // mihomo never sees the process, so the screen is honest about being
            // inert rather than silently doing nothing.
            splitMode: preferences.splitMode,
            // Process rules need an interface to route: under a system proxy the
            // core never sees the process, so they would be written and silently
            // never match. Domain and address rules work in both modes, so only
            // the process ones are dropped.
            splitRules: mode == .tun
                ? preferences.splitRules
                : preferences.splitRules.filter { !$0.kind.needsProcessMatching },
            dataDirectory: support.appendingPathComponent("core").path
        )
    }

    private func loadPanelYAML() throws -> String {
        try String(contentsOf: panelURL, encoding: .utf8)
    }

    private func nodesFromPanelConfig() throws -> [Node] {
        let yaml = try loadPanelYAML()
        guard let root = try Yams.load(yaml: yaml) as? [String: Any],
              let proxies = root["proxies"] as? [[String: Any]] else { return [] }
        return proxies.compactMap { proxy in
            guard let name = proxy["name"] as? String else { return nil }
            return Node(name: name,
                        type: proxy["type"] as? String ?? "unknown",
                        server: proxy["server"] as? String)
        }
    }

    /// "MacBook Pro" — what the design's device row shows, and what the panel's
    /// device list shows for this install.
    ///
    /// Splitting `hw.model` on capitals gets this wrong in the common case:
    /// `MacBookPro18,3` becomes "Mac Book Pro". Apple's product names are not
    /// derivable from the identifier, so the handful that exist are listed.
    nonisolated public static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let identifier = String(cString: bytes)

        // Longest prefix wins: MacBookPro must be tried before MacBook.
        let names = [
            ("MacBookPro", "MacBook Pro"),
            ("MacBookAir", "MacBook Air"),
            ("MacBook", "MacBook"),
            ("MacPro", "Mac Pro"),
            ("MacStudio", "Mac Studio"),
            ("Macmini", "Mac mini"),
            ("iMacPro", "iMac Pro"),
            ("iMac", "iMac"),
            ("Mac", "Mac"),
        ]
        for (prefix, name) in names where identifier.hasPrefix(prefix) {
            return name
        }
        // The generation suffix is dropped: this is a device name, not a spec.
        let letters = identifier.prefix { !$0.isNumber }
        return letters.isEmpty ? identifier : String(letters)
    }
}

public extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// The bundled core. Falls back to the repository layout so a `swift run`
    /// build outside an app bundle still finds it.
    var coreBinaryURL: URL {
        if let resource = url(forResource: "mihomo", withExtension: nil) {
            return resource
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/mihomo/mihomo")
    }

    var helperBinaryURL: URL {
        url(forResource: "moonlight-helper", withExtension: nil)
            ?? bundleURL.appendingPathComponent("Contents/Resources/moonlight-helper")
    }
}
