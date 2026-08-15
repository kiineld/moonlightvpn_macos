import SwiftUI
import MoonlightDesign
import MoonlightCore

/// Split tunnelling.
///
/// The screen is honest about its one hard constraint: `PROCESS-NAME` rules
/// need mihomo to see which process opened a connection, and it only does in
/// TUN mode. Under a system proxy the core is handed a socket with no process
/// behind it, so the rules would be written and silently never match. Rather
/// than let that happen, the list is dimmed and the banner offers the switch.
struct AppsScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @State private var apps: [AppEntry] = []
    @State private var running: Set<String> = []
    @State private var selection: Set<String> = []
    @State private var mode: SplitMode = .all
    @State private var query = ""

    private var needsTun: Bool { tunnel.tunnelMode != .tun }

    var body: some View {
        VStack(spacing: 16) {
            header
            if needsTun { tunBanner }
            columns
                .opacity(mode == .all ? 0.4 : 1)
                .animation(Motion.paint, value: mode)
        }
        .onAppear(perform: load)
    }

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
            .frame(width: 360)

            Text(hint)
                .font(.ml(13))
                .lineSpacing(3)
                .foregroundStyle(palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            searchField
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(.search, size: 15).foregroundStyle(palette.textMuted)
            TextField(L.t(.searchApps, locale), text: $query)
                .textFieldStyle(.plain)
                .font(.ml(13))
                .foregroundStyle(palette.text)
                .frame(width: 130)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(palette.surface2)
        .clipShape(Capsule())
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
                page = .settings
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
        .padding(.vertical, 14)
        .background(palette.accentQuiet)
        .clipShape(RoundedRectangle(cornerRadius: Radii.card, style: .continuous))
    }

    private var columns: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(split().enumerated()), id: \.offset) { _, column in
                        RowGroup {
                            ForEach(Array(column.enumerated()), id: \.element.id) { index, app in
                                if index > 0 { RowDivider(leading: 74) }
                                AppRow(
                                    app: app,
                                    running: running.contains(app.executable),
                                    isOn: Binding(
                                        get: { selection.contains(app.executable) },
                                        set: { on in
                                            if on { selection.insert(app.executable) }
                                            else { selection.remove(app.executable) }
                                            Task { await tunnel.setSplitApps(selection) }
                                        }
                                    ),
                                    enabled: mode != .all
                                )
                            }
                        }
                        .frame(width: (geometry.size.width - 16) / 2)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// Two balanced columns, as the design lays them out.
    private func split() -> [[AppEntry]] {
        let filtered = filteredApps
        let half = Int(ceil(Double(filtered.count) / 2))
        guard half > 0 else { return [[], []] }
        return [Array(filtered.prefix(half)), Array(filtered.dropFirst(half))]
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
        selection = tunnel.splitApps
        running = AppInventory.running()
        // Scanning /Applications touches every bundle's Info.plist, which is too
        // slow for a view body.
        Task.detached(priority: .userInitiated) {
            let found = AppInventory.installed()
            await MainActor.run { apps = found }
        }
    }
}

private struct AppRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let app: AppEntry
    let running: Bool
    @Binding var isOn: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppIcon(path: app.path, letter: String(app.name.prefix(1)).uppercased())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.ml(14.5, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    if running {
                        Text(L.t(.runningNow, locale))
                            .font(.ml(10, .heavy))
                            .foregroundStyle(palette.accentInk)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.accentQuiet)
                            .clipShape(Capsule())
                    }
                }
                Text(app.executable)
                    .font(.mlMono(12, .regular))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MLToggle(isOn: $isOn, enabled: enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

/// The real app icon, falling back to the design's lettered tile when a bundle
/// has none.
private struct AppIcon: View {
    @Environment(\.palette) private var palette
    let path: String
    let letter: String

    var body: some View {
        let image = NSWorkspace.shared.icon(forFile: path)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: 42, height: 42)
    }
}
