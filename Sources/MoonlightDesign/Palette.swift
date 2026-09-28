import SwiftUI

/// Moonlight colour system — black and white.
///
/// The interface is monochrome: a black canvas, near-black surfaces told apart
/// by a step of grey and a hairline, white type, and white as the one
/// interactive colour (black, in the light theme). Colour is spent in exactly
/// two places — the logo's lime tile, which is the brand and appears nowhere
/// else, and the small signals that carry meaning: latency, errors, log levels.
///
/// The token names are the ones every screen was written against; what they
/// resolve to is what changed. `accent` fills, `accentInk` is the accent as
/// type or a glyph, `textOnAccent` sits on an accent fill.
public struct Palette: Sendable {

    // MARK: Brand — the logo, and nothing else
    public let brand: Color
    public let brandInk: Color

    // MARK: Accents
    public let lime: Color
    public let limeDeep: Color
    public let purple: Color
    public let yellow: Color
    public let blue: Color
    public let orange: Color
    public let red: Color

    // MARK: Washes + hairlines
    public let limeWash: Color
    public let limeWashSoft: Color
    public let redWash: Color
    public let inkWash: Color
    public let inkWashSoft: Color
    public let hairline: Color
    public let hairlineSoft: Color

    // MARK: Surfaces
    public let bg: Color
    public let bgDeep: Color
    public let surface: Color
    public let surface2: Color
    public let surface3: Color
    public let surfaceNav: Color

    // MARK: Text
    public let text: Color
    public let text2: Color
    public let textMuted: Color
    public let textOnAccent: Color
    public let textLink: Color
    public let textLinkHover: Color

    // MARK: Interactive
    public let accent: Color
    public let accentHover: Color
    public let accentQuiet: Color
    public let accentInk: Color
    public let accentInkStrong: Color
    public let accentLine: Color

    // MARK: Status
    public let statusSecure: Color
    public let danger: Color
    public let dangerQuiet: Color
    public let warning: Color
    public let info: Color

    // MARK: Category fills — tiles behind a glyph, all one quiet grey now
    public let cat1: Color
    public let cat2: Color
    public let cat3: Color
    public let cat4: Color
    public let cat5: Color
    public let heroGold: Color

    // MARK: Signals — the only colour in the interface proper
    public let stUp: Color
    public let stUpInk: Color
    public let stDegraded: Color
    public let stDegradedInk: Color
    public let stMaintenance: Color
    public let stMaintenanceInk: Color
    public let stPartial: Color
    public let stPartialInk: Color
    public let stDown: Color
    public let stDownInk: Color

    /// Telegram brand blue — the one third-party colour in the system.
    public let telegramBlue: Color

    public static let dark = Palette(
        brand: .hex(0xD2FF1F), brandInk: .hex(0x0A0A0A),

        lime: .hex(0xD2FF1F), limeDeep: .hex(0xC2F015), purple: .hex(0x8A8A8A),
        yellow: .hex(0xFFD60A), blue: .hex(0xA3A3A3), orange: .hex(0xFF9F0A),
        red: .hex(0xFF453A),

        limeWash: .hex(0xFFFFFF, 0.08), limeWashSoft: .hex(0xFFFFFF, 0.04),
        redWash: .hex(0xFF453A, 0.14),
        inkWash: .hex(0x000000, 0.10), inkWashSoft: .hex(0x000000, 0.05),
        hairline: .hex(0xFFFFFF, 0.10), hairlineSoft: .hex(0xFFFFFF, 0.06),

        bg: .hex(0x0A0A0A), bgDeep: .hex(0x000000), surface: .hex(0x111111),
        surface2: .hex(0x1A1A1A), surface3: .hex(0x262626),
        surfaceNav: .hex(0x0A0A0A),

        text: .hex(0xF5F5F5), text2: .hex(0xA3A3A3), textMuted: .hex(0x737373),
        textOnAccent: .hex(0x000000), textLink: .hex(0xF5F5F5),
        textLinkHover: .hex(0xFFFFFF),

        accent: .hex(0xFFFFFF), accentHover: .hex(0xE5E5E5),
        accentQuiet: .hex(0xFFFFFF, 0.08), accentInk: .hex(0xFFFFFF),
        accentInkStrong: .hex(0xFFFFFF), accentLine: .hex(0xFFFFFF, 0.6),

        statusSecure: .hex(0xFFFFFF), danger: .hex(0xFF453A),
        dangerQuiet: .hex(0xFF453A, 0.14), warning: .hex(0xFFD60A),
        info: .hex(0xA3A3A3),

        cat1: .hex(0x1F1F1F), cat2: .hex(0x1F1F1F), cat3: .hex(0x1F1F1F),
        cat4: .hex(0x1F1F1F), cat5: .hex(0x1F1F1F), heroGold: .hex(0xFFFFFF),

        stUp: .hex(0x30D158), stUpInk: .hex(0x30D158),
        stDegraded: .hex(0xFFD60A), stDegradedInk: .hex(0xFFD60A),
        stMaintenance: .hex(0xA3A3A3), stMaintenanceInk: .hex(0xA3A3A3),
        stPartial: .hex(0xFF9F0A), stPartialInk: .hex(0xFF9F0A),
        stDown: .hex(0xFF453A), stDownInk: .hex(0xFF453A),

        telegramBlue: .hex(0x29A0DA)
    )

    public static let light = Palette(
        brand: .hex(0xD2FF1F), brandInk: .hex(0x0A0A0A),

        lime: .hex(0xD2FF1F), limeDeep: .hex(0xC2F015), purple: .hex(0x737373),
        yellow: .hex(0xB58900), blue: .hex(0x525252), orange: .hex(0xC2410C),
        red: .hex(0xD70015),

        limeWash: .hex(0x000000, 0.06), limeWashSoft: .hex(0x000000, 0.03),
        redWash: .hex(0xD70015, 0.10),
        inkWash: .hex(0xFFFFFF, 0.16), inkWashSoft: .hex(0xFFFFFF, 0.08),
        hairline: .hex(0x000000, 0.10), hairlineSoft: .hex(0x000000, 0.06),

        bg: .hex(0xFAFAFA), bgDeep: .hex(0xFFFFFF), surface: .hex(0xF5F5F5),
        surface2: .hex(0xEDEDED), surface3: .hex(0xE0E0E0),
        surfaceNav: .hex(0xFAFAFA),

        text: .hex(0x0A0A0A), text2: .hex(0x525252), textMuted: .hex(0x8A8A8A),
        textOnAccent: .hex(0xFFFFFF), textLink: .hex(0x0A0A0A),
        textLinkHover: .hex(0x000000),

        accent: .hex(0x0A0A0A), accentHover: .hex(0x262626),
        accentQuiet: .hex(0x000000, 0.06), accentInk: .hex(0x0A0A0A),
        accentInkStrong: .hex(0x0A0A0A), accentLine: .hex(0x000000, 0.5),

        statusSecure: .hex(0x0A0A0A), danger: .hex(0xD70015),
        dangerQuiet: .hex(0xD70015, 0.10), warning: .hex(0xB58900),
        info: .hex(0x525252),

        cat1: .hex(0xEDEDED), cat2: .hex(0xEDEDED), cat3: .hex(0xEDEDED),
        cat4: .hex(0xEDEDED), cat5: .hex(0xEDEDED), heroGold: .hex(0x0A0A0A),

        stUp: .hex(0x248A3D), stUpInk: .hex(0x248A3D),
        stDegraded: .hex(0xB58900), stDegradedInk: .hex(0xB58900),
        stMaintenance: .hex(0x525252), stMaintenanceInk: .hex(0x525252),
        stPartial: .hex(0xC2410C), stPartialInk: .hex(0xC2410C),
        stDown: .hex(0xD70015), stDownInk: .hex(0xD70015),

        telegramBlue: .hex(0x29A0DA)
    )

    /// Latency as a signal: fine, usable, slow. Tuned to what a tunnel out of
    /// Russia actually measures — the old 40/100 ms steps painted every server
    /// here the "slow" colour, which told nobody anything.
    public func pingColor(_ ms: Int) -> Color {
        if ms < 150 { return stUpInk }
        if ms < 300 { return stDegradedInk }
        return stPartialInk
    }
}

extension Color {
    static func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Environment

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

public extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
