import SwiftUI
import MoonlightDesign
import MoonlightCore

/// Split tunnelling by app.
///
/// The app switches are `PROCESS-NAME` rules the split mode composes with the
/// subscription's routing. Rules for anything else — a domain, an address, a
/// port, a process the scanner never found — live on the rules page, where
/// they can point anywhere rather than only around the tunnel or through it.
///
/// The TUN constraint is **per rule**, not per screen: `PROCESS-*` rules need
/// the core to identify the process behind a connection, which only TUN can do,
/// while domain and address rules work under a system proxy too.
struct AppsScreen: View {
    /// Both column headings share this, so the one carrying the search field
    /// does not sit lower than the one that is only a label.
    static let headingHeight: CGFloat = 34

    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @State private var apps: [AppEntry] = []
    @State private var running: Set<String> = []
    @State private var rules: [SplitRule] = []
    @State private var mode: SplitMode = .all
    @State private var query = ""

    /// True when a rule is present that cannot work in the current mode.
    private var hasInertProcessRules: Bool {
        tunnel.tunnelMode != .tun && rules.contains { $0.enabled && $0.kind.needsProcessMatching }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if hasInertProcessRules { tunBanner }
            HStack(alignment: .top, spacing: 16) {
                appList
                    .opacity(mode == .all ? 0.45 : 1)
                    .animation(Motion.paint, value: mode)
                rulesLink
                    .frame(width: 300)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            SegmentedPill(
                selection: $mode,
                options: [
                    (.all, L.t(.splitAll, locale)),
                    (.only, L.t(.splitOnly, locale)),
                    (.except, L.t(.splitExcept, locale)),
                ]
            ) { value in
                Task { await tunnel.setSplitMode(value) }
            }
            .frame(width: 330)

            Text(hint)
                .font(.ml(12.5))
                .lineSpacing(2)
                .foregroundStyle(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hint: String {
        switch mode {
        case .all: return L.t(.splitHintAll, locale)
        case .only: return L.t(.splitHintOnly, locale)
        case .except: return L.t(.splitHintExcept, locale)
        }
    }

    private var tunBanner: some View {
        HStack(spacing: 12) {
            IconView(.circleAlert, size: 18).foregroundStyle(palette.warning)
            Text(L.t(.splitNeedsTun, locale))
                .font(.ml(TypeScale.meta))
                .foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await tunnel.setTunnelMode(.tun) }
            } label: {
                Text(L.t(.splitNeedsTunAction, locale))
                    .font(.ml(12.5, .heavy))
                    .foregroundStyle(palette.textOnAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .mlGlass(.capsule, tint: palette.accent, fallback: palette.accent)
            }
            .pressButton()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .mlGlass(.rounded(Radii.card), tint: palette.accent.opacity(0.25), fallback: palette.accentQuiet)
    }

    // MARK: - Apps

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Overline(text: L.t(.installedApps, locale))
                Spacer()
                searchField
            }
            .frame(height: Self.headingHeight)
            .padding(.horizontal, 2)

            RowGroup {
                if filteredApps.isEmpty {
                    Text(L.t(.noApps, locale))
                        .font(.ml(TypeScale.meta))
                        .foregroundStyle(palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                                if index > 0 { RowDivider(leading: 74) }
                                AppRow(
                                    app: app,
                                    running: running.contains(app.executable),
                                    isOn: binding(for: app),
                                    enabled: mode != .all
                                )
                            }
                        }
                    }
                    .mlScrollIndicators(hidden: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(.search, size: 15).foregroundStyle(palette.textMuted)
            TextField(L.t(.searchApps, locale), text: $query)
                .textFieldStyle(.plain)
                .font(.ml(13))
                .foregroundStyle(palette.text)
                .frame(width: 120)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .mlGlass(.capsule, fallback: palette.surface2)
    }

    /// An app's toggle is a view onto the rule list: switching it on appends a
    /// `PROCESS-NAME` rule tagged with the executable, switching it off removes
    /// that rule and leaves a hand-written one for the same process alone.
    private func binding(for app: AppEntry) -> Binding<Bool> {
        Binding(
            get: { rules.contains { $0.appExecutable == app.executable } },
            set: { on in
                if on {
                    guard !rules.contains(where: { $0.appExecutable == app.executable }) else { return }
                    rules.append(SplitRule(
                        kind: .processName, value: app.executable, appExecutable: app.executable
                    ))
                } else {
                    rules.removeAll { $0.appExecutable == app.executable }
                }
                save()
            }
        )
    }

    /// Running apps first: someone opening this screen is usually thinking about
    /// something on screen right now.
    private var filteredApps: [AppEntry] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched = text.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(text) || $0.executable.lowercased().contains(text)
        }
        return matched.sorted { first, second in
            let firstRunning = running.contains(first.executable)
            let secondRunning = running.contains(second.executable)
            if firstRunning != secondRunning { return firstRunning }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private func load() {
        mode = tunnel.splitMode
        rules = tunnel.splitRules
        running = AppInventory.running()
        // Scanning /Applications opens every bundle's Info.plist, which is far
        // too slow for a view body.
        Task.detached(priority: .userInitiated) {
            let found = AppInventory.installed()
            await MainActor.run { apps = found }
        }
    }

    private func save() {
        Task { await tunnel.setSplitRules(rules) }
    }

    /// The way to the rules page, where sites, addresses and ports are routed.
    private var rulesLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Overline(text: L.t(.rules, locale))
                Spacer(minLength: 0)
            }
            .frame(height: Self.headingHeight)
            .padding(.horizontal, 2)

            RowGroup {
                ActionRow(
                    icon: .route,
                    fill: palette.cat1,
                    title: L.t(.appsRulesLink, locale),
                    subtitle: L.t(.appsRulesLinkSub, locale)
                ) {
                    page = .rules
                }
            }

            Text(L.t(.rulesHelp, locale))
                .font(.ml(11.5))
                .lineSpacing(2)
                .foregroundStyle(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - App row

private struct AppRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let app: AppEntry
    let running: Bool
    @Binding var isOn: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.ml(14, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if running {
                        Text(L.t(.runningNow, locale))
                            .font(.ml(9.5, .heavy))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .mlGlass(.capsule, fallback: palette.accentQuiet)
                    }
                }
                Text(app.executable)
                    .font(.mlMono(11.5, .regular))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MLToggle(isOn: $isOn, enabled: enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}
