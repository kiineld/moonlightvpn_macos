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
            for glyph in Self.parsed[icon] ?? [] {
                context.stroke(glyph.path(in: rect), with: .foregroundColor(d: ()), style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Every glyph's path data, parsed once. The canvas redraws whenever the
    /// view around it re-renders, and parsing the `d` strings there meant a
    /// server list re-parsed a dozen glyphs per row on every tick.
    private static let parsed: [Icon: [SVGPath]] = Dictionary(
        uniqueKeysWithValues: Icon.allCases.map { ($0, $0.paths.map(SVGPath.init)) }
    )
}

private extension GraphicsContext.Shading {
    /// `Canvas` resolves `.foreground` against the view's foreground style, which
    /// is what lets an icon inherit `.foregroundStyle(…)` from its container the
    /// way `currentColor` does in the source SVG.
    static func foregroundColor(d: Void) -> GraphicsContext.Shading { .foreground }
}
