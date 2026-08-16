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
    /// Nodes whose probe has not come back yet in the current pass.
    ///
    /// Per node, not one flag for the whole pass: a single flag made every row
    /// show `…` until the slowest node timed out, which hid the results that had
    /// already arrived and made an otherwise streaming measurement look like it
    /// took as long as its worst entry.
    @Published public private(set) var pendingProbes: Set<String> = []
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

        // Warm the core as soon as there is a subscription, so the first latency
        // pass is instant rather than paying for a cold start.
        Task { await ensureCoreRunning() }
    }

    /// The panel's own auto-picker, if its selector offers one.
    ///
    /// Taken in the selector's order, so a panel that lists a general picker
    /// first and country-specific ones later gets the general one — those later
    /// ones are named for a country and belong in the list as ordinary rows.
    public var panelAutoNode: Node? {
        nodes.first { $0.isAutoPicker }
    }

    /// Everything the selector offers except the picker promoted to the top,
    /// so it is not listed twice.
    public var selectableNodes: [Node] {
        guard let auto = panelAutoNode else { return nodes }
        return nodes.filter { $0.name != auto.name }
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

            if state.isConnected || core.isRunning {
                // Reload in place rather than reconnecting: a refresh should not
                // drop a working tunnel, and the idle core has to pick up the new
                // nodes too — otherwise the list falls back to the raw `proxies:`
                // and the panel's own groups disappear from it.
                try await reloadRunningCore()
            } else {
                // No core yet: the raw proxy list is all there is to show until
                // one comes up and the selector can be read properly.
                nodes = try nodesFromPanelConfig()
                await ensureCoreRunning()
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

    /// Brings the core up **without routing anything through it**.
    ///
    /// The core running and the tunnel being on are separate facts, and keeping
    /// them separate is what makes a latency pass instant: the outbounds a probe
    /// needs already exist. Connecting then only has to point traffic at a core
    /// that is already warm — which is how FlClash and Clash Verge Rev behave,
    /// and why their ping is immediate.
    ///
    /// Nothing here touches system state: no proxy settings are written and no
    /// TUN block is in the config.
    @discardableResult
    public func ensureCoreRunning() async -> Bool {
        guard hasSubscription else { return false }
        // The helper's core counts: in TUN mode it is the one answering. Checked
        // regardless of `activeMode`, because a core left running by a previous
        // session is running whether or not this one knows about it.
        if (try? helper.status().running) == true { return true }
        if core.isRunning { return true }

        do {
            let yaml = try MihomoConfig.build(
                panelYAML: try loadPanelYAML(),
                overrides: overrides(mode: .systemProxy)
            )
            try yaml.write(to: configURL, atomically: true, encoding: .utf8)
            try core.validate(configPath: configURL)
            try core.start(configPath: configURL)
        } catch {
            lastError = error.localizedDescription
            return false
        }

        guard await api.waitUntilReady() else {
            lastError = "The core did not start"
            core.stop()
            return false
        }
        try? await discoverSelector()
        restoreLatencies()
        LogStore.shared.followCore(api)
        LogStore.shared.client("Core ready — \(nodes.count) entries offered")
        return true
    }

    public func connect() async {
        guard !state.isBusy, !state.isConnected else { return }
        guard hasSubscription else {
            lastError = "Add a subscription first"
            return
        }
        state = .connecting
        lastError = nil
        LogStore.shared.client("Connecting via \(preferences.tunnelMode == .tun ? "TUN" : "system proxy")")

        do {
            let mode = preferences.tunnelMode
            switch mode {
            case .systemProxy:
                // The core is already up for probing; connecting is only a
                // matter of pointing the machine at it.
                guard await ensureCoreRunning() else {
                    throw MihomoProcess.Failure.exited(0, lastError ?? "core unavailable")
                }
                if preferences.proxySnapshot == nil {
                    preferences.proxySnapshot = SystemProxy.snapshot()
                }
                SystemProxy.enable(port: preferences.mixedPort)

            case .tun:
                // TUN needs the core to run as root, so the idle one has to go.
                core.stop()
                let yaml = try MihomoConfig.build(
                    panelYAML: try loadPanelYAML(),
                    overrides: overrides(mode: .tun)
                )
                try helper.version()
                try helper.start(config: yaml)

                // Longer than the default: a panel config with `rule-providers`
                // downloads them before the core binds its controller, and the
                // window where the app still says "connecting" while traffic is
                // already flowing is exactly what that timeout governs.
                LogStore.shared.followCore(api)
                guard await api.waitUntilReady(timeout: 90) else {
                    throw MihomoProcess.Failure.exited(0, coreLog)
                }
                // A TUN interface that fails to come up does not stop the core:
                // it keeps running and keeps answering its API, so without this
                // the app reports a healthy tunnel while nothing is routed.
                try await Task.sleep(nanoseconds: 700_000_000)
                if let reason = MihomoProcess.tunFailure(in: coreLog) {
                    throw MihomoProcess.Failure.exited(0, reason)
                }
            }
            activeMode = mode

            try await discoverSelector()
            await applySelection()

            startedAt = Date()
            uptime = 0
            sessionUp = 0
            sessionDown = 0
            beginMonitoring()
            state = .connected
            LogStore.shared.client("Connected — \(selectedNode ?? "auto")")
        } catch {
            lastError = error.localizedDescription
            LogStore.shared.client("Connect failed: \(error.localizedDescription)", level: .error)
            await teardown()
            state = .failed(error.localizedDescription)
            // Fall back to an idle core so the server list and ping keep working.
            await ensureCoreRunning()
        }
    }

    public func disconnect() async {
        guard state != .disconnected else { return }
        state = .disconnecting
        LogStore.shared.client("Disconnecting")
        await teardown()
        state = .disconnected
        // Traffic stops; the core does not. Leaving it up is what keeps the next
        // latency pass instant.
        await ensureCoreRunning()
    }

    /// Stops routing. Teardown runs in the reverse order of ``connect()``: proxy
    /// settings go back before the core stops, so no window exists where the
    /// machine points at a listener that is already gone.
    private func teardown() async {
        trafficTask?.cancel()
        trafficTask = nil
        uptimeTimer?.invalidate()
        uptimeTimer = nil

        SystemProxy.restore(preferences.proxySnapshot)
        preferences.proxySnapshot = nil

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

    /// How each node's transport reads, taken from the subscription.
    ///
    /// The RESTful API reports a bare type — `Vless`, `Hysteria2` — but the
    /// panel's own list distinguishes Reality from plain TLS, and that is the
    /// difference a user picks on. Only the config has it.
    private func protocolLabels() -> [String: String] {
        guard let yaml = try? loadPanelYAML(),
              let root = try? Yams.load(yaml: yaml) as? [String: Any],
              let proxies = root["proxies"] as? [[String: Any]] else { return [:] }

        var labels: [String: String] = [:]
        for proxy in proxies {
            guard let name = proxy["name"] as? String,
                  let type = (proxy["type"] as? String)?.lowercased() else { continue }
            switch type {
            case "vless", "vmess":
                let family = type == "vless" ? "VLESS" : "VMess"
                if proxy["reality-opts"] != nil { labels[name] = "\(family) Reality" }
                else if proxy["tls"] as? Bool == true { labels[name] = "\(family) TLS" }
                else { labels[name] = family }
            case "hysteria2":
                // hysteria2 is TLS by definition; the panel writes it out anyway.
                labels[name] = "Hysteria2 TLS"
            case "trojan": labels[name] = "Trojan"
            case "ss": labels[name] = "Shadowsocks"
            default: labels[name] = type.uppercased()
            }
        }
        return labels
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
        var listed = try await api.nodes(in: selectorGroup)

        // A group has no transport of its own, so it borrows the one its members
        // share — which is what the panel's own list shows for it.
        let labels = protocolLabels()
        let membership = Dictionary(groups.map { ($0.name, $0.options) }) { first, _ in first }
        for index in listed.indices {
            if let label = labels[listed[index].name] {
                listed[index].protocolLabel = label
            } else if let members = membership[listed[index].name] {
                listed[index].protocolLabel = members.lazy.compactMap { labels[$0] }.first
            }
        }
        nodes = listed
        restoreLatencies()
    }

    private func reloadRunningCore() async throws {
        // An idle core routes nothing, so it never gets a TUN block — it runs as
        // the user and could not create a `utun` device anyway.
        let mode: TunnelMode = state.isConnected
            ? (activeMode ?? preferences.tunnelMode)
            : .systemProxy
        let yaml = try MihomoConfig.build(
            panelYAML: try loadPanelYAML(),
            overrides: overrides(mode: mode)
        )
        switch mode {
        case .tun where state.isConnected:
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

    /// Measures every node the selector offers.
    ///
    /// Instant, because a core is always running — see ``ensureCoreRunning()``.
    /// The probes go through that core's own outbounds whether or not traffic is
    /// currently being routed through it.
    public func pingAll() async {
        guard !isPinging else { return }
        isPinging = true
        defer { isPinging = false }

        guard await ensureCoreRunning() else { return }
        if nodes.isEmpty { try? await discoverSelector() }
        guard !nodes.isEmpty else { return }

        // Existing numbers stay on screen until their replacement lands, so the
        // list does not flash to n/a on every pass.
        pendingProbes = Set(nodes.map(\.name))
        defer { pendingProbes = [] }

        let measured = await api.delays(nodes: nodes.map(\.name)) { name, delay in
            await Self.record(name: name, delay: delay, on: self)
        }
        preferences.latencies = measured
        if autoSelect { await applySelection() }
    }

    /// Applies one node's result as it lands, on the main actor.
    private static func record(name: String, delay: Int?, on controller: TunnelController) async {
        controller.pendingProbes.remove(name)
        guard let index = controller.nodes.firstIndex(where: { $0.name == name }) else { return }
        controller.nodes[index].latency = delay
    }

    /// Puts the last measured numbers back after the node list is rebuilt, so a
    /// screen change or a reconnect does not blank the server list.
    private func restoreLatencies() {
        let saved = preferences.latencies
        guard !saved.isEmpty else { return }
        for index in nodes.indices where nodes[index].latency == nil {
            nodes[index].latency = saved[nodes[index].name]
        }
    }

    // MARK: - Connections

    /// Every connection the core currently has open.
    public func currentConnections() async -> [MihomoAPI.Connection] {
        (try? await api.connections()) ?? []
    }

    /// Closes a specific set — one process's connections, or a single one.
    ///
    /// The core reopens whatever the program still wants, so this reads as
    /// "move this app onto the node I just picked" rather than as cutting it
    /// off: existing connections would otherwise stay on the old node until
    /// they aged out on their own.
    public func close(connections ids: [String]) async {
        guard !ids.isEmpty else { return }
        var closed = 0
        for id in ids {
            do {
                try await api.close(connection: id)
                closed += 1
            } catch {
                // A connection that closed on its own between the poll and the
                // click is the common case here, not a failure worth surfacing.
                continue
            }
        }
        LogStore.shared.client("Closed \(closed) connection(s)")
    }

    /// Closes them all. The core reopens whatever is still wanted, which is how
    /// traffic is forced onto a node that was just selected instead of waiting
    /// for existing connections to age out.
    public func closeAllConnections() async {
        do {
            try await api.closeAllConnections()
            LogStore.shared.client("Closed all connections")
        } catch {
            lastError = error.localizedDescription
        }
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
        if let snapshot = preferences.proxySnapshot {
            SystemProxy.restore(snapshot)
            preferences.proxySnapshot = nil
        }

        // The same for the unprivileged core: a child is reparented to launchd
        // when its parent dies, so a crash, a force-quit or an in-app update
        // leaves one running and holding the controller port.
        let reaped = MihomoProcess.reapOrphans(dataDirectory: support)
        if !reaped.isEmpty {
            LogStore.shared.client("Stopped \(reaped.count) orphaned core(s) from a previous run")
        }

        // A privileged core outlives the app that started it — it is a root
        // daemon's child, not ours. Left running it holds the controller port,
        // so the core this session starts cannot bind it and every API call
        // silently addresses the *old* core instead: wrong nodes, wrong
        // connections, and a tunnel still carrying traffic while the window says
        // "Отключено".
        if (try? helper.status().running) == true {
            LogStore.shared.client("Found a privileged core from a previous session — stopping it")
            try? helper.stop()
        }
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
