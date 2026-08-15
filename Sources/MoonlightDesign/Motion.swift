import SwiftUI

/// Moonlight motion: short, eased, and mostly about *position*. Two curves do
/// almost all the work — a calm ease for colour/opacity, and an overshoot curve
/// for anything that slides into place (tab pill, segmented pill, toggle knob).
/// Presses shrink; hovers change colour or border, never scale up.
public enum Motion {
    public static let ease = Animation.timingCurve(0.2, 0.7, 0.3, 1)
    public static let easeBounce = Animation.timingCurve(0.5, 1.4, 0.4, 1)
    /// Sliding selection pills.
    public static let easeSlide = Animation.timingCurve(0.5, 1.28, 0.32, 1)
    /// Page-open stagger.
    public static let easeRise = Animation.timingCurve(0.22, 0.85, 0.3, 1)

    public static let durPress: Double = 0.18
    /// Background / colour / border changes.
    public static let durPaint: Double = 0.2
    /// Pill glide.
    public static let durSlide: Double = 0.42
    /// Screen change.
    public static let durEnter: Double = 0.35
    /// Staggered content entrance.
    public static let durRise: Double = 0.52

    public static let press = ease.speed(1 / durPress)
    public static let paint = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: durPaint)
    public static let slide = Animation.timingCurve(0.5, 1.28, 0.32, 1, duration: durSlide)
    public static let enter = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: durEnter)
    public static func rise(delay: Double = 0) -> Animation {
        Animation.timingCurve(0.22, 0.85, 0.3, 1, duration: durRise).delay(delay)
    }

    // Press scales — the whole system uses exactly these three.
    public static let pressCard: CGFloat = 0.985
    public static let pressButton: CGFloat = 0.97
    public static let pressIcon: CGFloat = 0.92
}

/// Corner radii, matching `tokens/radii.css` usage in the desktop composition.
public enum Radii {
    public static let chip: CGFloat = 7
    public static let field: CGFloat = 14
    public static let tile: CGFloat = 13
    public static let row: CGFloat = 18
    public static let card: CGFloat = 22
    public static let panel: CGFloat = 26
    public static let window: CGFloat = 12
    public static let pill: CGFloat = 999
}
