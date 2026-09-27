import SwiftUI
import AppKit

/// Liquid Glass where the system has it, a flat surface where it does not.
///
/// The glass is `NSGlassEffectView`, macOS 26, looked up by name at runtime
/// rather than referenced as a type. That is deliberate: the Command Line Tools
/// this project builds with ship the macOS 15 SDK, and CI's Xcode is no newer,
/// so neither `NSGlassEffectView` nor SwiftUI's `glassEffect` exists at compile
/// time. The class does exist at runtime on 26 and later whatever SDK the app
/// was linked against, and its public properties — `style` and
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

extension View {
    /// Sits the view on glass, or on `fallback` where there is none.
    ///
    /// `tint` colours the surface — use it for a state, never for decoration.
    /// The fallback is drawn in the same shape, so the layout and hit area are
    /// identical on every system.
    func mlGlass(_ shape: GlassShape, tint: Color? = nil, fallback: Color) -> some View {
        background(GlassBackground(shape: shape, tint: tint, fallback: fallback))
    }
}

private struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let shape: GlassShape
    let tint: Color?
    let fallback: Color

    var body: some View {
        if LiquidGlass.isAvailable {
            // The tint is painted over plain glass rather than handed to the
            // glass. macOS mutes tinted glass in a window that is not focused,
            // so the lime plan card went grey behind its dark type — unreadable
            // every time another window was in front.
            GlassBackdrop(shape: shape)
                .overlay {
                    if let tint {
                        outline.fill(tint.opacity(0.92))
                            .overlay(outline.stroke(rim, lineWidth: 1))
                    }
                }
        } else {
            outline.fill(fallback)
        }
    }

    private var outline: GlassOutline { GlassOutline(shape: shape) }

    /// The lit edge the glass would draw, which the paint above now covers.
    private var rim: LinearGradient {
        let dark = colorScheme == .dark
        return LinearGradient(
            colors: [.white.opacity(dark ? 0.35 : 0.7), .white.opacity(0.05),
                     .white.opacity(dark ? 0.15 : 0.4)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// A ``GlassShape`` as a SwiftUI `Shape`, for what is painted on the glass.
private struct GlassOutline: Shape {
    let shape: GlassShape

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .rounded(let radius):
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }
}

private struct GlassBackdrop: NSViewRepresentable {
    let shape: GlassShape

    func makeNSView(context: Context) -> GlassHost {
        GlassHost()
    }

    func updateNSView(_ host: GlassHost, context: Context) {
        host.shape = shape
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

// MARK: - Glass for shapes that move

extension View {
    /// Glass drawn by SwiftUI itself, for surfaces whose size animates.
    ///
    /// `NSGlassEffectView` is an AppKit view, and SwiftUI does not animate the
    /// frame of a hosted AppKit view: while the content slid, the glass under it
    /// jumped straight to its final size. It also takes only a rounded
    /// rectangle, so a panel with a tab grown out of its edge had to be two
    /// pieces with a seam between them. This is one `Shape`, so it can be any
    /// outline and it moves with the layout, frame by frame: the platform's
    /// blur material, a wash of the Moonlight surface, and a rim lit from the top.
    func mlSoftGlass<S: Shape>(_ shape: S, wash: Color, shadow: Bool = false) -> some View {
        background(SoftGlass(shape: shape, wash: wash, shadow: shadow))
    }
}

private struct SoftGlass<S: Shape>: View {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let wash: Color
    let shadow: Bool

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(wash))
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(dark ? 0.20 : 0.85),
                                 .white.opacity(dark ? 0.04 : 0.25),
                                 .white.opacity(dark ? 0.09 : 0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(shadow ? (dark ? 0.35 : 0.10) : 0), radius: 18, y: 6)
    }
}
