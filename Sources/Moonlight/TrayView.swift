import SwiftUI
import MoonlightDesign
import MoonlightCore

/// What the tray remembers between openings.
@MainActor
final class TrayState: ObservableObject {
    /// Pinned, the tray stays open when the user clicks elsewhere — for
    /// watching the speeds or trying servers one after another.
    @Published var pinned = false
}

/// The menu bar tray: the service's message, the tunnel at a glance, how it
/// routes, and every server — without opening the window.
struct TrayView: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var tray: TrayState
    let openWindow: () -> Void

    var body: some View {
        TrayContent(tray: tray, openWindow: openWindow)
            .environment(\.palette, settings.palette)
            .environment(\.liquidGlass, settings.liquidGlass)
            .mlLocale(settings.locale)
            .preferredColorScheme(settings.theme == .dark ? .dark : .light)
    }
}

private struct TrayContent: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.liquidGlass) private var liquidGlass
    @Environment(\.appLocale) private var locale
    @ObservedObject var tray: TrayState
    let openWindow: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if let announce = tunnel.info.announce {
                AnnounceBanner(text: announce)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
            }
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
            SegmentedPill(selection: routing, options: [
                (RoutingMode.rule, L.t(.routingRule, locale)),
                (RoutingMode.global, L.t(.routingGlobal, locale)),
                (RoutingMode.direct, L.t(.routingDirect, locale)),
            ])
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .disabled(!tunnel.hasSubscription)
            searchRow
                .padding(.horizontal, 12)
                .padding(.top, 10)
            list
            footer
        }
        .frame(width: TrayMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(backdrop)
    }

    /// The routing mode as a binding the segmented control can write.
    private var routing: Binding<RoutingMode> {
        Binding(
            get: { tunnel.routingMode },
            set: { mode in Task { await tunnel.setRoutingMode(mode) } }
        )
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                LogoTile(size: 26, radius: 8)
                Text("moonlight")
                    .font(.mlWordmark(15))
                    .tracking(-0.025 * 15)
                    .foregroundStyle(palette.text)
                    .fixedSize()
                Spacer(minLength: 8)
                Button {
                    tray.pinned.toggle()
                } label: {
                    IconView(.pin, size: 14, strokeWidth: 2.2)
                        .rotationEffect(.degrees(tray.pinned ? 0 : 45))
                        .foregroundStyle(tray.pinned ? palette.textOnAccent : palette.text2)
                        .frame(width: 30, height: 30)
                        .mlGlass(.circle,
                                 tint: tray.pinned ? palette.accent : nil,
                                 fallback: tray.pinned ? palette.accent : palette.surface2)
                }
                .pressIcon()
                .help(L.t(tray.pinned ? .stopKeepingOpen : .keepOpen, locale))
                .animation(Motion.paint, value: tray.pinned)
            }

            TrayStatusLine(state: tunnel.state, meter: tunnel.meter)

            if let issue = tunnel.issue {
                IssueLine(issue: issue)
            }
        }
    }

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                IconView(.search, size: 14).foregroundStyle(palette.textMuted)
                TextField(L.t(.searchServers, locale), text: $query)
                    .textFieldStyle(.plain)
                    .font(.ml(12.5))
                    .foregroundStyle(palette.text)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        IconView(.x, size: 12).foregroundStyle(palette.textMuted)
                    }
                    .pressIcon()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .mlGlass(.capsule, fallback: palette.surface2)

            Button {
                Task { await tunnel.pingAll() }
            } label: {
                HStack(spacing: 6) {
                    IconView(.zap, size: 13, strokeWidth: 2.2)
                        .foregroundStyle(palette.accentInk)
                        .opacity(tunnel.isPinging ? 0.5 : 1)
                    Text(L.t(tunnel.isPinging ? .pinging : .pingAll, locale))
                        .font(.ml(12.5, .heavy))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .mlGlass(.capsule, fallback: palette.surface2)
            }
            .pressButton()
            .disabled(!tunnel.hasSubscription || tunnel.isPinging)
        }
    }

    // MARK: - Servers

    private var filtered: [Node] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return tunnel.selectableNodes }
        return tunnel.selectableNodes.filter { node in
            [node.name, node.subtitle(locale), node.serverDescription ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    private var showsAuto: Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty || L.t(.auto, locale).lowercased().contains(needle)
    }

    private var list: some View {
        ZStack(alignment: .bottom) {
            if !tunnel.hasSubscription {
                noSubscription
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if showsAuto { autoRow }
                        ForEach(filtered) { node in
                            TrayNodeRow(
                                node: node,
                                selected: !tunnel.autoSelect && node.name == tunnel.selectedNode,
                                measuring: tunnel.pendingProbes.contains(node.name),
                                select: { Task { await tunnel.select(node: node.name) } },
                                ping: { Task { await tunnel.ping(node: node.name) } }
                            )
                        }
                        if filtered.isEmpty && !showsAuto {
                            Text(L.t(.nothingFound, locale))
                                .font(.ml(12.5))
                                .foregroundStyle(palette.textMuted)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    // Room for the floating button, so the last row can be
                    // scrolled clear of it.
                    .padding(.bottom, 72)
                }
                .mlScrollIndicators(hidden: true)
            }
            connectButton.padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
    }

    /// The one automatic row, as in the window's drawer.
    private var autoRow: some View {
        let auto = tunnel.panelAutoNode
        return TrayRowFrame(selected: tunnel.autoSelect) {
            Button {
                Task { await tunnel.selectAuto() }
            } label: {
                HStack(spacing: 10) {
                    IconView(.zap, size: 15, strokeWidth: 2.2)
                        .foregroundStyle(tunnel.autoSelect ? palette.textOnAccent : palette.accentInk)
                        .frame(width: 26, height: 26)
                        .mlGlass(.circle, tint: tunnel.autoSelect ? palette.accent : nil,
                                 fallback: palette.surface3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L.t(.auto, locale))
                            .font(.ml(13.5, .bold))
                            .foregroundStyle(tunnel.autoSelect ? palette.accentInk : palette.text)
                        TrayChip(text: auto?.protocolFamily ?? L.t(.autoSubtitle, locale), quiet: true)
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } trailing: {
            if let auto {
                TrayLatency(node: auto, measuring: tunnel.pendingProbes.contains(auto.name)) {
                    Task { await tunnel.ping(node: auto.name) }
                }
            }
        }
    }

    private var noSubscription: some View {
        VStack(spacing: 10) {
            IconView(.globe, size: 26).foregroundStyle(palette.textMuted)
            Text(L.t(.noSubscription, locale))
                .font(.ml(14, .heavy))
                .foregroundStyle(palette.text)
            Text(L.t(.noSubscriptionHint, locale))
                .font(.ml(12))
                .foregroundStyle(palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Connect

    private var connectButton: some View {
        let connected = tunnel.state.isConnected
        let busy = tunnel.state.isBusy
        return Button {
            Task { await tunnel.toggle() }
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    IconView(connected ? .square : .power, size: 15, strokeWidth: 2.4)
                }
                Text(connectLabel)
                    .font(.ml(14, .heavy))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(connected || busy ? palette.text : palette.textOnAccent)
            .padding(.horizontal, 24)
            .frame(height: 44)
            .mlGlass(.capsule,
                     tint: connected || busy ? nil : palette.accent,
                     fallback: connected || busy ? palette.surface3 : palette.accent)
            // Floats over the list: a ring of the canvas colour separates it
            // from the rows scrolling beneath, where a shadow would be a glow.
            .overlay(Capsule().strokeBorder(palette.bgDeep, lineWidth: 3).padding(-3))
        }
        .pressButton()
        .disabled(!tunnel.hasSubscription || busy)
        .opacity(tunnel.hasSubscription ? 1 : 0.5)
        .animation(Motion.paint, value: connected)
    }

    private var connectLabel: String {
        switch tunnel.state {
        case .connected: return L.t(.disconnectAction, locale)
        case .connecting: return L.t(.connecting, locale)
        case .disconnecting: return L.t(.disconnecting, locale)
        case .disconnected, .failed: return L.t(.connectAction, locale)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: openWindow) {
                HStack(spacing: 7) {
                    IconView(.monitor, size: 14)
                    Text(L.t(.openWindow, locale))
                        .font(.ml(12.5, .heavy))
                        .fixedSize()
                }
                .foregroundStyle(palette.text)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .mlGlass(.capsule, fallback: palette.surface2)
            }
            .pressButton()

            Spacer(minLength: 8)

            if let title = tunnel.info.title, tunnel.hasSubscription {
                HStack(spacing: 6) {
                    IconView(.sparkles, size: 13).foregroundStyle(palette.accentInk)
                    Text(title)
                        .font(.ml(12, .semibold))
                        .foregroundStyle(palette.text2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .frame(height: 32)
                .overlay(Capsule().stroke(palette.hairline, lineWidth: 1))
            }

            Button {
                AppExit.quit()
            } label: {
                IconView(.logOut, size: 14)
                    .foregroundStyle(palette.textMuted)
                    .frame(width: 32, height: 32)
                    .mlGlass(.circle, fallback: palette.surface2)
            }
            .pressIcon()
            .help(L.t(.quit, locale))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .mlGlass(.rounded(0), fallback: palette.surface)
    }

    /// The window's canvas in miniature: `bgDeep` with light falling in from
    /// the top, so the glass on it reads as glass.
    private var backdrop: some View {
        // Over the popover's own glass rather than hiding it: black at three
        // quarters, so the desktop's light still reaches the glass on top.
        ZStack {
            // Solid without glass: there is nothing on top for the light to reach.
            palette.bgDeep.opacity(liquidGlass ? 0.76 : 1)
            RadialGradient(
                colors: [palette.text.opacity(0.10), palette.text.opacity(0)],
                center: .topTrailing, startRadius: 0, endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

enum TrayMetrics {
    static let width: CGFloat = 384
    static let height: CGFloat = 620
}

// MARK: - Rows

/// A server: flag, name, what it runs and what it is for, and its latency with
/// a button to measure it again.
private struct TrayNodeRow: View {
    @Environment(\.palette) private var palette
    let node: Node
    let selected: Bool
    let measuring: Bool
    let select: () -> Void
    let ping: () -> Void

    var body: some View {
        TrayRowFrame(selected: selected) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Group {
                        if let flag = node.flag {
                            Text(flag).font(.system(size: 19))
                        } else {
                            IconView(.zap, size: 15, strokeWidth: 2.2)
                                .foregroundStyle(palette.accentInk)
                        }
                    }
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(node.title)
                            .font(.ml(13.5, .bold))
                            .foregroundStyle(selected ? palette.accentInk : palette.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            TrayChip(text: node.protocolFamily, quiet: true)
                            if let description = node.serverDescription {
                                TrayChip(text: description, quiet: false)
                                    .help(description)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } trailing: {
            TrayLatency(node: node, measuring: measuring, ping: ping)
        }
    }
}

/// The row shell both kinds share: padding, the selection, the hover wash.
private struct TrayRowFrame<Leading: View, Trailing: View>: View {
    @Environment(\.palette) private var palette
    let selected: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            leading()
            trailing()
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        // The selected row sits on glass, as in the window's drawer; the rest
        // take only a hover wash.
        .background {
            if selected {
                Color.clear.mlGlass(.rounded(14), fallback: palette.surface2)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.text.opacity(hovering ? 0.05 : 0))
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: selected)
        .animation(Motion.paint, value: hovering)
    }
}

/// The ping button and the number it produced.
private struct TrayLatency: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let node: Node
    let measuring: Bool
    let ping: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: ping) {
                IconView(.zap, size: 13, strokeWidth: 2.2)
                    .foregroundStyle(measuring ? palette.accentInk : palette.textMuted)
                    .opacity(measuring ? 0.5 : 1)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .pressIcon()
            .disabled(measuring)
            .help(L.t(.pingOne, locale))

            Text(measuring ? "…" : Format.latency(node.latency, unreachable: node.unreachable))
                .font(.mlMono(12))
                .foregroundStyle(latencyTone(node, palette))
                .lineLimit(1)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

extension Node {
    /// "VLESS", "HYSTERIA2" — the transport without its security layer, which
    /// is what fits in a chip beside the server's description.
    var protocolFamily: String {
        (protocolLabel?.split(separator: " ").first.map(String.init) ?? type).uppercased()
    }
}

/// A small label under a server's name.
private struct TrayChip: View {
    @Environment(\.palette) private var palette
    let text: String
    /// Quiet for the transport, which every row has; the description is what
    /// tells rows apart, so it reads louder.
    let quiet: Bool

    var body: some View {
        Text(text)
            .font(.ml(10.5, quiet ? .bold : .semibold))
            .foregroundStyle(quiet ? palette.textMuted : palette.text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .mlGlass(.capsule, fallback: palette.text.opacity(quiet ? 0.06 : 0.1))
            .layoutPriority(quiet ? 1 : 0)
    }
}

/// The state, the uptime and the speeds — the tray's one line that changes
/// every second, so the one part that observes the meter.
private struct TrayStatusLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let state: ConnectionState
    @ObservedObject var meter: TrafficMeter

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isConnected ? palette.accent : palette.textMuted)
                .frame(width: 7, height: 7)
            Text(statusLine)
                .font(.ml(12.5, .semibold))
                .foregroundStyle(state.isConnected ? palette.accentInk : palette.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            rate(.arrowDown, meter.rateDown, tone: palette.accentInk)
            rate(.arrowUp, meter.rateUp, tone: palette.text2)
        }
    }

    private var statusLine: String {
        switch state {
        case .connected:
            return "\(L.t(.bigConnected, locale)) · \(Format.duration(meter.uptime))"
        case .connecting: return L.t(.connecting, locale)
        case .disconnecting: return L.t(.disconnecting, locale)
        case .disconnected, .failed: return L.t(.disconnected, locale)
        }
    }

    private func rate(_ icon: Icon, _ value: Int64, tone: Color) -> some View {
        HStack(spacing: 3) {
            IconView(icon, size: 12, strokeWidth: 2.4)
            Text(Format.rate(state.isConnected ? value : 0, locale: locale))
                .font(.mlMono(12))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(state.isConnected ? tone : palette.textMuted)
    }
}
