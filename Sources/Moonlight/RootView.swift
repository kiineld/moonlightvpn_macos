import SwiftUI
import MoonlightDesign
import MoonlightCore

enum Page: Hashable {
    case connect, subscription, apps, settings, importSubscription, logs, connections
}

struct RootView: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    /// Where AppKit put the traffic lights, measured rather than assumed.
    @State private var titleBarCentre: CGFloat = 14
    /// `ML_PAGE` opens the app straight onto a screen. It exists for
    /// `scripts/screenshots.sh`, which cannot click without accessibility
    /// permission, and is inert when unset.
    @State private var page: Page = { switch ProcessInfo.processInfo.environment["ML_PAGE"] ?? "" { case "sub": return .subscription; case "apps": return .apps; case "settings": return .settings; case "import": return .importSubscription; case "logs": return .logs; case "connections": return .connections; default: return .connect } }()

    /// The gap between the floating sidebar and the window's edges.
    static let gutter: CGFloat = 8

    /// The traffic lights sit on the bare window above the sidebar, so the
    /// sidebar starts just under their row. Sized from where AppKit actually
    /// drew them — their inset is not a documented constant.
    private var topInset: CGFloat { max(30, titleBarCentre * 2 + 4) }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
                .padding(.leading, Self.gutter)
                .padding(.bottom, Self.gutter)
            content
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settings.palette.bgDeep)
        // macOS reports the title bar as a top safe-area inset. Ignoring it puts
        // the content origin at the top of the window, so the sidebar can sit
        // directly under the traffic lights rather than a title bar's height
        // further down.
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(buttonCentre: $titleBarCentre))
        .environment(\.palette, settings.palette)
        .mlLocale(settings.locale)
        .preferredColorScheme(settings.theme == .dark ? .dark : .light)
        .frame(minWidth: 1_000, minHeight: 680)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // The connect screen is its own heading: the button and its status
            // say more than a title would.
            if page != .connect { PageHeader(page: page) }
            Group {
                switch page {
                case .connect: ConnectScreen(page: $page)
                case .subscription: SubscriptionScreen(page: $page)
                case .apps: AppsScreen(page: $page)
                case .settings: SettingsScreen(page: $page)
                case .importSubscription: ImportScreen(page: $page)
                case .logs: LogsScreen(page: $page)
                case .connections: ConnectionsScreen(page: $page)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, page == .connect ? 26 : 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No cross-page transition. Any of them — a crossfade, or `.identity`
        // on the removal — keeps the outgoing screen in the hierarchy for the
        // length of the animation, so the previous page shows *through* the new
        // one and reads as a blink. The screens carry their own entrance
        // instead, which starts only once the old one is already gone.
        .id(page)
    }
}

// MARK: - Sidebar

/// A floating panel inset from the window's edges — glass on macOS 26 and
/// later, a flat surface before it.
private struct Sidebar: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    private var collapsed: Bool { settings.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header

            NavItem(icon: .power, title: L.t(.navConnect, locale),
                    active: page == .connect, collapsed: collapsed) { page = .connect }
            NavItem(icon: .sparkles, title: L.t(.navSubscription, locale),
                    active: page == .subscription || page == .importSubscription,
                    collapsed: collapsed) { page = .subscription }
            NavItem(icon: .layers, title: L.t(.navApps, locale),
                    active: page == .apps, collapsed: collapsed) { page = .apps }
            NavItem(icon: .activity, title: L.t(.navConnections, locale),
                    active: page == .connections, collapsed: collapsed) { page = .connections }
            NavItem(icon: .settings, title: L.t(.navSettings, locale),
                    active: page == .settings || page == .logs,
                    collapsed: collapsed) { page = .settings }

            Spacer(minLength: 12)
            if collapsed { collapsedPlan } else { planCard }
        }
        .padding(10)
        .frame(width: collapsed ? 60 : 212)
        .frame(maxHeight: .infinity)
        .mlGlass(.rounded(18), fallback: palette.surface)
        .animation(Motion.slide, value: collapsed)
    }

    /// The header carries its own collapse control — the panel icon every
    /// sidebar on the platform uses, so it needs no explaining. Collapsed there
    /// is no room beside the logo, so it takes its own line under it.
    @ViewBuilder
    private var header: some View {
        if collapsed {
            VStack(spacing: 10) {
                LogoTile(size: 28, radius: 9)
                collapseButton
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 12)
        } else {
            HStack(spacing: 9) {
                LogoTile(size: 28, radius: 9)
                Text("moonlight")
                    .font(.mlDisplay(15, .bold))
                    .tracking(-0.025 * 15)
                    .foregroundStyle(palette.text)
                    .fixedSize()
                Spacer(minLength: 0)
                collapseButton
            }
            .padding(.leading, 4)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private var collapseButton: some View {
        HoverIconButton(icon: collapsed ? .panelLeftOpen : .panelLeftClose) {
            settings.sidebarCollapsed.toggle()
        }
        .help(L.t(collapsed ? .expandSidebar : .collapseSidebar, locale))
    }

    /// Collapsed there is no room for the card, but the plan still has to be
    /// glanceable — so it becomes the bar alone.
    private var collapsedPlan: some View {
        Button {
            page = .subscription
        } label: {
            VStack(spacing: 7) {
                IconView(.sparkles, size: 15)
                    .foregroundStyle(tunnel.info.isActive ? palette.accentInk : palette.danger)
                QuotaBar(used: tunnel.hasSubscription ? tunnel.info.usedFraction : 0, height: 3)
                    .frame(width: 26)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.text.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .pressCard()
        .help(planDays)
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

    private var planCard: some View {
        Button {
            page = .subscription
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Overline(text: L.t(.remainingCaps, locale))
                    Spacer(minLength: 6)
                    if tunnel.hasSubscription {
                        let tone = tunnel.info.isActive ? palette.accentInk : palette.danger
                        Circle().fill(tone).frame(width: 6, height: 6)
                        Text(L.t(tunnel.info.isActive ? .active : .expired, locale))
                            .font(.ml(11.5, .bold))
                            .foregroundStyle(tone)
                    }
                }
                Text(planDays)
                    .font(.mlDisplay(17))
                    .tracking(TypeScale.trackDisplay * 17)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 7)
                QuotaBar(used: tunnel.hasSubscription ? tunnel.info.usedFraction : 0, height: 4)
                    .padding(.top, 10)
                Text(quotaLine)
                    .font(.ml(11.5))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.text.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .pressCard()
    }
}

/// A sidebar row: a small glyph and a label, with a quiet wash behind the
/// current page. The accent is spent on the active glyph only — a lime slab per
/// row was the loudest thing in the window.
private struct NavItem: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    let title: String
    let active: Bool
    var collapsed = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconView(icon, size: 16)
                    .foregroundStyle(active ? palette.accentInk : palette.text2)
                if !collapsed {
                    Text(title)
                        .font(.ml(13.5, .semibold))
                        .foregroundStyle(active ? palette.text : palette.text2)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, collapsed ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .frame(height: 34)
            // The active wash is *not* animated. Animating it crossfaded the
            // outgoing item against the incoming one for a few frames — the
            // blink. A selection that moves instantly cannot smear; only the
            // hover wash, which never overlaps a selection, is worth easing.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.text.opacity(active ? 0.08 : (hovering ? 0.04 : 0)))
            )
            .contentShape(Rectangle())
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(hovering ? Motion.paint : nil, value: hovering)
        .help(collapsed ? title : "")
    }
}

/// A bare glyph that gains a wash on hover — for controls that should be
/// findable without being part of the composition.
struct HoverIconButton: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 16)
                .foregroundStyle(hovering ? palette.text : palette.textMuted)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.text.opacity(hovering ? 0.06 : 0))
                )
        }
        .pressIcon()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
    }
}

// MARK: - Page header

private struct PageHeader: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L.t(title, locale))
                .font(.mlDisplay(20))
                .tracking(TypeScale.trackDisplay * 20)
                .foregroundStyle(palette.text)
            Text(L.t(subtitle, locale))
                .font(.ml(TypeScale.meta))
                .foregroundStyle(palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 12)
    }

    private var title: L.Key {
        switch page {
        case .connect: return .titleConnect
        case .subscription: return .titleSubscription
        case .apps: return .titleApps
        case .settings: return .titleSettings
        case .importSubscription: return .titleImport
        case .logs: return .titleLogs
        case .connections: return .titleConnections
        }
    }

    private var subtitle: L.Key {
        switch page {
        case .connect: return .subtitleConnect
        case .subscription: return .subtitleSubscription
        case .apps: return .subtitleApps
        case .settings: return .subtitleSettings
        case .importSubscription: return .subtitleImport
        case .logs: return .subtitleLogs
        case .connections: return .subtitleConnections
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
