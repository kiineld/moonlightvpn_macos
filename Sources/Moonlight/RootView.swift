import SwiftUI
import MoonlightDesign
import MoonlightCore

enum Page: Hashable {
    case connect, subscription, apps, settings, importSubscription
}

struct RootView: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    /// `ML_PAGE` opens the app straight onto a screen. It exists for
    /// `scripts/screenshots.sh`, which cannot click without accessibility
    /// permission, and is inert when unset.
    @State private var page: Page = { switch ProcessInfo.processInfo.environment["ML_PAGE"] ?? "" { case "sub": return .subscription; case "apps": return .apps; case "settings": return .settings; case "import": return .importSubscription; default: return .connect } }()

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(status: statusLabel, connected: tunnel.state.isConnected)
            HStack(spacing: 0) {
                Sidebar(page: $page)
                VStack(spacing: 0) {
                    Header(page: $page)
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(settings.palette.bg)
        .environment(\.palette, settings.palette)
        .mlLocale(settings.locale)
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .frame(minWidth: 1_000, minHeight: 680)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch page {
            case .connect: ConnectScreen(page: $page)
            case .subscription: SubscriptionScreen(page: $page)
            case .apps: AppsScreen(page: $page)
            case .settings: SettingsScreen(page: $page)
            case .importSubscription: ImportScreen(page: $page)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // `id(page)` makes each screen an insertion rather than a mutation, so
        // the transition actually plays — without it SwiftUI reuses the view and
        // only the differing subviews animate. It also resets each screen's
        // local state, which is what re-runs their `onAppear` loads.
        .id(page)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity
        ))
        .animation(Motion.enter, value: page)

    }

    private var statusLabel: String {
        switch tunnel.state {
        case .connected: return L.t(.secured, settings.locale)
        case .connecting: return L.t(.connecting, settings.locale)
        case .disconnecting: return L.t(.disconnecting, settings.locale)
        case .disconnected, .failed: return L.t(.disconnected, settings.locale)
        }
    }
}

// MARK: - Title bar

/// The strip the window's traffic lights sit in.
///
/// The window uses a hidden title bar, so the system buttons float over this
/// view's leading edge — hence the leading padding rather than the design's own
/// drawn circles. Drawing fake ones would give the window two sets.
///
/// The height is 28pt, not the design's 40, because AppKit centres the traffic
/// lights in the *standard* titlebar height and gives no supported way to move
/// them. At 40pt the wordmark sat six points below the buttons; matching the
/// height is what puts them on one row.
private struct TitleBar: View {
    @Environment(\.palette) private var palette
    let status: String
    let connected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Spacer()
            Text("moonlight")
                .font(.ml(12.5, .heavy))
            Circle()
                .fill(connected ? palette.accentInk : palette.textMuted)
                .frame(width: 5, height: 5)
            Text(status)
                .font(.ml(12.5, .heavy))
            Spacer()
        }
        .foregroundStyle(palette.textMuted)
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(palette.bgDeep)
        .overlay(alignment: .bottom) { palette.hairline.frame(height: 1) }
        .animation(Motion.paint, value: connected)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                LogoTile(size: 32, radius: 10)
                Text("moonlight")
                    .font(.mlDisplay(17, .bold))
                    .tracking(-0.025 * 17)
                    .foregroundStyle(palette.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 14)

            NavItem(icon: .power, title: L.t(.navConnect, locale),
                    active: page == .connect) { page = .connect }
            NavItem(icon: .sparkles, title: L.t(.navSubscription, locale),
                    active: page == .subscription || page == .importSubscription) {
                page = .subscription
            }
            NavItem(icon: .layers, title: L.t(.navApps, locale),
                    active: page == .apps) { page = .apps }
            NavItem(icon: .settings, title: L.t(.navSettings, locale),
                    active: page == .settings) { page = .settings }

            Spacer()
            quotaCard
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 236)
        .background(palette.bgDeep)
        .overlay(alignment: .trailing) { palette.hairline.frame(width: 1) }
    }

    /// With no subscription there is nothing to be unknown *about*, so the
    /// figures read zero. "—" and "без срока" are answers about a plan, and
    /// showing them before one exists looks like a plan whose panel omitted a
    /// field.
    private var planDays: String {
        guard tunnel.hasSubscription else { return Format.days(0, locale: locale) }
        return Format.days(tunnel.info.daysLeft, locale: locale)
    }

    /// "24,8 из 100 ГБ трафика" — a sentence, so an unlimited plan says so
    /// rather than reading as "— of unlimited of traffic".
    private var quotaLine: String {
        guard tunnel.hasSubscription else {
            return "\(Format.bytes(0, locale: locale)) \(L.t(.trafficOf, locale))"
        }
        guard tunnel.info.total != nil else {
            return "\(L.t(.unlimited, locale)) \(L.t(.trafficOf, locale))"
        }
        return Format.quota(used: tunnel.info.used, total: tunnel.info.total, locale: locale)
            + " " + L.t(.trafficOf, locale)
    }

    private var quotaCard: some View {
        Button {
            page = .subscription
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Overline(text: L.t(.remainingCaps, locale))
                    Spacer(minLength: 8)
                    if tunnel.hasSubscription {
                        Text(L.t(tunnel.info.isActive ? .active : .expired, locale))
                            .font(.ml(10.5, .heavy))
                            .foregroundStyle(palette.textOnAccent)
                            .padding(.horizontal, 9)
                            .frame(height: 22)
                            .background(tunnel.info.isActive ? palette.accent : palette.danger)
                            .clipShape(Capsule())
                    }
                }
                Text(planDays)
                    .font(.mlDisplay(22))
                    .tracking(TypeScale.trackDisplay * 22)
                    .foregroundStyle(palette.text)
                    .padding(.top, 8)
                QuotaBar(fraction: tunnel.hasSubscription
                         ? tunnel.info.usedFraction.map { 1 - $0 } : 0, height: 6)
                    .padding(.top, 10)
                Text(quotaLine)
                    .font(.ml(12))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            )
        }
        .pressCard()
    }
}

private struct NavItem: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    let title: String
    let active: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconView(icon, size: 19)
                Text(title).font(.ml(14, .heavy))
                Spacer(minLength: 0)
            }
            // Hover shifts the label to accent ink as well as washing the
            // background: on the near-white light sidebar a background tint
            // alone is barely a change, and the design's hover language is a
            // colour shift rather than a fill.
            .foregroundStyle(active ? palette.textOnAccent
                             : (hovering ? palette.accentInk : palette.text2))
            .padding(.horizontal, 12)
            .frame(height: 44)
            // `surface` is white in light mode, which on the near-white sidebar
            // reads as a smudge rather than a hover. The accent wash is a tint in
            // both themes.
            .background(active ? palette.accent : (hovering ? palette.accentQuiet : .clear))
            .overlay(
                Capsule().strokeBorder(
                    hovering && !active ? palette.accentLine.opacity(0.5) : .clear,
                    lineWidth: 1
                )
            )
            .clipShape(Capsule())
            .contentShape(Rectangle())
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: active)
        .animation(Motion.paint, value: hovering)
    }
}

// MARK: - Header

private struct Header: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t(title, locale))
                    .font(.mlDisplay(20))
                    .tracking(TypeScale.trackDisplay * 20)
                    .foregroundStyle(palette.text)
                Text(L.t(subtitle, locale))
                    .font(.ml(TypeScale.meta))
                    .foregroundStyle(palette.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PillButton(
                title: L.t(tunnel.isPinging ? .pinging : .ping, locale),
                icon: .activity,
                blinking: tunnel.isPinging
            ) {
                Task { await tunnel.pingAll() }
            }
            // Probing goes through the core's own outbounds, which do not exist
            // until it is up.
            .disabled(!tunnel.state.isConnected)
            .opacity(tunnel.state.isConnected ? 1 : 0.45)

            PillButton(
                title: L.t(tunnel.isRefreshing ? .refreshing : .refresh, locale),
                icon: .refreshCW,
                spinning: tunnel.isRefreshing
            ) {
                Task { await tunnel.refresh() }
            }
            .disabled(!tunnel.hasSubscription)
            .opacity(tunnel.hasSubscription ? 1 : 0.45)

            Button {
                settings.toggleTheme()
            } label: {
                IconView(settings.theme == .dark ? .sun : .moon, size: 17)
                    .foregroundStyle(palette.text2)
                    .frame(width: 38, height: 38)
                    .background(palette.surface2)
                    .clipShape(Circle())
            }
            .pressIcon()
            .accessibilityLabel(L.t(.theme, locale))
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .overlay(alignment: .bottom) { palette.hairlineSoft.frame(height: 1) }
    }

    private var title: L.Key {
        switch page {
        case .connect: return .titleConnect
        case .subscription: return .titleSubscription
        case .apps: return .titleApps
        case .settings: return .titleSettings
        case .importSubscription: return .titleImport
        }
    }

    private var subtitle: L.Key {
        switch page {
        case .connect: return .subtitleConnect
        case .subscription: return .subtitleSubscription
        case .apps: return .subtitleApps
        case .settings: return .subtitleSettings
        case .importSubscription: return .subtitleImport
        }
    }
}

// MARK: - Logo

/// The wordmark tile from `assets/logo-tile.svg`, redrawn as vectors so it
/// paints crisply at every size and follows the accent in light mode.
struct LogoTile: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 32
    var radius: CGFloat = 10

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 44
            func scaled(_ d: String) -> Path {
                SVGPath(d).path(in: CGRect(origin: .zero, size: canvasSize), viewBox: 44)
            }
            let ink = GraphicsContext.Shading.color(palette.textOnAccent)
            context.fill(scaled("M30 22a8.4 8.4 0 1 1-9.4-8.34A10 10 0 0 0 30 22Z"), with: ink)
            context.fill(
                Path(ellipseIn: CGRect(x: (30.5 - 1.7) * scale, y: (12.5 - 1.7) * scale,
                                       width: 3.4 * scale, height: 3.4 * scale)),
                with: ink
            )
            context.fill(
                Path(ellipseIn: CGRect(x: (25 - 1.1) * scale, y: (8 - 1.1) * scale,
                                       width: 2.2 * scale, height: 2.2 * scale)),
                with: ink
            )
        }
        .frame(width: size, height: size)
        .background(palette.accent)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
