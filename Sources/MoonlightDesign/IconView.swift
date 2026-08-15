import SwiftUI

/// Renders a lucide glyph at its drawn geometry.
///
/// Stroke, cap and join match lucide's own SVG attributes (`round`/`round`),
/// and the path is never filled — that is what keeps these identical to the
/// design rather than merely similar.
public struct IconView: View {
    let icon: Icon
    let size: CGFloat
    let strokeWidth: CGFloat

    public init(_ icon: Icon, size: CGFloat = 20, strokeWidth: CGFloat = 2) {
        self.icon = icon
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            // lucide's stroke-width is expressed in the 24×24 viewBox, so it
            // scales with the glyph rather than staying a fixed device width.
            let scaled = strokeWidth * min(canvasSize.width, canvasSize.height) / 24
            let style = StrokeStyle(lineWidth: scaled, lineCap: .round, lineJoin: .round)
            for d in icon.paths {
                context.stroke(SVGPath(d).path(in: rect), with: .foregroundColor(d: ()), style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension GraphicsContext.Shading {
    /// `Canvas` resolves `.foreground` against the view's foreground style, which
    /// is what lets an icon inherit `.foregroundStyle(…)` from its container the
    /// way `currentColor` does in the source SVG.
    static func foregroundColor(d: Void) -> GraphicsContext.Shading { .foreground }
}
