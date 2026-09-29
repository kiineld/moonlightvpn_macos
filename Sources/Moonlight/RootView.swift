import SwiftUI
import MoonlightDesign
import MoonlightCore

enum Page: Hashable {
    case connect, subscription, apps, settings, importSubscription, logs, connections
}

struct RootView: View {
    // Not the tunnel: nothing here reads it, and observing it re-ran the whole
    // window — sidebar, page and all — on every change it published.
    @EnvironmentObject var settings: AppSettings
    /// Handed down, not observed: its download ticks would re-run the whole
    /// window. The banner and Settings observe it themselves.
    let updater: Updater
    /// Where AppKit put the traffic lights, measured rather than assumed.
    @State private var titleBarCentre: CGFloat = 14
    /// `ML_PAGE` opens the app straight onto a screen. It exists for
    /// `scripts/screenshots.sh`, which cannot click without accessibility
    /// permission, and is inert when unset.
    @State private var page: Page = { switch ProcessInfo.processInfo.environment["ML_PAGE"] ?? "" { case "sub": return .subscription; case "apps": return .apps; case "settings": return .settings; case "import": return .importSubscription; case "logs": return .logs; case "connections": return .connections; default: return .connect } }()

    /// The gap between the floating sidebar and the window's edges.
    static let gutter: CGFloat = 8
    /// The space under every page, down to the window's bottom edge.
    static let pageBottomInset: CGFloat = 24
    /// The margin either side of every page.
    static let pageGutter: CGFloat = 28
    /// The space between a page's header and its content.
    static let pageTopInset: CGFloat = 18

    /// The traffic lights sit on the bare window above the sidebar, so the
    /// sidebar starts just under their row. Sized from where AppKit actually
    /// drew them — their inset is not a documented constant.
    private var topInset: CGFloat { max(30, titleBarCentre * 2 + 4) }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
                .padding(.leading, Self.gutter)
                .padding(.bottom, Self.gutter)
                .zIndex(1)
            // Outside the page's own identity, so it stays put — and stays
            // dismissed — as the pages change under it.
            content
                .overlay(alignment: .topTrailing) {
                    UpdateBanner(updater: updater, page: $page)
                        .padding(.trailing, Self.pageGutter)
                        .padding(.top, 10)
                }
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ambient(palette: settings.palette, dark: settings.theme == .dark))
        // macOS reports the title bar as a top safe-area inset. Ignoring it puts
        // the content origin at the top of the window, so the sidebar can sit
        // directly under the traffic lights rather than a title bar's height
        // further down.
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(buttonCentre: $titleBarCentre))
        .environmentObject(updater)
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
            .padding(.horizontal, Self.pageGutter)
            .padding(.top, page == .connect ? 26 : Self.pageTopInset)
            .padding(.bottom, Self.pageBottomInset)
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
        VStack(alignment: .leading, spacing: 6) {
            header
            navigation
            Spacer(minLength: 12)
            if collapsed { collapsedPlan } else { planCard }
        }
        .padding(10)
        .frame(width: collapsed ? 64 : 216)
        .frame(maxHeight: .infinity)
        // One surface, tab included — see `SidebarShape`.
        .mlSoftGlass(SidebarShape(bump: CollapseTab.width, reach: CollapseTab.reach),
                     wash: palette.surface.opacity(0.6), shadow: true)
        .overlay(alignment: .trailing) {
            CollapseTab(collapsed: collapsed) {
                // Animated at the source, not on the sidebar: an `.animation`
                // attached here moved only the sidebar, and the page beside it
                // jumped to its new width while the sidebar was still sliding.
                // One transaction moves everything that depends on the width,
                // on one curve — a spring without overshoot, because the whole
                // page rides on it.
                withAnimation(Self.resize) { settings.sidebarCollapsed.toggle() }
            }
            .help(L.t(collapsed ? .expandSidebar : .collapseSidebar, locale))
            .offset(x: CollapseTab.width)
        }
    }

    private static let resize = Motion.standard
    private static let navSpacing: CGFloat = 6

    private static let pages: [(icon: Icon, title: L.Key, page: Page)] = [
        (.power, .navConnect, .connect),
        (.sparkles, .navSubscription, .subscription),
        (.layers, .navApps, .apps),
        (.activity, .navConnections, .connections),
        (.settings, .navSettings, .settings),
    ]

    /// The row that owns the current page. Import belongs to the subscription,
    /// and the log to settings, which is where each is opened from.
    private var selected: Int {
        switch page {
        case .connect: return 0
        case .subscription, .importSubscription: return 1
        case .apps: return 2
        case .connections: return 3
        case .settings, .logs: return 4
        }
    }

    private var navigation: some View {
        VStack(spacing: Self.navSpacing) {
            ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, item in
                NavItem(icon: item.icon, title: L.t(item.title, locale),
                        active: index == selected, collapsed: collapsed) { page = item.page }
            }
        }
        .background(
            LiquidSelection(index: selected, count: Self.pages.count,
                            row: NavItem.height, spacing: Self.navSpacing)
        )
    }

    /// The wordmark, or the logo alone when collapsed. The collapse control is
    /// the tab on the sidebar's edge, not a button in here.
    @ViewBuilder
    private var header: some View {
        if collapsed {
            LogoTile(size: 28, radius: 9)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 14)
        } else {
            HStack(spacing: 9) {
                LogoTile(size: 28, radius: 9)
                Text("moonlight")
                    .font(.mlWordmark(15))
                    .tracking(-0.025 * 15)
                    .foregroundStyle(palette.text)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
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
            .mlSoftGlass(RoundedRectangle(cornerRadius: 12, style: .continuous),
                         wash: palette.text.opacity(0.04))
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
            .mlSoftGlass(RoundedRectangle(cornerRadius: 12, style: .continuous),
                         wash: palette.text.opacity(0.04))
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

    static let height: CGFloat = 38

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
            .padding(.horizontal, collapsed ? 0 : 12)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .frame(height: Self.height)
            // The selection is not drawn here — it is the one piece of glass
            // behind every row (`LiquidSelection`), which flows between them.
            // Only the hover wash is the row's own.
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.text.opacity(hovering && !active ? 0.05 : 0))
            }
            .contentShape(Rectangle())
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
        .animation(Motion.paint, value: active)
        .help(collapsed ? title : "")
    }
}

/// The sidebar's selection: one piece of glass behind the rows that flows from
/// row to row.
///
/// Its two edges move on different springs. The edge heading for the new row
/// leads and the other follows, so on the way the glass stretches out towards
/// where it is going, thins a little as it does, and gathers itself up when it
/// arrives — a drop of liquid rather than a tile sliding. It used to be a glass
/// background on the active row, which could only jump: animating that
/// crossfaded two pieces of glass and read as a blink.
///
/// Driven by a timeline rather than by `withAnimation`. Two edges changed in
/// two transactions with two curves still came out on one: SwiftUI animated
/// the glass's frame as a whole, and it slid as a rigid tile. Here each edge
/// is worked out from its own spring on every frame, and only while it moves.
private struct LiquidSelection: View {
    @Environment(\.palette) private var palette
    let index: Int
    let count: Int
    let row: CGFloat
    let spacing: CGFloat

    @State private var travel: Travel
    /// Whether the timeline ticks. Off at rest, so a still sidebar costs
    /// nothing.
    @State private var moving = false

    /// Long enough for the slower spring to have settled.
    private static let settle = 0.8

    init(index: Int, count: Int, row: CGFloat, spacing: CGFloat) {
        self.index = index
        self.count = count
        self.row = row
        self.spacing = spacing
        let edges = Edges(top: CGFloat(index) * (row + spacing), row: row)
        _travel = State(initialValue: Travel(from: edges, to: edges, start: .distantPast))
    }

    private var column: CGFloat { CGFloat(count) * row + CGFloat(count - 1) * spacing }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !moving)) { context in
            let edges = travel.edges(at: context.date)
            // Stretched, it thins a little, as a drop does.
            let stretch = max(0, edges.bottom - edges.top - row)
            Color.clear
                .mlSoftGlass(RoundedRectangle(cornerRadius: 12, style: .continuous),
                             wash: palette.text.opacity(0.07))
                .padding(.horizontal, min(3, stretch * 0.04))
                .padding(.top, edges.top)
                .padding(.bottom, column - edges.bottom)
        }
        .onChange(of: index) { index in
            // From wherever it is now, so a click mid-flight turns it round
            // rather than making it jump.
            let now = Date()
            travel = Travel(from: travel.edges(at: now),
                            to: Edges(top: CGFloat(index) * (row + spacing), row: row),
                            start: now)
            moving = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) {
                if travel.start == now { moving = false }
            }
        }
    }

    private struct Edges {
        var top: CGFloat
        var bottom: CGFloat

        init(top: CGFloat, bottom: CGFloat) {
            self.top = top
            self.bottom = bottom
        }

        init(top: CGFloat, row: CGFloat) {
            self.init(top: top, bottom: top + row)
        }
    }

    private struct Travel {
        var from: Edges
        var to: Edges
        var start: Date

        /// The edge nearer the destination leads; the other follows.
        func edges(at date: Date) -> Edges {
            let t = date.timeIntervalSince(start)
            let lead = CGFloat(Motion.spring(t, response: Motion.liquidLead))
            let trail = CGFloat(Motion.spring(t, response: Motion.liquidTrail))
            let down = to.top >= from.top
            return Edges(top: from.top + (to.top - from.top) * (down ? trail : lead),
                         bottom: from.bottom + (to.bottom - from.bottom) * (down ? lead : trail))
        }
    }
}

/// The collapse control: the swell in the sidebar's edge, halfway down.
///
/// It has no surface of its own — the swell is part of the sidebar's outline
/// (`SidebarShape`), so panel and tab are one element. The chevron points the
/// way a click will move the sidebar — left to collapse it, right to open it —
/// and turns between the two rather than being swapped for a different glyph,
/// which read as the arrow jumping.
private struct CollapseTab: View {
    @Environment(\.palette) private var palette
    let collapsed: Bool
    let action: () -> Void

    /// How far the swell stands out past the panel's edge.
    static let width: CGFloat = 16
    /// Half the height of the edge that swells.
    static let reach: CGFloat = 30

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            // The frame straddles the edge; the glyph sits in the swell's
            // visual centre, a little in from its tip.
            IconView(.chevronRight, size: 12, strokeWidth: 2.6)
                .rotationEffect(.degrees(collapsed ? 0 : 180))
                .foregroundStyle(hovering ? palette.accentInk : palette.textMuted)
                .offset(x: Self.width * 0.4)
                .frame(width: Self.width * 2, height: Self.reach * 1.6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 1))
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
    }
}

/// The sidebar's outline: a rounded panel whose trailing edge swells out,
/// halfway down, into the collapse tab.
///
/// One path, so the tab is the sidebar and not a second piece laid against it.
/// The swell leaves the edge along the edge's own tangent and meets it again
/// the same way, so there is no corner or seam where they join — two curves
/// out to a rounded tip and two back.
struct SidebarShape: Shape {
    var radius: CGFloat = 18
    /// How far the swell stands out past the edge.
    var bump: CGFloat
    /// Half the height of the edge that swells.
    var reach: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        let edge = rect.maxX
        let mid = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: edge - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: edge, y: rect.minY),
                    tangent2End: CGPoint(x: edge, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: edge, y: mid - reach))
        path.addCurve(to: CGPoint(x: edge + bump, y: mid),
                      control1: CGPoint(x: edge, y: mid - reach * 0.42),
                      control2: CGPoint(x: edge + bump, y: mid - reach * 0.58))
        path.addCurve(to: CGPoint(x: edge, y: mid + reach),
                      control1: CGPoint(x: edge + bump, y: mid + reach * 0.58),
                      control2: CGPoint(x: edge, y: mid + reach * 0.42))
        path.addLine(to: CGPoint(x: edge, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: edge, y: rect.maxY),
                    tangent2End: CGPoint(x: edge - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

/// The canvas: the desktop, blurred, under `bgDeep` at three quarters — black,
/// or white in the light theme — with light falling in from two corners.
///
/// Liquid Glass over a flat colour has nothing to refract and draws as a grey
/// slab with no edge, which is how the whole interface looked on a solid black
/// canvas. Over the blurred desktop it has real light and colour to bend, as
/// it does in the system's own windows, while the window still reads as black.
private struct Ambient: View {
    let palette: Palette
    let dark: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BehindWindowBlur()
                palette.bgDeep.opacity(0.76)
                glow(dark ? 0.10 : 0.06, diameter: 900)
                    .position(x: geometry.size.width - 60, y: 0)
                glow(dark ? 0.06 : 0.04, diameter: 760)
                    .position(x: 140, y: geometry.size.height + 80)
            }
        }
        .allowsHitTesting(false)
    }

    private func glow(_ strength: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [palette.text.opacity(strength), palette.text.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

/// The desktop behind the window, blurred by the system.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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

/// The logo tile from `assets/logo-tile.svg`, redrawn as vectors so it paints
/// crisply at every size — lime in both themes, since it is the brand.
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
            let ink = GraphicsContext.Shading.color(palette.brandInk)
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
        // The lime is the brand, and this tile is the one place it appears.
        .background(palette.brand)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
