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
    /// Uptime and speeds, which tick every second — see ``TrafficMeter`` for
    /// why they are not published here.
    public let meter = TrafficMeter()
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isPinging = false
    /// Nodes whose probe has not come back yet in the current pass.
    ///
    /// Per node, not one flag for the whole pass: a single flag made every row
    /// show `…` until the slowest node timed out, which hid the results that had
    /// already arrived and made an otherwise streaming measurement look like it
    /// took as long as its worst entry.
    @Published public private(set) var pendingProbes: Set<String> = []
    /// What went wrong last, as a kind the app words for the user. Cleared by
    /// the next success of the same thing.
    @Published public private(set) var issue: TunnelIssue?
    @Published public private(set) var lastRefresh: Date?

    @Published public var selectedNode: String?
    @Published public var autoSelect: Bool
    /// Rules, everything through the server, or nothing — see ``RoutingMode``.
    @Published public private(set) var routingMode: RoutingMode
    /// How traffic reaches the core: the system proxy, or TUN through the
    /// helper. Published rather than read from the preferences, so a switch
    /// made while disconnected — which changes nothing else — still redraws
    /// the controls showing it.
    @Published public private(set) var tunnelMode: TunnelMode
    /// The subscription's proxy groups, in its order — what a rule of the
    /// user's own can point at besides `DIRECT` and `REJECT`.
    @Published public private(set) var ruleTargets: [String] = []
    /// The subscription's own rules, as it wrote them.
    @Published public private(set) var profileRules: [String] = []

    // MARK: Collaborators

    private let preferences: Preferences
    private let core: MihomoProcess
    private let helper = HelperClient()
    private let subscriptions: SubscriptionClient
    private var api: MihomoAPI

    private let support: URL
    private let coreBinary: URL
    private let helperBinary: URL
    private let geodata: URL
    /// The helper core's version as last read, so the check costs a process
    /// launch once rather than on every connect.
    private var configURL: URL { core.configURL }
    private var panelURL: URL { support.appendingPathComponent("subscription.yaml") }

    /// The proxy group the app steers. Discovered from the running core rather
    /// than assumed — see ``MihomoConfig/primarySelectorName(groups:rules:)``.
    private var selectorGroup: String?
    private var trafficTask: Task<Void, Never>?
    private var uptimeTimer: Timer?
    /// The idle core's start while it is under way, so a second caller waits
    /// for it instead of starting another — see ``ensureCoreRunning()``.
    private var coreStartup: Task<Bool, Never>?
    /// Set while one core hands over to another: the idle one stopping for
    /// TUN's privileged one, or either stopping on a disconnect. That work
    /// waits off the main thread, and an idle core started in the gap — by a
    /// ping or a refresh — would take the ports the other one needs.
    private var coreHandover = false
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
        // The core's home as well, since its config is written there before
        // the core first starts.
        let coreHome = support.appendingPathComponent("core", isDirectory: true)
        try? FileManager.default.createDirectory(at: coreHome, withIntermediateDirectories: true)
        // Where the config lived before it moved into the core's home.
        try? FileManager.default.removeItem(at: support.appendingPathComponent("config.yaml"))

        coreBinary = bundle.coreBinaryURL
        helperBinary = bundle.helperBinaryURL
        geodata = bundle.geodataURL
        core = MihomoProcess(binary: bundle.coreBinaryURL, dataDirectory: coreHome,
                             geodata: bundle.geodataURL)
        api = MihomoAPI(port: preferences.controllerPort, secret: preferences.coreSecret)

        selectedNode = preferences.selectedNode
        autoSelect = preferences.autoSelect
        routingMode = preferences.routingMode
        tunnelMode = preferences.tunnelMode
        lastRefresh = preferences.lastRefresh
        // Cached figures outlive the subscription they describe, and a fresh
        // install that inherited them from a removed plan would show days and
        // traffic for a subscription that is not there.
        if preferences.subscriptionURL?.isEmpty == false {
            var cached = preferences.cachedInfo ?? SubscriptionInfo()
            // Cached by an older build that read Remnawave's "never expires"
            // (a date in 2099) literally; fixed at the next refresh anyway.
            if let expire = cached.expire, SubscriptionInfo.expiry(expire) == nil {
                cached.expire = nil
            }
            info = cached
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
        retireSplitTunnelling()

        // Warm the core as soon as there is a subscription, so the first latency
        // pass is instant rather than paying for a cold start. The redactions
        // go first: the core's log quotes server addresses.
        Task {
            await updateRedactions()
            await refreshRoutingInputs()
            await ensureCoreRunning()
        }
        Task { await refreshHelperStatus() }
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

    /// Whether `link` is the subscription already in use — so a link that
    /// adds it again can say it will be updated rather than replaced.
    public func isCurrentSubscription(_ link: String) -> Bool {
        guard let current = preferences.subscriptionURL.flatMap(SubscriptionClient.normalize) else {
            return false
        }
        return SubscriptionClient.normalize(link) == current
    }

    /// Whether a previously fetched subscription is on disk, so there is
    /// something to show and run before the network answers.
    public var hasCachedSubscription: Bool {
        FileManager.default.fileExists(atPath: panelURL.path)
    }
    public var helperInstalled: Bool { HelperInstaller.isInstalled && helper.isInstalled }

    /// Whether the installed helper is this build's — its program and the core
    /// it runs. See ``refreshHelperStatus()``, which is what sets it.
    ///
    /// The helper and its root-owned copy of the core are made when it is
    /// installed, and nothing updated them afterwards. An app update that
    /// needed a newer core (the service's XHTTP servers need 1.19.30 or later)
    /// left TUN on the old one; one that fixed the helper itself (it ignored
    /// SIGTERM until 1.6.4) never reached anyone who had it installed.
    @Published public private(set) var helperIsCurrent = true

    /// Compares the installed helper with this build's, off the main thread.
    ///
    /// Stored and refreshed rather than computed where it is read: reading the
    /// core's version means launching it and waiting, and `waitUntilExit`
    /// spins the calling thread's run loop. Asked from inside the Settings
    /// view, that ran a layout pass in the middle of the one being drawn, and
    /// SwiftUI aborted — opening Settings crashed the app.
    public func refreshHelperStatus() async {
        guard helperInstalled else {
            helperIsCurrent = true
            return
        }
        let helperBinary = helperBinary, coreBinary = coreBinary
        helperIsCurrent = await Task.detached(priority: .utility) {
            let bundledCore = MihomoProcess.version(of: coreBinary)
            let installedCore = MihomoProcess.version(of: HelperInstaller.installedCore)
            // A build run outside an app bundle has no helper of its own to
            // compare, and should not keep asking to install one.
            let helperMatches = !FileManager.default.fileExists(atPath: helperBinary.path)
                || FileManager.default.contentsEqual(atPath: helperBinary.path,
                                                     andPath: HelperInstaller.installedHelper.path)
            return helperMatches && (bundledCore == nil || bundledCore == installedCore)
        }.value
    }

    /// Replaces the helper's copy of the core with this build's — the one admin
    /// prompt the install itself asks for.
    public func updateHelper() async throws {
        LogStore.shared.client("Updating the system helper to this build's core")
        let helperBinary = helperBinary, coreBinary = coreBinary, geodata = geodata
        try await Task.detached(priority: .userInitiated) {
            try HelperInstaller.install(helper: helperBinary, core: coreBinary,
                                        geodata: Geodata.files(in: geodata))
        }.value
        // launchd takes a moment to bring the daemon back and open its socket.
        for _ in 0..<30 {
            if (try? helper.version()) != nil { break }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        await refreshHelperStatus()
    }

    /// The core's own log tail, for the settings screen's diagnostics.
    public var coreLog: String {
        activeMode == .tun ? ((try? helper.status().log) ?? "") : core.recentLog
    }

    /// ``coreLog``, read off the main thread: in TUN mode it is a round trip
    /// to the helper.
    private func readCoreLog() async -> String {
        let helper = helper, core = core, tun = activeMode == .tun
        return await offMain { tun ? ((try? helper.status().log) ?? "") : core.recentLog }
    }

    /// Runs blocking work — a child process, a round trip to the helper, a
    /// parse of the whole subscription — off the main actor.
    ///
    /// All of it used to run on the main thread. A connect ran `networksetup`
    /// seven times per network service, the helper's stop waits for its core
    /// to exit, `mihomo -t`
    /// loads the whole config, and the subscription was parsed three times
    /// over: the window froze for a second or more at exactly the moment the
    /// moon was animating, and again after every refresh.
    nonisolated private func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    nonisolated private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    /// ``offMain(_:)`` with idle-core starts held off until it is done — see
    /// ``coreHandover``.
    private func handingOver<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        coreHandover = true
        defer { coreHandover = false }
        return try await offMain(work)
    }

    // MARK: - Subscription

    /// Adds a subscription and fetches it. The design promises a link from the
    /// bot "adds itself", so this both stores and loads rather than only storing.
    ///
    /// The link is only kept once it has actually loaded. It used to be stored
    /// first, so a mistyped link — or a server having a bad minute — replaced a
    /// working subscription with one that loads nothing.
    @discardableResult
    public func importSubscription(_ url: String) async -> Bool {
        guard SubscriptionClient.normalize(url) != nil else {
            issue = .invalidLink
            return false
        }
        return await refresh(from: url.trimmingCharacters(in: .whitespacesAndNewlines), adopting: true)
    }

    public func removeSubscription() async {
        if state != .disconnected { await disconnect() }
        preferences.subscriptionURL = nil
        preferences.cachedInfo = nil
        preferences.selectedNode = nil
        preferences.serverDescriptions = [:]
        preferences.lastRefresh = nil
        lastRefresh = nil
        issue = nil
        try? FileManager.default.removeItem(at: panelURL)
        nodes = []
        info = SubscriptionInfo()
        subscriptionSource = nil
        selectedNode = nil
        ruleTargets = []
        profileRules = []
    }

    @discardableResult
    public func refresh() async -> Bool {
        guard let url = preferences.subscriptionURL else { return false }
        return await refresh(from: url, adopting: false)
    }

    /// The intervals offered, in hours; 0 is never.
    nonisolated public static let autoUpdateChoices = [0, 1, 6, 12, 24]

    /// The offered interval nearest to `hours`. The service may suggest any
    /// number; snapping it here means the switch always shows what will happen.
    nonisolated public static func autoUpdateChoice(nearest hours: Int) -> Int {
        autoUpdateChoices.min { abs($0 - hours) < abs($1 - hours) } ?? 24
    }

    /// The effective auto-update interval in hours, 0 for never: the user's
    /// choice, or else what the service suggests, or else a day.
    public var autoUpdateHours: Int {
        Self.autoUpdateChoice(nearest: preferences.autoUpdateHours ?? info.updateIntervalHours ?? 24)
    }

    /// Refreshes if the interval has passed since the last successful refresh.
    /// Called on a timer, at launch and on wake; cheap when nothing is due.
    public func refreshIfDue() async {
        let hours = autoUpdateHours
        guard hours > 0, hasSubscription, !isRefreshing else { return }
        let due = (lastRefresh ?? .distantPast).addingTimeInterval(TimeInterval(hours) * 3600)
        guard Date() >= due else { return }
        LogStore.shared.client("Auto-updating the subscription (every \(hours) h)")
        await refresh()
    }

    private func refresh(from url: String, adopting: Bool) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await subscriptions.fetch(url)
            let replacing = adopting && url != preferences.subscriptionURL
            if adopting {
                preferences.subscriptionURL = url
            }
            if replacing {
                // Another subscription's choices mean nothing for this one.
                preferences.selectedNode = nil
                preferences.latencies = [:]
                preferences.serverDescriptions = [:]
                selectedNode = nil
            }
            try result.yaml.write(to: panelURL, atomically: true, encoding: .utf8)
            subscriptionSource = result.source

            // The `/info` endpoint carries the device count the headers do not,
            // but the headers are what every subscription server implements
            // consistently — so info first, headers layered on top.
            var merged = (await subscriptions.fetchInfo(url) ?? SubscriptionInfo())
                .merging(result.info)
            if !replacing { merged.title = merged.title ?? info.title }
            info = merged
            preferences.cachedInfo = merged
            lastRefresh = Date()
            preferences.lastRefresh = lastRefresh
            issue = nil
            await updateRedactions()
            await refreshRoutingInputs()

            if state.isConnected || core.isRunning {
                // Reload in place rather than reconnecting: a refresh should not
                // drop a working tunnel, and the idle core has to pick up the new
                // nodes too — otherwise the list falls back to the raw `proxies:`
                // and the config's own groups disappear from it.
                try await reloadRunningCore()
            } else {
                // No core yet: the raw proxy list is all there is to show until
                // one comes up and the selector can be read properly — but only
                // when there is nothing better on screen. Swapping a selector
                // list for the raw one and back made every refresh flicker
                // between two different lists and counts.
                if nodes.isEmpty { nodes = try await nodesFromPanelConfig() }
                await ensureCoreRunning()
            }
            return true
        } catch {
            issue = TunnelIssue.classify(error)
            LogStore.shared.client("Subscription update failed: \(error.localizedDescription)",
                                   level: .warning)
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
        // One start at a time. The checks and the start wait off the main
        // thread, so two callers — the warm-up at launch and a ping, say —
        // could otherwise both find no core and both start one, and the second
        // start stops the first.
        if let pending = coreStartup { return await pending.value }
        let startup = Task { await startIdleCore() }
        coreStartup = startup
        defer { coreStartup = nil }
        return await startup.value
    }

    private func startIdleCore() async -> Bool {
        guard !coreHandover else { return false }
        let helper = helper, core = core, configURL = configURL, panelURL = panelURL
        let overrides = overrides(mode: .systemProxy)
        // The helper's core counts: in TUN mode it is the one answering. Checked
        // regardless of `activeMode`, because a core left running by a previous
        // session is running whether or not this one knows about it.
        let running = await offMain { (try? helper.status().running) == true || core.isRunning }
        if running { return true }

        do {
            try await offMain {
                let yaml = try MihomoConfig.build(
                    panelYAML: try String(contentsOf: panelURL, encoding: .utf8),
                    overrides: overrides
                )
                try yaml.write(to: configURL, atomically: true, encoding: .utf8)
                try core.validate(configPath: configURL)
                try core.start(configPath: configURL)
            }
        } catch {
            issue = TunnelIssue.classify(error)
            LogStore.shared.client("Core would not start: \(error.localizedDescription)", level: .error)
            return false
        }

        guard await api.waitUntilReady() else {
            issue = .coreFailed
            LogStore.shared.client("Core did not answer after starting", level: .error)
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
            issue = .noSubscription
            return
        }
        state = .connecting
        issue = nil
        LogStore.shared.client("Connecting via \(preferences.tunnelMode == .tun ? "TUN" : "system proxy")")

        do {
            let mode = preferences.tunnelMode
            switch mode {
            case .systemProxy:
                // The core is already up for probing; connecting is only a
                // matter of pointing the machine at it.
                guard await ensureCoreRunning() else {
                    throw MihomoProcess.Failure.exited(0, "core unavailable")
                }
                // Recorded before anything is changed, so a crash between the
                // two still leaves something to restore at the next launch.
                if preferences.proxySnapshot == nil {
                    preferences.proxySnapshot = await offMain { SystemProxy.snapshot() }
                }
                let port = preferences.mixedPort
                await offMain { SystemProxy.enable(port: port) }

            case .tun:
                await refreshHelperStatus()
                if !helperIsCurrent { try await updateHelper() }
                // An idle core still starting would come up after the stop
                // below and hold the ports the privileged one needs.
                if let pending = coreStartup { _ = await pending.value }
                let core = core, helper = helper, panelURL = panelURL
                let overrides = overrides(mode: .tun)
                try await handingOver {
                    // TUN needs the core to run as root, so the idle one has to go.
                    core.stop()
                    let yaml = try MihomoConfig.build(
                        panelYAML: try String(contentsOf: panelURL, encoding: .utf8),
                        overrides: overrides
                    )
                    try helper.version()
                    try helper.start(config: yaml)
                }
                // From here the helper's core is the one to read and to stop.
                // Set only after the checks below, `coreLog` read the idle
                // core's log, so a TUN that failed to come up — another VPN
                // holding the routes — passed for connected; and a failure
                // before then left the privileged core running.
                activeMode = .tun

                // Longer than the default: a panel config with `rule-providers`
                // downloads them before the core binds its controller, and the
                // window where the app still says "connecting" while traffic is
                // already flowing is exactly what that timeout governs.
                LogStore.shared.followCore(api)
                guard await api.waitUntilReady(timeout: 90) else {
                    let log = await readCoreLog()
                    throw MihomoProcess.Failure.exited(0, log)
                }
                // A TUN interface that fails to come up does not stop the core:
                // it keeps running and keeps answering its API, so without this
                // the app reports a healthy tunnel while nothing is routed.
                try await Task.sleep(nanoseconds: 700_000_000)
                let log = await readCoreLog()
                if let reason = MihomoProcess.tunFailure(in: log) {
                    throw TunFailure(routesTaken: MihomoProcess.routesTaken(in: log),
                                     reason: reason)
                }
            }
            activeMode = mode

            try await discoverSelector()
            await applySelection()

            startedAt = Date()
            meter.start()
            beginMonitoring()
            state = .connected
            LogStore.shared.client("Connected — \(selectedNode ?? "auto")")
        } catch {
            // A step below may already have said something more specific —
            // "no usable servers" beats "the core would not start".
            if issue == nil { issue = TunnelIssue.classify(error) }
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

    /// Everything down, for quitting: routing *and* the idle core.
    ///
    /// ``disconnect()`` deliberately leaves the core running, which is right
    /// while the app is open and wrong once it is leaving — a child outlives its
    /// parent, so the core went on holding the controller port (and, while
    /// connected, carrying traffic) until the next launch reaped it.
    public func shutdown() async {
        if state != .disconnected {
            state = .disconnecting
            LogStore.shared.client("Quitting — bringing the tunnel down")
            await teardown()
            state = .disconnected
        }
        // Not waited for: the idle core holds no system state, and it exits on
        // the signal whether or not the app is still here to watch.
        core.stop(waitForExit: false)
        LogStore.shared.stopFollowingCore()
    }

    /// Stops routing. Teardown runs in the reverse order of ``connect()``: proxy
    /// settings go back before the core stops, so no window exists where the
    /// machine points at a listener that is already gone.
    private func teardown() async {
        trafficTask?.cancel()
        trafficTask = nil
        uptimeTimer?.invalidate()
        uptimeTimer = nil
        let mode = activeMode

        // Only what this app changed goes back. With no snapshot this used to
        // switch *every* proxy off on every network service — TUN never sets
        // one, so each TUN disconnect turned off any other client's proxy (or a
        // company one), and cost three `networksetup` runs per service.
        if let snapshot = preferences.proxySnapshot {
            await offMain { SystemProxy.restore(snapshot) }
            preferences.proxySnapshot = nil
        } else if mode == .systemProxy {
            let port = preferences.mixedPort
            await offMain { SystemProxy.disable(pointingAt: port) }
        }

        // Both wait for the core to exit, for up to five seconds.
        let helper = helper, core = core
        coreHandover = true
        switch mode {
        case .tun: await offMain { _ = try? helper.stop() }
        case .systemProxy, .none: await offMain { core.stop() }
        }
        coreHandover = false
        activeMode = nil

        meter.stop()
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
            // Global mode sends everything through mihomo's own GLOBAL group,
            // which knows nothing of this selector unless pointed at it — the
            // user's choice would otherwise be ignored the moment they switch.
            try? await api.select(node: group, in: "GLOBAL")
            if !autoSelect { selectedNode = target }
        } catch {
            LogStore.shared.client("Could not switch server: \(error.localizedDescription)",
                                   level: .warning)
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
    nonisolated private static func protocolLabels(panelYAML yaml: String) -> [String: String] {
        guard let root = try? Yams.load(yaml: yaml) as? [String: Any],
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

    /// The subscription's server descriptions, or the last ones it carried
    /// when this copy came without them.
    private func currentDescriptions(fresh: [String: String]) -> [String: String] {
        guard !fresh.isEmpty else { return preferences.serverDescriptions }
        preferences.serverDescriptions = fresh
        return fresh
    }

    /// What ``discoverSelector()`` needs from the YAML on disk.
    private struct SelectorInputs: Sendable {
        var rules: [String]?
        var labels: [String: String]
        var descriptions: [String: String]
    }

    private func discoverSelector() async throws {
        let groups = try await api.groups()
        let selectors = groups.filter { $0.type == "Selector" }

        // The config's rules are the authority on which group is *the* one; the
        // running core does not expose them, so the generated config is re-read.
        // Everything read from YAML is parsed off the main thread, and the
        // subscription only once.
        let panelURL = panelURL
        let rulesURL = activeMode == .tun ? panelURL : configURL
        let inputs = await offMain { () -> SelectorInputs in
            let panel = (try? String(contentsOf: panelURL, encoding: .utf8)) ?? ""
            let config = rulesURL == panelURL
                ? panel : (try? String(contentsOf: rulesURL, encoding: .utf8)) ?? ""
            return SelectorInputs(
                rules: (try? Yams.load(yaml: config) as? [String: Any])?["rules"] as? [String],
                labels: Self.protocolLabels(panelYAML: panel),
                descriptions: MihomoConfig.serverDescriptions(panelYAML: panel)
            )
        }
        if let rules = inputs.rules {
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
        let labels = inputs.labels
        let membership = Dictionary(groups.map { ($0.name, $0.options) }) { first, _ in first }
        for index in listed.indices {
            if let label = labels[listed[index].name] {
                listed[index].protocolLabel = label
            } else if let members = membership[listed[index].name] {
                listed[index].protocolLabel = members.lazy.compactMap { labels[$0] }.first
            }
        }
        let descriptions = currentDescriptions(fresh: inputs.descriptions)
        for index in listed.indices {
            listed[index].serverDescription = descriptions[listed[index].name]
        }
        nodes = listed
        restoreLatencies()

        // A server chosen under an earlier subscription may be gone from this
        // one. Left pointing at nothing, the picker read "Авто" with no row
        // picked; automatic is what would effectively happen, so it says so.
        if !autoSelect, let chosen = selectedNode, !listed.contains(where: { $0.name == chosen }) {
            autoSelect = true
            preferences.autoSelect = true
        }
    }

    private func reloadRunningCore() async throws {
        // An idle core routes nothing, so it never gets a TUN block — it runs as
        // the user and could not create a `utun` device anyway.
        let mode: TunnelMode = state.isConnected
            ? (activeMode ?? preferences.tunnelMode)
            : .systemProxy
        let panelURL = panelURL, overrides = overrides(mode: mode)
        let yaml = try await offMain {
            try MihomoConfig.build(
                panelYAML: try String(contentsOf: panelURL, encoding: .utf8),
                overrides: overrides
            )
        }
        switch mode {
        case .tun where state.isConnected:
            // The helper owns its config file, so a reload there is a restart of
            // the core it supervises — the tunnel blips, which is the cost of not
            // letting an unprivileged process write a root-read path.
            let helper = helper
            try await offMain { try helper.start(config: yaml) }
            _ = await api.waitUntilReady()
            // A new process: the old one's log and traffic streams ended with
            // it, which froze the speed readout at its last value.
            LogStore.shared.followCore(api)
            startTrafficStream()
        default:
            let core = core, configURL = configURL
            try await offMain {
                try yaml.write(to: configURL, atomically: true, encoding: .utf8)
                try core.validate(configPath: configURL)
            }
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

        let names = nodes.map(\.name)
        let measured = await api.delays(nodes: names) { name, delay in
            await Self.record(name: name, delay: delay, on: self)
        }
        // Timeouts are remembered too, as -1, so a node that was down still
        // reads `n/a` after a relaunch rather than looking never checked.
        var saved = measured
        for name in names where measured[name] == nil { saved[name] = -1 }
        preferences.latencies = saved
        if autoSelect { await applySelection() }
    }

    /// Measures one server, for the row's own ping button.
    public func ping(node name: String) async {
        guard !pendingProbes.contains(name), await ensureCoreRunning() else { return }
        pendingProbes.insert(name)
        let delay = await api.delay(node: name)
        await Self.record(name: name, delay: delay, on: self)
        var saved = preferences.latencies
        saved[name] = delay ?? -1
        preferences.latencies = saved
    }

    /// Applies one node's result as it lands, on the main actor.
    private static func record(name: String, delay: Int?, on controller: TunnelController) async {
        controller.pendingProbes.remove(name)
        guard let index = controller.nodes.firstIndex(where: { $0.name == name }) else { return }
        controller.nodes[index].latency = delay
        controller.nodes[index].unreachable = delay == nil
    }

    /// Puts the last measured numbers back after the node list is rebuilt, so a
    /// screen change or a reconnect does not blank the server list.
    private func restoreLatencies() {
        let saved = preferences.latencies
        guard !saved.isEmpty else { return }
        for index in nodes.indices
        where nodes[index].latency == nil && !nodes[index].unreachable {
            guard let value = saved[nodes[index].name] else { continue }
            if value > 0 { nodes[index].latency = value } else { nodes[index].unreachable = true }
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
            LogStore.shared.client("Could not close connections: \(error.localizedDescription)",
                                   level: .warning)
        }
    }

    // MARK: - Settings that change the config

    /// Switches the running core at once; the next config it is built with
    /// carries the choice too.
    public func setRoutingMode(_ mode: RoutingMode) async {
        guard mode != routingMode else { return }
        routingMode = mode
        preferences.routingMode = mode
        guard state.isConnected || core.isRunning else { return }
        do {
            try await api.patchConfig(["mode": mode.rawValue])
            LogStore.shared.client("Routing mode: \(mode.rawValue)")
            // Connections already open keep the route they started on. Closed,
            // programs reopen them, and the new mode takes them.
            if state.isConnected { await closeAllConnections() }
        } catch {
            LogStore.shared.client("Could not switch routing mode: \(error.localizedDescription)",
                                   level: .warning)
        }
    }

    public func setTunnelMode(_ mode: TunnelMode) async {
        guard mode != preferences.tunnelMode else { return }
        preferences.tunnelMode = mode
        tunnelMode = mode
        // A mode change swaps which process owns the core, so it cannot be a
        // live patch — it is a reconnect, and only if one was up.
        if state.isConnected {
            await disconnect()
            await connect()
        }
    }

    // MARK: - The user's own rules

    /// The rules as last applied.
    public var routingRules: [RoutingRule] { preferences.routingRules }

    /// Checks `rules` against the core, then keeps them and applies them.
    ///
    /// Checked first because a rule the core refuses does not fail on its own:
    /// the whole config is refused, and a connected tunnel would stop carrying
    /// anything. The check is the core's own `-t`, on the config these rules
    /// would produce, so what passes here is what will load.
    public func applyRoutingRules(_ rules: [RoutingRule]) async -> Bool {
        var proposed = overrides(mode: state.isConnected ? (activeMode ?? tunnelMode) : .systemProxy)
        proposed.routingRules = rules
        let overrides = proposed, core = core, panelURL = panelURL
        let probe = configURL.deletingLastPathComponent().appendingPathComponent("rules-check.yaml")
        do {
            try await offMain {
                defer { try? FileManager.default.removeItem(at: probe) }
                let yaml = try MihomoConfig.build(
                    panelYAML: try String(contentsOf: panelURL, encoding: .utf8),
                    overrides: overrides
                )
                try yaml.write(to: probe, atomically: true, encoding: .utf8)
                try core.validate(configPath: probe)
            }
        } catch {
            LogStore.shared.client("Rules not applied: \(error.localizedDescription)", level: .error)
            return false
        }
        preferences.routingRules = rules
        LogStore.shared.client("Applied \(rules.filter(\.enabled).count) rule(s) of the user's own")
        await reapplyRouting()
        return true
    }

    /// Reads the subscription's groups and rules for the rules screen.
    private func refreshRoutingInputs() async {
        let panelURL = panelURL
        let inputs = await offMain { () -> RoutingInputs in
            let yaml = (try? String(contentsOf: panelURL, encoding: .utf8)) ?? ""
            let parsed = MihomoConfig.routingInputs(panelYAML: yaml)
            return RoutingInputs(groups: parsed.groups, rules: parsed.rules)
        }
        ruleTargets = inputs.groups
        profileRules = inputs.rules
    }

    private struct RoutingInputs: Sendable {
        var groups: [String]
        var rules: [String]
    }

    /// Carries over what was set on the apps screen of earlier versions — the
    /// app switches, the rules beside them and the split mode — into the
    /// user's own rules, once, then forgets it. See ``LegacySplitRule``.
    private func retireSplitTunnelling() {
        guard let legacy = preferences.legacySplit else { return }
        defer { preferences.forgetLegacySplit() }
        guard !legacy.rules.isEmpty else { return }

        var group = MihomoConfig.defaultSelector
        if legacy.mode == "only" {
            let root = (try? loadPanelRoot()) ?? [:]
            group = MihomoConfig.primarySelectorName(
                groups: root["proxy-groups"] as? [[String: Any]] ?? [],
                rules: root["rules"] as? [String] ?? []
            )
        }
        let existing = preferences.routingRules
        let moved = RoutingRule.carriedOver(from: legacy.rules, mode: legacy.mode, group: group)
            .filter { new in !existing.contains { $0.kind == new.kind && $0.value == new.value } }
        preferences.routingRules = existing + moved
        LogStore.shared.client("Moved \(moved.count) rule(s) from the apps screen to the rules page")
    }

    private func loadPanelRoot() throws -> [String: Any] {
        let yaml = try String(contentsOf: panelURL, encoding: .utf8)
        return try Yams.load(yaml: yaml) as? [String: Any] ?? [:]
    }

    private func reapplyRouting() async {
        guard state.isConnected else { return }
        do {
            try await reloadRunningCore()
        } catch {
            issue = TunnelIssue.classify(error)
            LogStore.shared.client("Could not apply routing: \(error.localizedDescription)",
                                   level: .error)
        }
    }

    // MARK: - Monitoring

    private func beginMonitoring() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.meter.uptime = Int(Date().timeIntervalSince(startedAt))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        uptimeTimer = timer

        startTrafficStream()
    }

    private func startTrafficStream() {
        trafficTask?.cancel()
        trafficTask = Task { [api] in
            // mihomo's /traffic emits per-second deltas, so the session totals
            // are accumulated here rather than read back from /connections —
            // which resets whenever a connection closes.
            for await sample in api.trafficStream() {
                if Task.isCancelled { break }
                await MainActor.run {
                    self.meter.record(up: sample.up, down: sample.down)
                }
            }
        }
    }

    private func handleCoreExit(_ status: Int32) {
        guard state.isConnected || state == .connecting else { return }
        let detail = core.recentLog.split(whereSeparator: \.isNewline).suffix(3).joined(separator: "\n")
        issue = .coreStopped
        LogStore.shared.client("Core stopped unexpectedly (status \(status))"
                               + (detail.isEmpty ? "" : "\n\(detail)"), level: .error)
        Task { await teardown(); state = .failed("Core stopped") }
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

    /// Tells the log what never to show: the subscription link, its host and
    /// its token, and every server address the subscription names. Core errors
    /// quote server addresses (`dial tcp …`), and the log is on screen.
    private func updateRedactions() async {
        let link = preferences.subscriptionURL, panelURL = panelURL
        let secrets = await offMain { () -> [String] in
            var secrets: [String] = []
            if let link, let url = SubscriptionClient.normalize(link) {
                secrets.append(link)
                secrets.append(url.absoluteString)
                if let host = url.host { secrets.append(host) }
                secrets += url.pathComponents.filter { $0.count >= 8 }
            }
            if let yaml = try? String(contentsOf: panelURL, encoding: .utf8),
               let root = try? Yams.load(yaml: yaml) as? [String: Any],
               let proxies = root["proxies"] as? [[String: Any]] {
                secrets += proxies.compactMap { $0["server"] as? String }
            }
            return secrets
        }
        LogStore.shared.setRedactions(secrets)
    }

    private func overrides(mode: TunnelMode) -> MihomoConfig.Overrides {
        MihomoConfig.Overrides(
            controllerPort: preferences.controllerPort,
            secret: preferences.coreSecret,
            mixedPort: preferences.mixedPort,
            mode: mode,
            routingMode: preferences.routingMode,
            routingRules: preferences.routingRules,
            dataDirectory: support.appendingPathComponent("core").path
        )
    }

    private func nodesFromPanelConfig() async throws -> [Node] {
        let panelURL = panelURL
        return try await offMain {
            let yaml = try String(contentsOf: panelURL, encoding: .utf8)
            guard let root = try Yams.load(yaml: yaml) as? [String: Any],
                  let proxies = root["proxies"] as? [[String: Any]] else { return [] }
            return proxies.compactMap { proxy in
                guard let name = proxy["name"] as? String else { return nil }
                return Node(name: name,
                            type: proxy["type"] as? String ?? "unknown",
                            server: proxy["server"] as? String)
            }
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

    /// The folder of bundled geo databases — see ``Geodata``. Falls back to
    /// the repository layout, like the core.
    var geodataURL: URL {
        if let resource = url(forResource: "geodata", withExtension: nil) {
            return resource
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/geodata")
    }

    var helperBinaryURL: URL {
        url(forResource: "moonlight-helper", withExtension: nil)
            ?? bundleURL.appendingPathComponent("Contents/Resources/moonlight-helper")
    }
}
