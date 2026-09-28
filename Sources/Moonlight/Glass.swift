import SwiftUI
import MoonlightDesign

/// Apple's Liquid Glass on every surface — cards, rows, pills, buttons, the
/// sidebar, the tray — through SwiftUI's own `glassEffect` on macOS 26 and
/// later; a flat surface with a hairline before it.
///
/// The app used to reach for `NSGlassEffectView` by name at runtime, because
/// it built against the macOS 15 SDK, where neither that class nor SwiftUI's
/// glass exists. Hosted inside SwiftUI that view drew as a flat grey slab —
/// no lensing, no lit edge — and it could not follow an animating frame, so
/// the sidebar needed a hand-drawn imitation beside it. Built against the
/// macOS 26 SDK, the real thing is available: one glass, every shape, moving
/// with the layout.
///
/// The interface is monochrome, so the glass is neutral. A state — the white
/// primary button, a selection, the red of "close all" — is a tint on the
/// glass, never a colour painted over it.
enum GlassShape {
    case rounded(CGFloat)
    case capsule
    case circle
}

extension View {
    /// Sits the view on glass in `shape`. `tint` marks a state; `fallback` is
    /// the surface drawn where the system has no glass.
    func mlGlass(_ shape: GlassShape, tint: Color? = nil, fallback: Color) -> some View {
        background(GlassSurface(shape: SurfaceOutline(shape: shape), tint: tint, fallback: fallback))
    }

    /// The same glass for an outline of any shape — the sidebar with its tab, a
    /// selection that narrows with it. `wash` tints it; `shadow` marks a panel
    /// that floats over the canvas, which takes a hairline where there is no
    /// glass.
    func mlSoftGlass<S: Shape>(_ shape: S, wash: Color, shadow: Bool = false) -> some View {
        background(GlassSurface(shape: shape, tint: wash, fallback: .clear, outlined: shadow))
    }
}

private struct GlassSurface<S: Shape>: View {
    @Environment(\.palette) private var palette
    let shape: S
    let tint: Color?
    let fallback: Color
    /// Whether the flat fallback draws an edge. A plain surface does; a tinted
    /// one is its own edge.
    var outlined: Bool?

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(Glass.regular.tint(tint), in: shape)
        } else {
            flat
        }
        #else
        flat
        #endif
    }

    private var flat: some View {
        shape.fill(tint ?? fallback)
            .overlay {
                if outlined ?? (tint == nil) {
                    shape.stroke(palette.hairline, lineWidth: 1)
                }
            }
    }
}

/// A ``GlassShape`` as a `Shape`.
struct SurfaceOutline: Shape {
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
