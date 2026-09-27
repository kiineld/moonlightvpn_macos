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

    static var isAvailable: Bool { viewClass != nil }
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
            GlassBackdrop(cornerRadius: shape.cornerRadius, tint: tint.map { NSColor($0) })
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
    let cornerRadius: CGFloat?
    let tint: NSColor?

    func makeNSView(context: Context) -> GlassHost {
        GlassHost()
    }

    func updateNSView(_ host: GlassHost, context: Context) {
        host.cornerRadius = cornerRadius
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

    var cornerRadius: CGFloat? { didSet { if cornerRadius != oldValue { needsLayout = true } } }
    var tint: NSColor? { didSet { if tint != oldValue { apply("tintColor", tint) } } }

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
        let radius = cornerRadius ?? min(bounds.width, bounds.height) / 2
        apply("cornerRadius", radius)
    }

    /// Guarded because key-value coding raises on a key the object does not
    /// have — a renamed property in some later release should cost the effect,
    /// not the app.
    private func apply(_ key: String, _ value: Any?) {
        guard let glass else { return }
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        guard glass.responds(to: NSSelectorFromString(setter)) else { return }
        glass.setValue(value, forKey: key)
    }
}
