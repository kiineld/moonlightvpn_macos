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
                                locale: locale
                            ) {
                                withAnimation(Motion.paint) {
                                    expanded = expanded == group.process ? nil : group.process
                                }
                            }
                            if expanded == group.process {
                                ForEach(group.items.sorted { $0.download > $1.download }) { item in
                                    HostRow(connection: item, locale: locale)
                                }
                            }
                            palette.hairlineSoft.frame(height: 1)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L.t(.colProcess, locale)).frame(width: 176, alignment: .leading)
            Text(L.t(.colChain, locale)).frame(width: 128, alignment: .leading)
            Text(L.t(.colRule, locale)).frame(width: 66, alignment: .leading)
            Text(L.t(.colNetwork, locale)).frame(width: 66, alignment: .leading)
            Text(L.t(.colDown, locale)).frame(width: 72, alignment: .trailing)
            Text(L.t(.colUp, locale)).frame(width: 72, alignment: .trailing)
            Text(L.t(.colTime, locale)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.ml(10.5, .heavy))
        .tracking(0.08 * 10.5)
        .foregroundStyle(palette.textMuted)
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

    var body: some View {
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
                    if !group.path.isEmpty {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: group.path))
                            .resizable().frame(width: 16, height: 16)
                    }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .pressCard()
    }
}

private struct HostRow: View {
    @Environment(\.palette) private var palette
    let connection: MihomoAPI.Connection
    let locale: AppLocale

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
        }
        .padding(.leading, 36)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .background(palette.surface2.opacity(0.5))
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
