import SwiftUI
import MoonlightDesign
import MoonlightCore

/// Split tunnelling.
///
/// Two ways in to the same list. The app toggles are a convenience over
/// `PROCESS-NAME`; the rules panel is the general form, so a rule can also match
/// a process the scanner never found, a domain, a regex, a CIDR or a port. Both
/// write into one `[SplitRule]`, because that is what they are to the core.
///
/// The TUN constraint is **per rule**, not per screen: `PROCESS-*` rules need
/// the core to identify the process behind a connection, which only TUN can do,
/// while domain and address rules work under a system proxy too.
struct AppsScreen: View {
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
                RulesPanel(rules: $rules, onChange: save)
                    .frame(width: 400)
            }
            .opacity(mode == .all ? 0.45 : 1)
            .animation(Motion.paint, value: mode)
        }
        .rise(0, page)
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
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .pressButton()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(palette.accentQuiet)
        .clipShape(RoundedRectangle(cornerRadius: Radii.card, style: .continuous))
    }

    // MARK: - Apps

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Overline(text: L.t(.installedApps, locale))
                Spacer()
                searchField
            }
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
                    .scrollIndicators(.never)
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
        .background(palette.surface2)
        .clipShape(Capsule())
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
}

// MARK: - Rules

private struct RulesPanel: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var rules: [SplitRule]
    let onChange: () -> Void

    @State private var kind: SplitRule.Kind = .domainSuffix
    @State private var value = ""
    @State private var error: String?

    /// Rules the app list owns are shown there, not here — they would be a
    /// second, desynchronised copy of the same switch.
    private var custom: [SplitRule] { rules.filter { !$0.isFromAppList } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline(text: L.t(.rules, locale)).padding(.horizontal, 2)

            RowGroup {
                editor
                if !custom.isEmpty {
                    RowDivider(leading: 0)
                    ForEach(Array(custom.enumerated()), id: \.element.id) { index, rule in
                        if index > 0 { RowDivider(leading: 18) }
                        RuleRow(
                            rule: rule,
                            isOn: Binding(
                                get: { rule.enabled },
                                set: { on in
                                    guard let at = rules.firstIndex(where: { $0.id == rule.id })
                                    else { return }
                                    rules[at].enabled = on
                                    onChange()
                                }
                            ),
                            remove: {
                                rules.removeAll { $0.id == rule.id }
                                onChange()
                            }
                        )
                    }
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(SplitRule.Kind.allCases, id: \.self) { option in
                        Button {
                            kind = option
                            error = nil
                        } label: {
                            Text(option.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(kind.rawValue)
                            .font(.mlMono(11.5, .medium))
                            .lineLimit(1)
                        IconView(.chevronRight, size: 12, strokeWidth: 2.4)
                            .rotationEffect(.degrees(90))
                    }
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(palette.surface2)
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerCursor()

                if kind.needsProcessMatching {
                    Text("TUN")
                        .font(.ml(10, .heavy))
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(palette.accentQuiet)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                TextField(kind.placeholder, text: $value)
                    .textFieldStyle(.plain)
                    .font(.mlMono(12))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: Radii.field, style: .continuous))
                    .onSubmit(add)

                Button(action: add) {
                    IconView(.plus, size: 16, strokeWidth: 2.4)
                        .foregroundStyle(palette.textOnAccent)
                        .frame(width: 36, height: 36)
                        .background(palette.accent)
                        .clipShape(Circle())
                }
                .pressIcon()
                .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let error {
                Text(error)
                    .font(.ml(11.5))
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    /// Validated before it can be added: a bad rule does not fail on its own —
    /// mihomo refuses the whole config, so the tunnel stops rather than the rule
    /// being skipped.
    private func add() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let invalid = SplitRule.validate(kind: kind, value: trimmed) {
            error = invalid.errorDescription
            return
        }
        guard !rules.contains(where: { $0.kind == kind && $0.value == trimmed }) else {
            value = ""
            error = nil
            return
        }
        rules.append(SplitRule(kind: kind, value: trimmed))
        value = ""
        error = nil
        onChange()
    }
}

private struct RuleRow: View {
    @Environment(\.palette) private var palette
    let rule: SplitRule
    @Binding var isOn: Bool
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.kind.rawValue)
                    .font(.ml(10.5, .heavy))
                    .foregroundStyle(palette.textMuted)
                Text(rule.value)
                    .font(.mlMono(12.5))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: remove) {
                IconView(.trash2, size: 15)
                    .foregroundStyle(hovering ? palette.danger : palette.textMuted)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            MLToggle(isOn: $isOn)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(hovering ? palette.surface2.opacity(0.6) : .clear)
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
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
                            .background(palette.accentQuiet)
                            .clipShape(Capsule())
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
