import SwiftUI
import AppKit

/// Liquid Glass where the system has it, a flat surface where it does not.
///
/// The glass is `NSGlassEffectView`, macOS 26, looked up by name at runtime
/// rather than referenced as a type. That is deliberate: the Command Line Tools
/// this project builds with ship the macOS 15 SDK, and CI's Xcode is no newer,
/// so neither `NSGlassEffectView` nor SwiftUI's `glassEffect` exists at compile
/// time. The class does exist at runtime on 26 and later whatever SDK the app
/// was linked against, and its public properties — `style`, `tintColor`,
/// `cornerRadius` — are plain Objective-C properties, so key-value coding
/// reaches them without the headers.
///
/// Glass is for the layer that floats over content: the sidebar, the connect
/// button, the status pill, small icon buttons. Content cards stay flat
/// surfaces, which is how the platform itself draws the line.
enum LiquidGlass {
    static let viewClass: NSView.Type? = NSClassFromString("NSGlassEffectView") as? NSView.Type
    /// Glass views inside one of these that touch are drawn as a single piece.
    static let containerClass: NSView.Type? =
        NSClassFromString("NSGlassEffectContainerView") as? NSView.Type

    static var isAvailable: Bool { viewClass != nil }
}

/// Sets a property the SDK has no header for, if the object has it.
///
/// Key-value coding raises on a key the object does not know, so a property
/// renamed in some later release would take the app down with it; checked
/// first, it costs only the effect.
private func setIfPresent(_ object: NSObject?, _ key: String, _ value: Any?) {
    guard let object else { return }
    let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
    guard object.responds(to: NSSelectorFromString(setter)) else { return }
    object.setValue(value, forKey: key)
}

/// The outline a glass surface takes.
enum GlassShape {
    case rounded(CGFloat)
    case capsule
    case circle

    /// `nil` means half the shorter side, which is what both a capsule and a
    /// circle are.
    var cornerRadius: CGFloat? {
        if case .rounded(let radius) = self { return radius }
        return nil
    }
}

/// A capsule's right half: flat on the left, round on the right — a tab
/// standing off the edge of whatever it is attached to.
struct TrailingHalfCapsule: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Sits the view on glass, or on `fallback` where there is none.
    ///
    /// `tint` colours the glass itself — use it for a state, never for
    /// decoration. The fallback is drawn in the same shape, so the layout and
    /// hit area are identical on every system.
    func mlGlass(_ shape: GlassShape, tint: Color? = nil, fallback: Color) -> some View {
        background(GlassBackground(shape: shape, tint: tint, fallback: fallback))
    }
}

private struct GlassBackground: View {
    let shape: GlassShape
    let tint: Color?
    let fallback: Color

    var body: some View {
        if LiquidGlass.isAvailable {
            GlassBackdrop(shape: shape, tint: tint.map { NSColor($0) })
        } else {
            switch shape {
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fallback)
            case .capsule:
                Capsule().fill(fallback)
            case .circle:
                Circle().fill(fallback)
            }
        }
    }
}

private struct GlassBackdrop: NSViewRepresentable {
    let shape: GlassShape
    let tint: NSColor?

    func makeNSView(context: Context) -> GlassHost {
        GlassHost()
    }

    func updateNSView(_ host: GlassHost, context: Context) {
        host.shape = shape
        host.tint = tint
    }
}

/// Holds the glass view and keeps it out of hit testing.
///
/// An `NSView` inside a SwiftUI button's label otherwise takes the click for
/// itself and the button never fires. Returning `nil` from `hitTest` for the
/// whole subtree lets the event fall through to SwiftUI, which is what owns
/// every control drawn on the glass.
final class GlassHost: NSView {
    private let glass: NSView?

    var shape: GlassShape = .capsule { didSet { needsLayout = true } }
    var tint: NSColor? { didSet { if tint != oldValue { setIfPresent(glass, "tintColor", tint) } } }

    override init(frame: NSRect) {
        glass = LiquidGlass.viewClass?.init(frame: frame)
        super.init(frame: frame)
        if let glass {
            glass.autoresizingMask = [.width, .height]
            glass.frame = bounds
            addSubview(glass)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        setIfPresent(glass, "cornerRadius",
                     shape.cornerRadius ?? min(bounds.width, bounds.height) / 2)
    }
}

// MARK: - Panel with a tab

extension View {
    /// Glass for a panel with a half-circle tab standing off the middle of its
    /// trailing edge. The tab's area lies outside the view's own frame.
    ///
    /// On 26 the panel and a circle centred on its edge sit in one glass
    /// container, which draws touching glass as a single piece — so the tab is
    /// a bump grown out of the panel, with the platform's own fillets where
    /// they meet and one continuous rim. Clipping a separate glass view to a
    /// half shape instead left its square rim showing as a notch.
    func mlGlassPanel(radius: CGFloat, tab: CGFloat, fallback: Color) -> some View {
        background(PanelWithTabBackground(radius: radius, tab: tab, fallback: fallback))
    }
}

private struct PanelWithTabBackground: View {
    let radius: CGFloat
    /// How far the tab stands out; it is twice as tall.
    let tab: CGFloat
    let fallback: Color

    var body: some View {
        if LiquidGlass.isAvailable, LiquidGlass.containerClass != nil {
            PanelWithTabBackdrop(radius: radius, tab: tab)
                .padding(.trailing, -tab)
        } else {
            // Before 26: the same outline, drawn flat — one fill, so the seam
            // between panel and tab does not show.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fallback)
                .overlay(alignment: .trailing) {
                    TrailingHalfCapsule()
                        .fill(fallback)
                        .frame(width: tab, height: tab * 2)
                        .offset(x: tab)
                }
        }
    }
}

private struct PanelWithTabBackdrop: NSViewRepresentable {
    let radius: CGFloat
    let tab: CGFloat

    func makeNSView(context: Context) -> PanelWithTabHost { PanelWithTabHost() }

    func updateNSView(_ host: PanelWithTabHost, context: Context) {
        host.radius = radius
        host.tab = tab
    }
}

final class PanelWithTabHost: NSView {
    private let container: NSView?
    private let content = NSView()
    private let panel: NSView?
    private let knob: NSView?

    var radius: CGFloat = 18 { didSet { if radius != oldValue { needsLayout = true } } }
    var tab: CGFloat = 18 { didSet { if tab != oldValue { needsLayout = true } } }

    override init(frame: NSRect) {
        container = LiquidGlass.containerClass?.init(frame: frame)
        panel = LiquidGlass.viewClass?.init(frame: frame)
        knob = LiquidGlass.viewClass?.init(frame: frame)
        super.init(frame: frame)
        guard let container, let panel, let knob else { return }
        content.addSubview(panel)
        content.addSubview(knob)
        setIfPresent(container, "contentView", content)
        if content.superview == nil { container.addSubview(content) }
        addSubview(container)
    }

    required init?(coder: NSCoder) { nil }

    /// Clicks belong to the SwiftUI controls drawn on the glass.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        container?.frame = bounds
        content.frame = bounds
        // This view runs `tab` past the panel's trailing edge to make room.
        let panelFrame = NSRect(x: 0, y: 0, width: max(0, bounds.width - tab), height: bounds.height)
        panel?.frame = panelFrame
        knob?.frame = NSRect(x: panelFrame.maxX - tab, y: panelFrame.midY - tab,
                             width: tab * 2, height: tab * 2)
        setIfPresent(panel, "cornerRadius", radius)
        setIfPresent(knob, "cornerRadius", tab)
    }
}
