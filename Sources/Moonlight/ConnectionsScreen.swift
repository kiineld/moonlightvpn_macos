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
    @State private var query = ""
    @State private var expanded: String?
    @State private var poll: Task<Void, Never>?

    private var groups: [ConnectionGroup] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = text.isEmpty ? connections : connections.filter {
            $0.process.lowercased().contains(text) || $0.host.lowercased().contains(text)
        }
        return Dictionary(grouping: matching, by: \.process)
            .map { ConnectionGroup(process: $0.key, path: $0.value.first?.processPath ?? "", items: $0.value) }
            .sorted { $0.download > $1.download }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            if groups.isEmpty { empty } else { table }
        }
        .rise(0, page)
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
                .background(palette.accentQuiet)
                .clipShape(Capsule())

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
            .background(palette.surface2)
            .clipShape(Capsule())

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
                .background(palette.dangerQuiet)
                .clipShape(Capsule())
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
                                    withAnimation(Motion.paint) {
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
            ColumnHeading(text: L.t(.colProcess, locale), width: 176)
            ColumnHeading(text: L.t(.colChain, locale), width: 128)
            ColumnHeading(text: L.t(.colRule, locale), width: 74)
            ColumnHeading(text: L.t(.colNetwork, locale), width: 66)
            ColumnHeading(text: L.t(.colDown, locale), width: 72, alignment: .trailing)
            ColumnHeading(text: L.t(.colUp, locale), width: 72, alignment: .trailing)
            ColumnHeading(text: L.t(.colTime, locale), alignment: .trailing)
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
                connections = await tunnel.currentConnections()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
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
                        .background(palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    ProcessIcon(path: group.path)
                    Text(group.process)
                        .font(.ml(12.5, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    IconView(.chevronRight, size: 12, strokeWidth: 2.4)
                        .foregroundStyle(palette.textMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(width: 176, alignment: .leading)

                NodeChip(name: group.chain).frame(width: 128, alignment: .leading)
                Text(group.rule)
                    .font(.ml(11.5)).foregroundStyle(palette.textMuted)
                    .lineLimit(1).frame(width: 66, alignment: .leading)
                HStack(spacing: 4) {
                    ForEach(group.networks, id: \.self) { NetworkChip(network: $0) }
                }
                .frame(width: 66, alignment: .leading)
                Text(Format.bytes(group.download, locale: locale))
                    .font(.mlMono(11.5, .semibold)).foregroundStyle(palette.stUpInk)
                    .frame(width: 72, alignment: .trailing)
                Text(Format.bytes(group.upload, locale: locale))
                    .font(.mlMono(11.5, .semibold)).foregroundStyle(palette.text2)
                    .frame(width: 72, alignment: .trailing)
                Text(Format.age(group.newest, locale: locale))
                    .font(.mlMono(11.5)).foregroundStyle(palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.leading, 16)
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
                .frame(width: 176, alignment: .leading)
            NodeChip(name: connection.node)
                .frame(width: 128, alignment: .leading)
            Text(connection.rule)
                .font(.ml(11.5))
                .foregroundStyle(palette.textMuted)
                .lineLimit(1)
                .frame(width: 66, alignment: .leading)
            NetworkChip(network: connection.network)
                .frame(width: 66, alignment: .leading)
            Text(Format.bytes(connection.download, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.stUpInk)
                .frame(width: 72, alignment: .trailing)
            Text(Format.bytes(connection.upload, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.text2)
                .frame(width: 72, alignment: .trailing)
            Text(Format.age(connection.start, locale: locale))
                .font(.mlMono(11.5)).foregroundStyle(palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
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
