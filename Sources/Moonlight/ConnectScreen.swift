import SwiftUI
import MoonlightDesign
import MoonlightCore

struct ConnectScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dial
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .rise(0, page)
            serverList
                .frame(width: 340)
                .rise(0.07, page)
        }
    }

    // MARK: - Dial

    private var dial: some View {
        Panel(radius: Radii.panel, padding: 24) {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                DialButton(
                    state: tunnel.state,
                    fraction: ringFraction,
                    statusLabel: statusLabel,
                    bigLabel: bigLabel,
                    timer: Format.duration(tunnel.uptime),
                    enabled: tunnel.hasSubscription
                ) {
                    Task { await tunnel.toggle() }
                }

                HStack(spacing: 9) {
                    Text(L.t(tunnel.state.isConnected ? .hintDisconnect : .hintConnect, locale))
                        .font(.ml(TypeScale.meta))
                        .foregroundStyle(palette.textMuted)
                    Text("⌘⇧C")
                        .font(.mlMono(11))
                        .foregroundStyle(palette.text2)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: Radii.chip, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radii.chip, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1)
                        )
                }

                counters
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// What is *left*, not what has been spent. A session's byte counters are
    /// the least actionable numbers on the screen; how much plan remains is the
    /// thing people open the app to check.
    private var counters: some View {
        HStack(spacing: 0) {
            counter(L.t(.trafficLeft, locale), trafficLeft)
            divider
            counter(L.t(.timeLeft, locale), timeLeft)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .frame(maxWidth: 420)
        .background(palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var divider: some View {
        palette.hairline.frame(width: 1, height: 38)
    }

    private func counter(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Overline(text: label)
            Text(value)
                .font(.mlDisplay(20))
                .tracking(TypeScale.trackDisplay * 20)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// The ring is **full when connected**, and sweeps closed as it connects.
    ///
    /// It used to show remaining quota, which meant a perfectly healthy tunnel
    /// drew a ring with a gap in it — and a gap in a status ring reads as a
    /// fault, not as "you have used some traffic". The quota already has a bar
    /// of its own in the sidebar, where a partial fill is the point.
    private var ringFraction: Double {
        tunnel.state.isConnected ? 1 : 0
    }

    private var trafficLeft: String {
        guard tunnel.hasSubscription else { return Format.bytes(0, locale: locale) }
        guard let total = tunnel.info.total else { return L.t(.unlimited, locale) }
        return Format.bytes(max(0, total - (tunnel.info.used ?? 0)), locale: locale)
    }

    private var timeLeft: String {
        guard tunnel.hasSubscription else { return Format.days(0, locale: locale) }
        return Format.timeLeft(tunnel.info.expire, locale: locale)
    }

    private var statusLabel: String {
        switch tunnel.state {
        case .connected: return L.t(.secured, locale)
        case .connecting: return L.t(.connecting, locale)
        case .disconnecting: return L.t(.disconnecting, locale)
        case .disconnected, .failed: return L.t(.disconnected, locale)
        }
    }

    private var bigLabel: String {
        tunnel.state.isConnected ? L.t(.bigConnected, locale) : L.t(.bigConnect, locale)
    }

    // MARK: - Servers

    private var serverList: some View {
        Panel(radius: Radii.panel, padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Overline(text: L.t(.servers, locale))
                    Spacer()
                    Text("\(tunnel.selectableNodes.count) \(L.t(.nodesCount, locale))")
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)

                if tunnel.nodes.isEmpty {
                    emptyState
                } else {
                    autoRow
                    palette.hairlineSoft
                        .frame(height: 1)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                    ScrollView {
                        LazyVStack(spacing: 2) {
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
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            IconView(.globe, size: 34)
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
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .pressButton()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
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
            .background(tunnel.autoSelect ? palette.surface2 : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Radii.row, style: .continuous))
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

// MARK: - Dial

private struct DialButton: View {
    @Environment(\.palette) private var palette
    let state: ConnectionState
    let fraction: Double
    let statusLabel: String
    let bigLabel: String
    let timer: String
    let enabled: Bool
    let action: () -> Void

    @State private var breathing = false

    private var tone: Color {
        state.isConnected ? palette.accentInk : palette.textMuted
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Halo — a thin accent ring outside the dial that breathes while
                // the tunnel is up.
                Circle()
                    .strokeBorder(palette.accent, lineWidth: 1)
                    .padding(-10)
                    .opacity(state.isConnected ? (breathing ? 0.28 : 0.5) : 0)
                    .scaleEffect(breathing ? 1.012 : 1)

                Circle().strokeBorder(palette.hairline, lineWidth: 2)

                // The quota sweep. Trimmed and rotated rather than drawn with an
                // angular gradient, so the arc has a true end rather than a seam.
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(3)

                VStack(spacing: 7) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(tone)
                            .frame(width: 8, height: 8)
                            .shadow(color: state.isConnected ? palette.accent.opacity(0.7) : .clear,
                                    radius: 5)
                        Text(statusLabel.uppercased())
                            .font(.ml(TypeScale.micro, .heavy))
                            .tracking(TypeScale.trackOverline * TypeScale.micro)
                            .foregroundStyle(tone)
                    }
                    Text(bigLabel)
                        .font(.mlDisplay(26))
                        .tracking(TypeScale.trackDisplay * 26)
                        .foregroundStyle(palette.text)
                    Text(timer)
                        .font(.mlMono(15))
                        .foregroundStyle(tone)
                }
            }
            .frame(width: 238, height: 238)
            .contentShape(Circle())
        }
        .buttonStyle(PressScale(scale: 0.975))
        .disabled(!enabled || state.isBusy)
        .opacity(enabled ? 1 : 0.5)
        .animation(Motion.enter, value: state)
        .animation(Motion.enter, value: fraction)
        .onAppear { startBreathing() }
        .onChange(of: state) { _ in startBreathing() }
    }

    private func startBreathing() {
        breathing = false
        guard state.isConnected else { return }
        withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
            breathing = true
        }
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
            .background(selected ? palette.surface2 : (hovering ? palette.surface2.opacity(0.6) : .clear))
            .clipShape(RoundedRectangle(cornerRadius: Radii.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: selected)
        .animation(Motion.paint, value: hovering)
    }
}
