import SwiftUI
import MoonlightDesign
import MoonlightCore

struct ConnectScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    var body: some View {
        VStack(spacing: 0) {
            hero.rise(0, page)
            serverList
                .frame(maxWidth: 560)
                .padding(.top, 34)
                .rise(0.07, page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Hero

    /// How long the tunnel has been up, the one control that matters, and what
    /// state it is in — nothing else competes for the top of the window.
    private var hero: some View {
        VStack(spacing: 0) {
            Text(L.t(.connectionTime, locale))
                .font(.ml(12.5, .semibold))
                .foregroundStyle(palette.text2)
            Text(Format.duration(tunnel.uptime))
                .font(.ml(20, .semibold).monospacedDigit())
                .foregroundStyle(tunnel.state.isConnected ? palette.text : palette.textMuted)
                .padding(.top, 3)

            PowerButton(state: tunnel.state, enabled: tunnel.hasSubscription) {
                Task { await tunnel.toggle() }
            }
            .help("\(L.t(tunnel.state.isConnected ? .hintDisconnect : .hintConnect, locale)) · ⌘⇧C")
            .padding(.top, 20)

            StatusPill(
                title: statusLabel,
                connected: tunnel.state.isConnected
            ) {
                page = .connections
            }
            .help(L.t(.titleConnections, locale))
            .padding(.top, 18)
        }
        // A faint accent bloom while the tunnel is up. It is also what gives
        // the glass above it something to bend.
        .background(
            RadialGradient(
                colors: [palette.accent.opacity(0.16), palette.accent.opacity(0)],
                center: .center, startRadius: 0, endRadius: 180
            )
            .frame(width: 460, height: 360)
            .opacity(tunnel.state.isConnected ? 1 : 0)
            .animation(Motion.enter, value: tunnel.state.isConnected)
            .allowsHitTesting(false)
        )
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

            Panel(radius: Radii.card, padding: 8) {
                if tunnel.nodes.isEmpty {
                    emptyState
                } else {
                    FitOrScroll {
                        VStack(spacing: 2) {
                            autoRow
                            palette.hairlineSoft
                                .frame(height: 1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            ForEach(tunnel.selectableNodes) { node in
                                NodeRow(
                                    node: node,
                                    selected: !tunnel.autoSelect && node.name == tunnel.selectedNode,
                                    measuring: tunnel.pendingProbes.contains(node.name)
                                ) {
                                    Task { await tunnel.select(node: node.name) }
                                }
                            }
                        }
                    }
                }
            }
        }
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
                            .fill(auto.latency.map { palette.pingColor($0) } ?? palette.textMuted)
                            .frame(width: 6, height: 6)
                        Text(tunnel.pendingProbes.contains(auto.name)
                             ? "…" : Format.latency(auto.latency))
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
            return "\(L.t(.autoPicked, locale)) \(node.title) · \(Format.latency(node.latency))"
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
    let action: () -> Void

    @State private var hovering = false

    private static let tile: CGFloat = 92
    private static let knob: CGFloat = 58

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(state.isConnected ? palette.accent : palette.surface3)
                    .frame(width: Self.knob, height: Self.knob)
                    .shadow(color: state.isConnected ? palette.accent.opacity(0.45) : .clear,
                            radius: 14)
                if state.isBusy {
                    SpinnerArc()
                        .frame(width: Self.knob + 12, height: Self.knob + 12)
                }
                glyph
            }
            .frame(width: Self.tile, height: Self.tile)
            .mlGlass(.rounded(28), fallback: palette.surface)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.textOnAccent)
                .frame(width: 20, height: 20)
        } else {
            IconView(.power, size: 24, strokeWidth: 2.4)
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
                        .fill(node.latency.map { palette.pingColor($0) } ?? palette.textMuted)
                        .frame(width: 6, height: 6)
                    Text(measuring ? "…" : Format.latency(node.latency))
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
