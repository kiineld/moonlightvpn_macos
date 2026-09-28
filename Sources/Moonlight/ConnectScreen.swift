import SwiftUI
import MoonlightDesign
import MoonlightCore

struct ConnectScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    /// Whether the server drawer is open.
    @State private var serversOpen = false
    /// The drawer's natural height, measured, so it opens to exactly its
    /// content rather than to a guess.
    @State private var drawerContent: CGFloat = 0
    /// The parts above and below the power button, measured. Neither changes
    /// when the drawer opens, so the button's size and the page's offset can
    /// be worked out from them in the same animation as the drawer — measuring
    /// the whole column instead re-read it after the button had resized, and
    /// the page jumped at the end of the spring.
    @State private var aboveButton: CGFloat = 0
    @State private var belowButton: CGFloat = 0

    /// One curve for everything the drawer moves: its height, its fade and the
    /// chevron — a spring, so the list settles instead of stopping dead.
    private static let drawer = Animation.spring(response: 0.42, dampingFraction: 0.86)
    private static let pickerHeight: CGFloat = 60
    private static let drawerGap: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let button = PowerButton.side(large: !serversOpen)
            VStack(spacing: 0) {
                timer
                    .padding(.bottom, 20)
                    .background(measure(AboveButtonKey.self))
                    .rise(0, page)
                PowerButton(state: tunnel.state, enabled: tunnel.hasSubscription,
                            large: !serversOpen) {
                    Task { await tunnel.toggle() }
                }
                .help("\(L.t(tunnel.state.isConnected ? .hintDisconnect : .hintConnect, locale)) · ⌘⇧C")
                .background(bloom)
                .rise(0, page)
                belowButtonContent
                    .background(measure(BelowButtonKey.self))
                if !tunnel.nodes.isEmpty {
                    drawer(room: height - aboveButton - PowerButton.side(large: false)
                           - belowButton - Self.drawerGap)
                        .frame(maxWidth: 560)
                        .padding(.top, Self.drawerGap)
                }
            }
            // Closed, the button is the page: large, with its centre on the
            // page's centre, and pulled up only as far as it takes for the rest
            // to fit. Opening the drawer shrinks it and lifts the column to the
            // top on the drawer's own spring, and the list takes the room that
            // frees.
            .padding(.top, serversOpen ? 0 : Self.centredOffset(
                page: height, above: aboveButton, button: button, below: belowButton))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onPreferenceChange(AboveButtonKey.self) { aboveButton = $0 }
        .onPreferenceChange(BelowButtonKey.self) { belowButton = $0 }
    }

    /// How far down to start the column so the button's centre lands on the
    /// page's, without pushing what is under it off the bottom.
    static func centredOffset(page: CGFloat, above: CGFloat, button: CGFloat, below: CGFloat) -> CGFloat {
        let centred = page / 2 - above - button / 2
        let lowest = page - above - button - below
        return max(0, min(centred, lowest))
    }

    private func measure<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        }
    }

    // MARK: - Hero

    /// How long the tunnel has been up.
    private var timer: some View {
        VStack(spacing: 0) {
            Text(L.t(.connectionTime, locale))
                .font(.ml(12.5, .semibold))
                .foregroundStyle(palette.text2)
            Text(Format.duration(tunnel.uptime))
                .font(.ml(20, .semibold).monospacedDigit())
                .foregroundStyle(tunnel.state.isConnected ? palette.text : palette.textMuted)
                .padding(.top, 3)
        }
    }

    /// The state in words, why it is not connected, the service's message,
    /// and the server picker.
    private var belowButtonContent: some View {
        VStack(spacing: 0) {
            StatusPill(
                title: statusLabel,
                connected: tunnel.state.isConnected
            ) {
                page = .connections
            }
            .help(L.t(.titleConnections, locale))
            .padding(.top, 18)
            .rise(0, page)

            // Why it is not connected, or why the list may be stale — a failed
            // connect used to leave only "Отключено", with the reason in the log.
            if let issue = tunnel.issue {
                IssueLine(issue: issue, centered: true)
                    .frame(maxWidth: 440)
                    .padding(.top, 14)
            }
            if let announce = tunnel.info.announce {
                AnnounceBanner(text: announce)
                    .frame(maxWidth: 560)
                    .padding(.top, 28)
                    .rise(0.05, page)
            }
            serverList
                .frame(maxWidth: 560)
                .padding(.top, 28)
                .rise(0.07, page)
        }
    }

    /// A faint accent bloom while the tunnel is up. It is also what gives the
    /// glass above it something to bend.
    private var bloom: some View {
        RadialGradient(
            colors: [palette.accent.opacity(0.16), palette.accent.opacity(0)],
            center: .center, startRadius: 0, endRadius: 180
        )
        .frame(width: 460, height: 360)
        .opacity(tunnel.state.isConnected ? 1 : 0)
        .animation(Motion.enter, value: tunnel.state.isConnected)
        .allowsHitTesting(false)
    }

    private var statusLabel: String {
        switch tunnel.state {
        case .connected: return L.t(.bigConnected, locale)
        case .connecting: return L.t(.connecting, locale)
        case .disconnecting: return L.t(.disconnecting, locale)
        case .disconnected, .failed: return L.t(.disconnected, locale)
        }
    }

    // MARK: - Servers

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Overline(text: L.t(.servers, locale))
                if !tunnel.nodes.isEmpty {
                    Text("\(tunnel.selectableNodes.count) \(L.t(.nodesCount, locale))")
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                }
                Spacer()
                // Live whether or not the tunnel is up: with it down the probe
                // runs through the idle core. Picking a server is exactly when
                // the latencies matter.
                GlassIconButton(icon: .activity, blinking: tunnel.isPinging) {
                    Task { await tunnel.pingAll() }
                }
                .help(L.t(tunnel.isPinging ? .pinging : .ping, locale))
                .disabled(!tunnel.hasSubscription || tunnel.isPinging)
                .opacity(tunnel.hasSubscription ? 1 : 0.45)

                GlassIconButton(icon: .refreshCW, spinning: tunnel.isRefreshing) {
                    Task { await tunnel.refresh() }
                }
                .help(L.t(tunnel.isRefreshing ? .refreshing : .refresh, locale))
                .disabled(!tunnel.hasSubscription)
                .opacity(tunnel.hasSubscription ? 1 : 0.45)
            }
            .padding(.horizontal, 6)

            if tunnel.nodes.isEmpty {
                Panel(radius: Radii.card, padding: 8) { emptyState }
            } else {
                picker
            }
        }
    }

    // MARK: - Picker

    /// The server in use, and the way into the rest — as on the phone: one row
    /// until it is opened.
    private var picker: some View {
        Button {
            withAnimation(Self.drawer) { serversOpen.toggle() }
        } label: {
            HStack(spacing: 12) {
                pickedGlyph
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(palette.text.opacity(0.06)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(picked.title)
                        .font(.ml(14.5, .heavy))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(picked.subtitle)
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                IconView(.chevronRight, size: 15, strokeWidth: 2.4)
                    .foregroundStyle(palette.text2)
                    .rotationEffect(.degrees(serversOpen ? -90 : 90))
            }
            .padding(.leading, 10)
            .padding(.trailing, 20)
            .frame(height: Self.pickerHeight)
            .mlGlass(.capsule, fallback: palette.surface)
            .contentShape(Capsule())
        }
        .pressCard()
    }

    @ViewBuilder
    private var pickedGlyph: some View {
        if let node = pickedNode, let flag = node.flag {
            Text(flag).font(.system(size: 20))
        } else {
            IconView(.zap, size: 18, strokeWidth: 2.2).foregroundStyle(palette.accentInk)
        }
    }

    /// The node the picker names: the chosen one, or none while "Авто" is.
    private var pickedNode: Node? {
        guard !tunnel.autoSelect, let name = tunnel.selectedNode else { return nil }
        return tunnel.nodes.first { $0.name == name }
    }

    private var picked: (title: String, subtitle: String) {
        if let node = pickedNode { return (node.title, node.subtitle(locale)) }
        return (L.t(.auto, locale), autoSubtitle)
    }

    // MARK: - Drawer

    /// Every server, under the picker. Always in the hierarchy — only its
    /// height moves, from nothing to its measured content, so opening is one
    /// continuous motion rather than a list popping in and a card resizing
    /// after it. It may use whatever height is left under the picker; past
    /// that it scrolls.
    private func drawer(room: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                autoRow
                ForEach(tunnel.selectableNodes) { node in
                    NodeRow(
                        node: node,
                        selected: !tunnel.autoSelect && node.name == tunnel.selectedNode,
                        measuring: tunnel.pendingProbes.contains(node.name)
                    ) {
                        Task { await tunnel.select(node: node.name) }
                        withAnimation(Self.drawer) { serversOpen = false }
                    }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: DrawerHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .mlScrollIndicators(hidden: true)
        .onPreferenceChange(DrawerHeightKey.self) { drawerContent = $0 }
        .padding(8)
        .frame(height: serversOpen ? max(0, min(drawerContent + 16, room)) : 0, alignment: .top)
        .mlGlass(.rounded(Radii.card), fallback: palette.surface)
        .opacity(serversOpen ? 1 : 0)
        .allowsHitTesting(serversOpen)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            IconView(.globe, size: 30)
                .foregroundStyle(palette.textMuted)
            Text(L.t(.noSubscription, locale))
                .font(.ml(15, .heavy))
                .foregroundStyle(palette.text)
            Text(L.t(.noSubscriptionHint, locale))
                .font(.ml(TypeScale.meta))
                .foregroundStyle(palette.textMuted)
                .multilineTextAlignment(.center)
            Button {
                page = .importSubscription
            } label: {
                Text(L.t(.addSubscription, locale))
                    .font(.ml(13, .heavy))
                    .foregroundStyle(palette.textOnAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .mlGlass(.capsule, tint: palette.accent, fallback: palette.accent)
            }
            .pressButton()
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 26)
    }

    /// The one automatic row.
    ///
    /// When the panel's selector carries its own `url-test` group, this row *is*
    /// that group — choosing it hands the decision to the panel's picker, which
    /// is what its operator built. Showing the app's own "Авто" beside it gave
    /// two rows doing the same job with different answers.
    private var autoRow: some View {
        Button {
            Task { await tunnel.selectAuto() }
            withAnimation(Self.drawer) { serversOpen = false }
        } label: {
            HStack(spacing: 12) {
                IconView(.zap, size: 18, strokeWidth: 2.2)
                    .foregroundStyle(tunnel.autoSelect ? palette.textOnAccent : palette.accentInk)
                    .frame(width: 36, height: 36)
                    .background(tunnel.autoSelect ? palette.accent : palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L.t(.auto, locale))
                        .font(.ml(14, .heavy))
                        .foregroundStyle(palette.text)
                    Text(autoSubtitle)
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let auto = tunnel.panelAutoNode {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(latencyTone(auto, palette))
                            .frame(width: 6, height: 6)
                        Text(tunnel.pendingProbes.contains(auto.name)
                             ? "…" : Format.latency(auto.latency, unreachable: auto.unreachable))
                            .font(.mlMono(12.5))
                            .foregroundStyle(palette.text2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background {
                if tunnel.autoSelect {
                    Color.clear.mlGlass(.rounded(14), fallback: palette.surface2)
                }
            }
            .contentShape(Rectangle())
        }
        .pressCard()
        .animation(Motion.paint, value: tunnel.autoSelect)
    }

    private var autoSubtitle: String {
        // While it is the active choice, say which node it landed on — that is
        // the thing the row cannot otherwise tell you.
        if tunnel.autoSelect, let name = tunnel.selectedNode,
           let node = tunnel.nodes.first(where: { $0.name == name }), !node.isAutoPicker {
            return "\(L.t(.autoPicked, locale)) \(node.title) · "
                + Format.latency(node.latency, unreachable: node.unreachable)
        }
        if let auto = tunnel.panelAutoNode, let label = auto.protocolLabel {
            return label
        }
        return L.t(.autoSubtitle, locale)
    }
}

// MARK: - Power button

/// A glass squircle holding one round control. Off, the circle is neutral and
/// carries the power glyph; on, it fills with the accent and the glyph becomes
/// a stop square — the change of state is the change of colour.
private struct PowerButton: View {
    @Environment(\.palette) private var palette
    let state: ConnectionState
    let enabled: Bool
    /// Large while it is the only thing on the page; the drawer shrinks it.
    var large = false
    let action: () -> Void

    @State private var hovering = false

    /// Everything is drawn at this multiple of the compact size, so the knob,
    /// the glyph and the corner grow together rather than the tile alone.
    private static let largeScale: CGFloat = 1.5
    private static let compactTile: CGFloat = 92

    static func side(large: Bool) -> CGFloat { compactTile * (large ? largeScale : 1) }

    private var scale: CGFloat { large ? Self.largeScale : 1 }
    private var tile: CGFloat { Self.compactTile * scale }
    private var knob: CGFloat { 58 * scale }
    private var corner: CGFloat { 28 * scale }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isConnected ? palette.accent : palette.surface3)
                    .frame(width: knob, height: knob)
                    .shadow(color: state.isConnected ? palette.accent.opacity(0.45) : .clear,
                            radius: 14 * scale)
                if state.isBusy {
                    SpinnerArc()
                        .frame(width: knob + 12 * scale, height: knob + 12 * scale)
                }
                glyph
            }
            .frame(width: tile, height: tile)
            .mlGlass(.rounded(corner), fallback: palette.surface)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.95))
        .disabled(!enabled || state.isBusy)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .animation(Motion.enter, value: state)
        .animation(Motion.paint, value: hovering)
    }

    @ViewBuilder
    private var glyph: some View {
        if state.isConnected {
            RoundedRectangle(cornerRadius: 5 * scale, style: .continuous)
                .fill(palette.textOnAccent)
                .frame(width: 20 * scale, height: 20 * scale)
        } else {
            IconView(.power, size: 24 * scale, strokeWidth: 2.4)
                .foregroundStyle(hovering && enabled ? palette.accentInk : palette.text)
        }
    }
}

/// The arc that turns round the knob while the tunnel is changing state.
private struct SpinnerArc: View {
    @Environment(\.palette) private var palette
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(palette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// The state, in words, as a way into the connections screen. Tinted with the
/// accent while the tunnel is up.
private struct StatusPill: View {
    @Environment(\.palette) private var palette
    let title: String
    let connected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(.ml(13.5, .bold))
                IconView(.chevronRight, size: 14, strokeWidth: 2.4)
            }
            .foregroundStyle(connected ? palette.accentInkStrong : palette.text2)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 34)
            .mlGlass(.capsule,
                     tint: connected ? palette.accent.opacity(0.22) : nil,
                     fallback: connected ? palette.accentQuiet : palette.surface)
            .contentShape(Capsule())
        }
        .pressButton()
        .animation(Motion.paint, value: connected)
    }
}

// MARK: - Node row

private struct NodeRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let node: Node
    let selected: Bool
    let measuring: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // A balancer named for a country is still that country as far as
                // the user is concerned, so it gets the flag its name carries.
                // The accent mark is only for entries with no flag at all — an
                // auto-picker spanning several places.
                if let flag = node.flag {
                    Text(flag).font(.system(size: 20))
                } else {
                    IconView(.zap, size: 16, strokeWidth: 2.2)
                        .foregroundStyle(palette.accentInk)
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(.ml(14, .bold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Text(node.subtitle(locale))
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Circle()
                        .fill(latencyTone(node, palette))
                        .frame(width: 6, height: 6)
                    Text(measuring ? "…" : Format.latency(node.latency, unreachable: node.unreachable))
                        .font(.mlMono(12.5))
                        .foregroundStyle(palette.text2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if selected {
                    Color.clear.mlGlass(.rounded(14), fallback: palette.surface2)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.text.opacity(hovering ? 0.05 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: selected)
        .animation(Motion.paint, value: hovering)
    }
}

/// The dot beside a latency: the ping colour when measured, the danger colour
/// when the probe timed out, muted when not measured yet.
func latencyTone(_ node: Node, _ palette: Palette) -> Color {
    if let latency = node.latency { return palette.pingColor(latency) }
    return node.unreachable ? palette.danger : palette.textMuted
}

/// The drawer's content height, reported from inside its scroll view.
private struct DrawerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The height of what sits above the power button.
private struct AboveButtonKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The height of what sits below it, the drawer aside.
private struct BelowButtonKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
