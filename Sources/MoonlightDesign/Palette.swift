import SwiftUI

/// Moonlight colour system — lime on slate.
///
/// Mapped one-for-one from `tokens/colors.css`. Base values first, then semantic
/// aliases. Light mode is the same system flipped, with two deliberate
/// departures the source calls out:
///
/// 1. The accent is **yellow**, not lime — acid lime on near-white neither fills
///    nor reads. Ink type stays on it, so the accent is a bright fill in both.
/// 2. Category fills keep their dark-theme hues, because ink on a dark purple or
///    red slab fails contrast.
///
/// The accent splits into four roles that must stay distinct, because light mode
/// depends on it: `accent` fills, `accentInk` is accent as type or a glyph,
/// `accentInkStrong` is accent type sitting *on* an accent wash, and
/// `accentLine` is accent as a thin mark. In dark mode all four coincide.
public struct Palette: Sendable {

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

    // MARK: Category fills
    public let cat1: Color
    public let cat2: Color
    public let cat3: Color
    public let cat4: Color
    public let cat5: Color
    public let heroGold: Color

    // MARK: Service-status severities
    //
    // Two roles per state. `-ink` is the readable one (pill text, dots, bars —
    // anything drawn ON the page). The plain token is a solid fill that always
    // carries #101828 text, so it stays light in both themes.
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
        lime: .hex(0xD2FF1F), limeDeep: .hex(0xC2F015), purple: .hex(0xAB93E1),
        yellow: .hex(0xFFE078), blue: .hex(0xB6CAEB), orange: .hex(0xFB7A54),
        red: .hex(0xFF6B5A),

        limeWash: .hex(0xD2FF1F, 0.13), limeWashSoft: .hex(0xD2FF1F, 0.06),
        redWash: .hex(0xFF6B5A, 0.13),
        inkWash: .hex(0x101828, 0.14), inkWashSoft: .hex(0x101828, 0.06),
        hairline: .hex(0xFFFFFF, 0.09), hairlineSoft: .hex(0xFFFFFF, 0.05),

        bg: .hex(0x101828), bgDeep: .hex(0x0B111E), surface: .hex(0x182131),
        surface2: .hex(0x212B3B), surface3: .hex(0x2A3547),
        surfaceNav: .hex(0x182131, 0.92),

        text: .hex(0xFFFFFF), text2: .hex(0xAEB7C7), textMuted: .hex(0x878EA8),
        textOnAccent: .hex(0x101828), textLink: .hex(0xD2FF1F),
        textLinkHover: .hex(0xE4FF6A),

        accent: .hex(0xD2FF1F), accentHover: .hex(0xC2F015),
        accentQuiet: .hex(0xD2FF1F, 0.13), accentInk: .hex(0xD2FF1F),
        accentInkStrong: .hex(0xD2FF1F), accentLine: .hex(0xD2FF1F),

        statusSecure: .hex(0xD2FF1F), danger: .hex(0xFF6B5A),
        dangerQuiet: .hex(0xFF6B5A, 0.13), warning: .hex(0xFFE078),
        info: .hex(0xB6CAEB),

        cat1: .hex(0xD2FF1F), cat2: .hex(0xAB93E1), cat3: .hex(0xB6CAEB),
        cat4: .hex(0xFFE078), cat5: .hex(0xFB7A54), heroGold: .hex(0xEFAE2E),

        stUp: .hex(0xD2FF1F), stUpInk: .hex(0xD2FF1F),
        stDegraded: .hex(0xFFE078), stDegradedInk: .hex(0xFFE078),
        stMaintenance: .hex(0xB6CAEB), stMaintenanceInk: .hex(0xB6CAEB),
        stPartial: .hex(0xFB7A54), stPartialInk: .hex(0xFB7A54),
        stDown: .hex(0xFF6B5A), stDownInk: .hex(0xFF6B5A),

        telegramBlue: .hex(0x29A0DA)
    )

    public static let light = Palette(
        lime: .hex(0xFFE078), limeDeep: .hex(0xF5CE52), purple: .hex(0xAB93E1),
        yellow: .hex(0xFFE078), blue: .hex(0xB6CAEB), orange: .hex(0xFB7A54),
        red: .hex(0xFF6B5A),

        limeWash: .hex(0xB07908, 0.16), limeWashSoft: .hex(0xB07908, 0.07),
        redWash: .hex(0xFF6B5A, 0.13),
        inkWash: .hex(0x101828, 0.14), inkWashSoft: .hex(0x101828, 0.06),
        hairline: .hex(0x101828, 0.11), hairlineSoft: .hex(0x101828, 0.06),

        bg: .hex(0xF2F3ED), bgDeep: .hex(0xE6E8DF), surface: .hex(0xFFFFFF),
        surface2: .hex(0xF1F3EB), surface3: .hex(0xE1E4D9),
        surfaceNav: .hex(0xFFFFFF, 0.92),

        text: .hex(0x101828), text2: .hex(0x475467), textMuted: .hex(0x667085),
        textOnAccent: .hex(0x101828), textLink: .hex(0x7A5600),
        textLinkHover: .hex(0x5E4200),

        accent: .hex(0xFFE078), accentHover: .hex(0xF5CE52),
        accentQuiet: .hex(0xB07908, 0.16), accentInk: .hex(0xEFAE2E),
        accentInkStrong: .hex(0x6B4A00), accentLine: .hex(0xEFAE2E),

        statusSecure: .hex(0xFFE078), danger: .hex(0xFF6B5A),
        dangerQuiet: .hex(0xFF6B5A, 0.13), warning: .hex(0x9A6A00),
        info: .hex(0xB6CAEB),

        // cat-4 is deepened so the yellow category stays distinct from the
        // now-yellow accent.
        cat1: .hex(0xFFE078), cat2: .hex(0xAB93E1), cat3: .hex(0xB6CAEB),
        cat4: .hex(0xEFAE2E), cat5: .hex(0xFB7A54), heroGold: .hex(0xFFE078),

        stUp: .hex(0xC2EA45), stUpInk: .hex(0x4C7A0F),
        stDegraded: .hex(0xFFD75C), stDegradedInk: .hex(0x9A6A00),
        stMaintenance: .hex(0xAFC9EE), stMaintenanceInk: .hex(0x3D6392),
        stPartial: .hex(0xFB9B7C), stPartialInk: .hex(0xC2410C),
        stDown: .hex(0xFF8A7A), stDownInk: .hex(0xB42318),

        telegramBlue: .hex(0x29A0DA)
    )

    /// The design keys ping colour off latency, not off a status enum.
    public func pingColor(_ ms: Int) -> Color {
        if ms < 40 { return stUpInk }
        if ms < 100 { return stDegradedInk }
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
