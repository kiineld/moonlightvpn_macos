import SwiftUI
import AppKit
import MoonlightDesign
import MoonlightCore

/// Live connections, grouped by the process that opened them.
///
/// Grouped rather than flat because the flat list is unreadable at any real
/// traffic level — a browser alone opens dozens — and because the question
/// people bring here is about a *program*: is this app going through the tunnel
/// or not. Expanding a row shows the hosts behind it.
struct ConnectionsScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @State private var connections: [MihomoAPI.Connection] = []
    /// Whether the first answer has arrived.
    @State private var loaded = false
    /// The order processes first appeared in. Sorting by live traffic
    /// reshuffled the rows every second, so nothing stayed under the pointer.
    @State private var order: [String] = []
    @State private var query = ""
    @State private var expanded: String?
    @State private var poll: Task<Void, Never>?

    private var groups: [ConnectionGroup] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = text.isEmpty ? connections : connections.filter {
            $0.process.lowercased().contains(text) || $0.host.lowercased().contains(text)
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        return Dictionary(grouping: matching, by: \.process)
            .map { ConnectionGroup(process: $0.key, path: $0.value.first?.processPath ?? "", items: $0.value) }
            .sorted { (rank[$0.process] ?? .max, $1.download) < (rank[$1.process] ?? .max, $0.download) }
    }

    /// The table, or the empty state. Until the first answer the tunnel's
    /// state decides — connected, there is traffic to show — so the page
    /// arrives whole with everything else. It used to draw nothing until the
    /// core answered and then fade the table in on its own, a beat after the
    /// page had already arrived: two entrances, one of them late.
    private var showsTable: Bool {
        loaded ? !groups.isEmpty : tunnel.state.isConnected
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            ZStack {
                if showsTable {
                    table.transition(.opacity)
                } else {
                    empty
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }
            }
            .animation(Motion.standard, value: showsTable)
        }
        .onAppear(perform: start)
        .onDisappear { poll?.cancel() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Text("\(L.t(.activeConnections, locale)): \(connections.count)")
                .font(.ml(12.5, .heavy))
                .foregroundStyle(palette.accentInk)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .mlGlass(.capsule, tint: palette.accent.opacity(0.25), fallback: palette.accentQuiet)

            HStack(spacing: 8) {
                IconView(.search, size: 14).foregroundStyle(palette.textMuted)
                TextField(L.t(.searchApps, locale), text: $query)
                    .textFieldStyle(.plain)
                    .font(.ml(12.5))
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .mlGlass(.capsule, fallback: palette.surface2)

            Button {
                Task { await tunnel.closeAllConnections() }
            } label: {
                HStack(spacing: 7) {
                    IconView(.x, size: 13, strokeWidth: 2.4)
                    Text(L.t(.closeAll, locale)).font(.ml(12.5, .heavy))
                }
                .foregroundStyle(palette.danger)
                .padding(.horizontal, 13)
                .frame(height: 30)
                .mlGlass(.capsule, tint: palette.danger.opacity(0.25), fallback: palette.dangerQuiet)
            }
            .pressButton()
            .disabled(connections.isEmpty)
            .opacity(connections.isEmpty ? 0.5 : 1)
        }
    }

    private var empty: some View {
        Panel(radius: Radii.card, padding: 40) {
            VStack(spacing: 10) {
                IconView(.globe, size: 30).foregroundStyle(palette.textMuted)
                Text(L.t(tunnel.state.isConnected ? .noConnections : .connectionsNeedTunnel, locale))
                    .font(.ml(TypeScale.meta))
                    .foregroundStyle(palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var table: some View {
        Panel(radius: Radii.card, padding: 0) {
            VStack(spacing: 0) {
                header
                palette.hairlineSoft.frame(height: 1)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            ProcessRow(
                                group: group,
                                expanded: expanded == group.process,
                                locale: locale,
                                toggle: {
                                    withAnimation(Motion.standard) {
                                        expanded = expanded == group.process ? nil : group.process
                                    }
                                },
                                close: {
                                    let ids = group.items.map(\.id)
                                    Task { await tunnel.close(connections: ids) }
                                }
                            )
                            if expanded == group.process {
                                ForEach(group.items.sorted { $0.download > $1.download }) { item in
                                    HostRow(connection: item, locale: locale) {
                                        Task { await tunnel.close(connections: [item.id]) }
                                    }
                                }
                            }
                            palette.hairlineSoft.frame(height: 1)
                        }
                    }
                }
                .mlScrollIndicators(hidden: false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // The process takes whatever is left; every other column is fixed.
            // Time used to be the flexible one, and on a narrow window it was
            // left some thirty points — "TIME" broke over two lines.
            ColumnHeading(text: L.t(.colProcess, locale))
            ColumnHeading(text: L.t(.colChain, locale), width: Columns.chain)
            ColumnHeading(text: L.t(.colRule, locale), width: Columns.rule)
            ColumnHeading(text: L.t(.colNetwork, locale), width: Columns.network)
            ColumnHeading(text: L.t(.colDown, locale), width: Columns.bytes, alignment: .trailing)
            ColumnHeading(text: L.t(.colUp, locale), width: Columns.bytes, alignment: .trailing)
            ColumnHeading(text: L.t(.colTime, locale), width: Columns.time, alignment: .trailing)
            // Height pinned: a Color constrained only in width is greedy
            // vertically, which stretched the header row to fill the panel.
            Color.clear.frame(width: 26, height: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// One second, matching the core's own traffic tick — anything faster only
    /// makes the numbers flicker.
    private func start() {
        poll?.cancel()
        poll = Task {
            while !Task.isCancelled {
                let latest = await tunnel.currentConnections()
                guard !Task.isCancelled else { break }
                // New processes join at the end, heaviest first among
                // themselves; ones already listed keep their place.
                let known = Set(order)
                let newcomers = Dictionary(grouping: latest, by: \.process)
                    .filter { !known.contains($0.key) }
                    .sorted { $0.value.reduce(0) { $0 + $1.download } > $1.value.reduce(0) { $0 + $1.download } }
                    .map(\.key)
                withAnimation(loaded ? Motion.standard : nil) {
                    order += newcomers
                    connections = latest
                    loaded = true
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

/// The table's fixed column widths, shared by the header and both kinds of
/// row so they cannot drift apart — the rule heading was 74 points over a
/// 66-point column.
private enum Columns {
    static let process: CGFloat = 120
    static let chain: CGFloat = 128
    static let rule: CGFloat = 66
    static let network: CGFloat = 66
    static let bytes: CGFloat = 72
    static let time: CGFloat = 58
}

/// One process and everything it has open.
struct ConnectionGroup: Identifiable {
    var id: String { process }
    var process: String
    var path: String
    var items: [MihomoAPI.Connection]

    var download: Int64 { items.reduce(0) { $0 + $1.download } }
    var upload: Int64 { items.reduce(0) { $0 + $1.upload } }
    var newest: Date { items.map(\.start).max() ?? Date() }
    var rule: String { items.first?.rule ?? "" }
    var networks: [String] { Array(Set(items.map(\.network))).sorted() }

    /// The node carrying most of this process's connections — a browser can
    /// have a few on different chains, and the majority is the useful answer.
    var chain: String {
        Dictionary(grouping: items, by: \.node)
            .max { $0.value.count < $1.value.count }?.key ?? ""
    }
}

private struct ProcessRow: View {
    @Environment(\.palette) private var palette
    let group: ConnectionGroup
    let expanded: Bool
    let locale: AppLocale
    let toggle: () -> Void
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
        Button(action: toggle) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(group.items.count)")
                        .font(.mlMono(10.5, .semibold))
                        .foregroundStyle(palette.text2)
                        .frame(minWidth: 18)
                        .padding(.vertical, 2)
                        .mlGlass(.rounded(5), fallback: palette.surface2)
                    ProcessIcon(path: group.path)
                    Text(group.process)
                        .font(.ml(12.5, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    IconView(.chevronRight, size: 12, strokeWidth: 2.4)
                        .foregroundStyle(palette.textMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(minWidth: Columns.process, maxWidth: .infinity, alignment: .leading)

                NodeChip(name: group.chain).frame(width: Columns.chain, alignment: .leading)
                Text(group.rule)
                    .font(.ml(11.5)).foregroundStyle(palette.textMuted)
                    .lineLimit(1).frame(width: Columns.rule, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(group.networks, id: \.self) { NetworkChip(network: $0) }
                }
                .frame(width: Columns.network, alignment: .leading)
                Text(Format.bytes(group.download, locale: locale))
                    .font(.mlMono(11.5, .semibold)).foregroundStyle(palette.stUpInk)
                    .frame(width: Columns.bytes, alignment: .trailing)
                Text(Format.bytes(group.upload, locale: locale))
                    .font(.mlMono(11.5, .semibold)).foregroundStyle(palette.text2)
                    .frame(width: Columns.bytes, alignment: .trailing)
                Text(Format.age(group.newest, locale: locale))
                    .font(.mlMono(11.5)).foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                    .frame(width: Columns.time, alignment: .trailing)
            }
            .padding(.leading, 16)
            // The gap the header and the host rows leave before the close
            // button, so the last column lines up down the whole table.
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .pressCard()

        CloseButton(hint: L.t(.closeProcess, locale), action: close)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.trailing, 16)
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
    }
}

/// Closes what a row stands for — one process's connections, or one connection.
private struct CloseButton: View {
    @Environment(\.palette) private var palette
    let hint: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(.x, size: 12, strokeWidth: 2.4)
                .foregroundStyle(hovering ? palette.danger : palette.textMuted)
                .frame(width: 22, height: 22)
                .background(hovering ? palette.dangerQuiet : .clear)
                .clipShape(Circle())
        }
        .pressIcon()
        .frame(width: 26)
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
        .help(hint)
    }
}

private struct HostRow: View {
    @Environment(\.palette) private var palette
    let connection: MihomoAPI.Connection
    let locale: AppLocale
    let close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(connection.host)
                .font(.mlMono(11.5, .regular))
                .foregroundStyle(palette.text2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: Columns.process - 20, maxWidth: .infinity, alignment: .leading)
            NodeChip(name: connection.node)
                .frame(width: Columns.chain, alignment: .leading)
            Text(connection.rule)
                .font(.ml(11.5))
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
                .frame(width: Columns.rule, alignment: .leading)
            NetworkChip(network: connection.network)
                .frame(width: Columns.network, alignment: .leading)
            Text(Format.bytes(connection.download, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.stUpInk)
                .frame(width: Columns.bytes, alignment: .trailing)
            Text(Format.bytes(connection.upload, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.text2)
                .frame(width: Columns.bytes, alignment: .trailing)
            Text(Format.age(connection.start, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.textMuted)
                .lineLimit(1)
                .frame(width: Columns.time, alignment: .trailing)
            CloseButton(hint: L.t(.closeConnection, locale), action: close)
                .opacity(hovering ? 1 : 0.35)
        }
        .padding(.leading, 36)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .background(palette.surface2.opacity(0.5))
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
    }
}

/// A process's own icon, or a neutral glyph when it has none — a daemon like
/// `netsimd` is not an app and has no bundle to take one from.
private struct ProcessIcon: View {
    @Environment(\.palette) private var palette
    let path: String

    var body: some View {
        if let bundle = AppInventory.bundlePath(forExecutable: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundle))
                .resizable()
                .interpolation(.high)
                .frame(width: 17, height: 17)
        } else {
            IconView(.settings, size: 13)
                .foregroundStyle(palette.textMuted)
                .frame(width: 17, height: 17)
        }
    }
}

/// The node a connection went through, with the flag its name carries.
struct NodeChip: View {
    @Environment(\.palette) private var palette
    let name: String

    var body: some View {
        let node = Node(name: name, type: "")
        HStack(spacing: 5) {
            if let flag = node.flag { Text(flag).font(.system(size: 12)) }
            Text(node.title.isEmpty ? "DIRECT" : node.title)
                .font(.ml(11.5, .bold))
                .foregroundStyle(name.isEmpty || name == "DIRECT"
                                 ? palette.text2 : palette.accentInk)
                .lineLimit(1)
        }
    }
}

struct NetworkChip: View {
    @Environment(\.palette) private var palette
    let network: String

    var body: some View {
        Text(network)
            .font(.mlMono(10, .semibold))
            .foregroundStyle(network == "UDP" ? palette.stDegradedInk : palette.stUpInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((network == "UDP" ? palette.stDegradedInk : palette.stUpInk).opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
