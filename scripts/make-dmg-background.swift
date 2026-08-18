// Renders the installer window's backdrop.
//
//     swift scripts/make-dmg-background.swift <out.png> [<out@2x.png>]
//
// Drawn rather than shipped as an asset so it stays in step with the palette,
// and so the repository carries no binary that has to be re-exported by hand.
import AppKit
import CoreText

let width = 660.0, height = 420.0
let scale = 2.0

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

func font(_ family: String, _ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont(name: family, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

let image = NSImage(size: NSSize(width: width * scale, height: height * scale))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
context.scaleBy(x: scale, y: scale)

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
draw("moonlight", font("Unbounded", 27, .heavy), deep, centreX: width / 2, y: height - 78)
draw("Перетащите Moonlight в папку «Программы»",
     font("Onest", 14, .medium), muted, centreX: width / 2, y: height - 112)
draw("Drag the app into your Applications folder",
     font("Onest", 12, .regular), muted.withAlphaComponent(0.75),
     centreX: width / 2, y: height - 133)

// The arrow between the two icons, at the height appdmg places them.
// Matches the icon row appdmg lays out at y = 250 from the top.
let arrowY = height - 250.0
let path = NSBezierPath()
path.move(to: NSPoint(x: width / 2 - 46, y: arrowY))
path.line(to: NSPoint(x: width / 2 + 30, y: arrowY))
path.lineWidth = 3
path.lineCapStyle = .round
deep.withAlphaComponent(0.35).setStroke()
path.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: width / 2 + 46, y: arrowY))
head.line(to: NSPoint(x: width / 2 + 26, y: arrowY + 11))
head.line(to: NSPoint(x: width / 2 + 26, y: arrowY - 11))
head.close()
deep.withAlphaComponent(0.35).setFill()
head.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg-background.png"
try png.write(to: URL(fileURLWithPath: out))
print("▸ \(out)")
