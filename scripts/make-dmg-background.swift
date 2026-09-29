// Renders the installer window's backdrop.
//
//     swift scripts/make-dmg-background.swift <out.png> [<out@2x.png>]
//
// Drawn rather than shipped as an asset so it stays in step with the palette,
// and so the repository carries no binary that has to be re-exported by hand.
//
// Each file is an exact bitmap: 660x420 pixels at 72 dpi, and 1320x840 at 144
// dpi for the @2x. Both measure 660x420 *points*, the window's size. This used
// to draw into an `NSImage` with `lockFocus`, which backs the image at the
// screen's scale — on a Retina Mac that doubled the already-doubled canvas into
// a 2640x1680 file claiming 1320x840 points, so Finder showed it at twice the
// window's size and only its top-left quarter was visible. dmgbuild finds the
// @2x beside the 1x and combines the pair into one HiDPI TIFF.
import AppKit
import CoreText

let width = 660.0, height = 420.0

// Palette — light mode, matching the app.
let cream = NSColor(srgbRed: 0.949, green: 0.953, blue: 0.929, alpha: 1)   // #F2F3ED
let deep = NSColor(srgbRed: 0.063, green: 0.094, blue: 0.157, alpha: 1)    // #101828
let accent = NSColor(srgbRed: 1.0, green: 0.878, blue: 0.471, alpha: 1)    // #FFE078
let muted = NSColor(srgbRed: 0.400, green: 0.439, blue: 0.522, alpha: 1)   // #667085

// The app's own display face, when the build has fetched it.
for name in ["Unbounded", "Onest"] {
    let url = URL(fileURLWithPath: "Resources/fonts/\(name).ttf")
    if FileManager.default.fileExists(atPath: url.path) {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// The family at a weight. `NSFont(name:)` resolves the variable TTF to its
/// default instance whatever weight is wanted, so the member is picked on the
/// font manager's 0–15 weight scale instead.
func font(_ family: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let managerWeight: Int
    switch weight {
    case .medium: managerWeight = 6
    case .semibold: managerWeight = 8
    case .bold: managerWeight = 9
    case .heavy: managerWeight = 11
    default: managerWeight = 5
    }
    return NSFontManager.shared.font(withFamily: family, traits: [],
                                     weight: managerWeight, size: size)
        ?? .systemFont(ofSize: size, weight: weight)
}

/// Draws the backdrop in points; the caller has already scaled the context.
func drawBackdrop(_ context: CGContext) {
    // Ground.
    cream.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // A soft accent wash bleeding off the bottom-left, as the app's cards do.
    context.saveGState()
    context.setFillColor(accent.withAlphaComponent(0.30).cgColor)
    context.fillEllipse(in: CGRect(x: -170, y: -230, width: 460, height: 460))
    context.setFillColor(accent.withAlphaComponent(0.18).cgColor)
    context.fillEllipse(in: CGRect(x: width - 190, y: height - 150, width: 340, height: 340))
    context.restoreGState()

    func draw(_ text: String, _ nsFont: NSFont, _ color: NSColor, centreX: Double, y: Double) {
        let attributes: [NSAttributedString.Key: Any] = [.font: nsFont, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: centreX - size.width / 2, y: y))
    }

    // AppKit's origin is bottom-left; the numbers below read top-down.
    draw("moonlight", font("Unbounded", 27, .bold), deep, centreX: width / 2, y: height - 78)
    draw("Перетащите moonlight в папку «Программы»",
         font("Onest", 14, .medium), muted, centreX: width / 2, y: height - 112)
    draw("Drag the app into your Applications folder",
         font("Onest", 12, .regular), muted.withAlphaComponent(0.75),
         centreX: width / 2, y: height - 133)

    // The arrow between the two icons, on the row scripts/dmg-settings.py
    // places them on: y = 250 from the top.
    // Shaft and head are drawn opaque inside one transparency layer, which is
    // then faded as a whole — faded separately, the two overlapped and the
    // join showed as a darker band.
    let arrowY = height - 250.0
    context.saveGState()
    context.setAlpha(0.35)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    deep.setStroke()
    deep.setFill()

    let path = NSBezierPath()
    path.move(to: NSPoint(x: width / 2 - 46, y: arrowY))
    path.line(to: NSPoint(x: width / 2 + 30, y: arrowY))
    path.lineWidth = 3
    path.lineCapStyle = .round
    path.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: width / 2 + 46, y: arrowY))
    head.line(to: NSPoint(x: width / 2 + 26, y: arrowY + 11))
    head.line(to: NSPoint(x: width / 2 + 26, y: arrowY - 11))
    head.close()
    head.fill()

    context.endTransparencyLayer()
    context.restoreGState()
}

func render(scale: Double) -> Data? {
    // Tagged sRGB, the space the palette's values are written in, so the
    // cream behind the icons is the app's own #F2F3ED.
    guard let untagged = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let rep = untagged.retagging(with: .sRGB),
       let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    // Setting the size in points is what gives the PNG its dpi: 72 for the 1x,
    // 144 for the @2x.
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: scale, y: scale)
    drawBackdrop(graphics.cgContext)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let arguments = CommandLine.arguments.dropFirst()
let outputs = [
    (arguments.first ?? "build/dmg-background.png", 1.0),
] + (arguments.dropFirst().first.map { [($0, 2.0)] } ?? [])

for (path, scale) in outputs {
    guard let png = render(scale: scale) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: path))
    print("▸ \(path)")
}
