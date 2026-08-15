import SwiftUI

/// A parser for the SVG path `d` grammar, sufficient for the whole lucide set.
///
/// `Icons.swift` carries lucide's geometry as `d` strings — including the icons
/// lucide draws with `<circle>`/`<rect>`/`<line>`, which the generator rewrites
/// into path commands. That leaves exactly one thing to parse here.
///
/// Everything in the grammar is supported, absolute and relative: `M L H V C S
/// Q T A Z`. The smooth variants (`S`/`T`) need the previous control point, and
/// arcs (`A`) are converted to cubic segments, so this is not a subset parser —
/// getting either wrong shows up as a visibly wrong glyph rather than an error.
public struct SVGPath {
    public let commands: [Command]

    public enum Command: Equatable {
        case move(CGPoint)
        case line(CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    public init(_ d: String) {
        var scanner = SVGPathScanner(d)
        commands = scanner.parse()
    }

    /// The path in lucide's own 24×24 space, scaled to `size` and stroked by the
    /// caller. Lucide icons are never filled.
    public func path(in rect: CGRect, viewBox: CGFloat = 24) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let dx = rect.minX + (rect.width - viewBox * scale) / 2
        let dy = rect.minY + (rect.height - viewBox * scale) / 2
        func t(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale + dx, y: p.y * scale + dy)
        }

        var path = Path()
        for command in commands {
            switch command {
            case .move(let p): path.move(to: t(p))
            case .line(let p): path.addLine(to: t(p))
            case .curve(let to, let c1, let c2):
                path.addCurve(to: t(to), control1: t(c1), control2: t(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

private struct SVGPathScanner {
    private let chars: [Character]
    private var i = 0

    private var current = CGPoint.zero
    private var start = CGPoint.zero
    /// Last cubic control point, for `S`. Nil resets the reflection to `current`.
    private var lastCubicControl: CGPoint?
    /// Last quadratic control point, for `T`.
    private var lastQuadControl: CGPoint?
    private var out: [SVGPath.Command] = []

    init(_ d: String) { chars = Array(d) }

    mutating func parse() -> [SVGPath.Command] {
        var command: Character = " "
        while true {
            skipSeparators()
            guard i < chars.count else { break }

            if chars[i].isLetter {
                command = chars[i]
                i += 1
            } else if command == " " {
                // Numbers before any command letter: malformed, give up rather
                // than guess at an implied command.
                break
            } else if command == "M" {
                command = "L"       // repeated moveto pairs are implicit linetos
            } else if command == "m" {
                command = "l"
            }
            guard step(command) else { break }
        }
        return out
    }

    private mutating func step(_ command: Character) -> Bool {
        let relative = command.isLowercase
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        switch command.lowercased().first! {
        case "m":
            guard let x = number(), let y = number() else { return false }
            current = point(x, y)
            start = current
            out.append(.move(current))
            lastCubicControl = nil; lastQuadControl = nil

        case "l":
            guard let x = number(), let y = number() else { return false }
            current = point(x, y)
            out.append(.line(current))
            lastCubicControl = nil; lastQuadControl = nil

        case "h":
            guard let x = number() else { return false }
            current = CGPoint(x: relative ? current.x + x : x, y: current.y)
            out.append(.line(current))
            lastCubicControl = nil; lastQuadControl = nil

        case "v":
            guard let y = number() else { return false }
            current = CGPoint(x: current.x, y: relative ? current.y + y : y)
            out.append(.line(current))
            lastCubicControl = nil; lastQuadControl = nil

        case "c":
            guard let x1 = number(), let y1 = number(),
                  let x2 = number(), let y2 = number(),
                  let x = number(), let y = number() else { return false }
            let c1 = point(x1, y1), c2 = point(x2, y2), end = point(x, y)
            out.append(.curve(to: end, control1: c1, control2: c2))
            current = end; lastCubicControl = c2; lastQuadControl = nil

        case "s":
            guard let x2 = number(), let y2 = number(),
                  let x = number(), let y = number() else { return false }
            let c1 = reflect(lastCubicControl)
            let c2 = point(x2, y2), end = point(x, y)
            out.append(.curve(to: end, control1: c1, control2: c2))
            current = end; lastCubicControl = c2; lastQuadControl = nil

        case "q":
            guard let x1 = number(), let y1 = number(),
                  let x = number(), let y = number() else { return false }
            let q = point(x1, y1), end = point(x, y)
            appendQuad(control: q, to: end)

        case "t":
            guard let x = number(), let y = number() else { return false }
            let q = reflect(lastQuadControl)
            appendQuad(control: q, to: point(x, y))

        case "a":
            guard let rx = number(), let ry = number(), let rotation = number(),
                  let largeArc = flag(), let sweep = flag(),
                  let x = number(), let y = number() else { return false }
            let end = point(x, y)
            appendArc(rx: rx, ry: ry, rotation: rotation,
                      largeArc: largeArc, sweep: sweep, to: end)
            current = end; lastCubicControl = nil; lastQuadControl = nil

        case "z":
            out.append(.close)
            current = start
            lastCubicControl = nil; lastQuadControl = nil

        default:
            return false
        }
        return true
    }

    /// A smooth curve's first control point is the previous one mirrored through
    /// the current point; with no previous curve it *is* the current point.
    private func reflect(_ control: CGPoint?) -> CGPoint {
        guard let control else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    private mutating func appendQuad(control: CGPoint, to end: CGPoint) {
        // Exact degree elevation — a quadratic is a cubic with these controls.
        let c1 = CGPoint(x: current.x + 2.0 / 3 * (control.x - current.x),
                         y: current.y + 2.0 / 3 * (control.y - current.y))
        let c2 = CGPoint(x: end.x + 2.0 / 3 * (control.x - end.x),
                         y: end.y + 2.0 / 3 * (control.y - end.y))
        out.append(.curve(to: end, control1: c1, control2: c2))
        current = end; lastQuadControl = control; lastCubicControl = nil
    }

    /// Endpoint-parameterised arc → centre parameterisation → cubic segments,
    /// following the SVG 1.1 implementation notes (F.6.5).
    private mutating func appendArc(
        rx: CGFloat, ry: CGFloat, rotation: CGFloat,
        largeArc: Bool, sweep: Bool, to end: CGPoint
    ) {
        var rx = abs(rx), ry = abs(ry)
        let p0 = current
        if rx == 0 || ry == 0 || (p0.x == end.x && p0.y == end.y) {
            out.append(.line(end))
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p0.x - end.x) / 2, dy2 = (p0.y - end.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        // Scale up radii that are too small to span the endpoints (F.6.6).
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let coef = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cx1 = coef * rx * y1 / ry
        let cy1 = -coef * ry * x1 / rx

        let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + end.x) / 2
        let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard len > 0 else { return 0 }
            let a = acos(min(1, max(-1, dot / len)))
            return (ux * vy - uy * vx < 0) ? -a : a
        }

        let theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry,
                          (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // A cubic approximates at most a quarter turn within tolerance.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let alpha = 4.0 / 3 * tan(step / 4)

        var angleStart = theta
        var from = p0
        for _ in 0..<segments {
            let angleEnd = angleStart + step
            func onArc(_ t: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                        y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
            }
            func derivative(_ t: CGFloat) -> CGPoint {
                CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                        y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
            }
            let to = onArc(angleEnd)
            let d0 = derivative(angleStart), d1 = derivative(angleEnd)
            out.append(.curve(
                to: to,
                control1: CGPoint(x: from.x + alpha * d0.x, y: from.y + alpha * d0.y),
                control2: CGPoint(x: to.x - alpha * d1.x, y: to.y - alpha * d1.y)
            ))
            from = to
            angleStart = angleEnd
        }
    }

    // MARK: Lexing

    private mutating func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," ||
                chars[i] == "\n" || chars[i] == "\r" || chars[i] == "\t" {
            i += 1
        }
    }

    private mutating func number() -> CGFloat? {
        skipSeparators()
        let begin = i
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        while i < chars.count, chars[i].isNumber { i += 1 }
        if i < chars.count, chars[i] == "." {
            i += 1
            while i < chars.count, chars[i].isNumber { i += 1 }
        }
        if i < chars.count, chars[i] == "e" || chars[i] == "E" {
            let mark = i
            i += 1
            if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
            if i < chars.count, chars[i].isNumber {
                while i < chars.count, chars[i].isNumber { i += 1 }
            } else {
                i = mark
            }
        }
        guard i > begin, let value = Double(String(chars[begin..<i])) else { return nil }
        return CGFloat(value)
    }

    /// Arc flags are single characters and may run together with the numbers
    /// around them (`a5 5 0 1 0 10 0` is also legal as `a5 5 0 1010 0`), so they
    /// cannot go through `number()`.
    private mutating func flag() -> Bool? {
        skipSeparators()
        guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
        defer { i += 1 }
        return chars[i] == "1"
    }
}
