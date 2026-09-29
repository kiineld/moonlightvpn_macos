import SwiftUI

/// Moonlight motion: one curve.
///
/// Everything that moves — a page arriving, the drawer opening, the power
/// button growing, a selection pill gliding, the sidebar folding — moves on
/// ``standard``: a spring damped just short of settling on its own, so it eases
/// in and lands without the overshoot that makes a bounce read as a toy. Only
/// changes with no movement in them (a colour, a hover wash) use ``paint``.
/// The app used to carry six curves, two of them overshooting, and screens
/// felt like different apps as a result.
public enum Motion {
    /// The one curve for anything that moves.
    public static let standard = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// Colour, opacity and hover — changes with nothing moving.
    public static let paint = Animation.easeOut(duration: 0.18)

    // The names screens were written against. All of them are the one curve.
    public static let slide = standard
    public static let enter = standard
    public static func rise(delay: Double = 0) -> Animation { standard.delay(delay) }
    /// How far a page's content travels as it arrives. Short: it settles into
    /// place rather than flying in.
    public static let riseDistance: CGFloat = 8

    /// The sidebar's selection is the one thing that moves as a liquid rather
    /// than a solid: the edge heading for the new row leads on a quick spring
    /// and the other follows on the standard one, so the glass stretches
    /// towards where it is going and gathers itself up on arrival. These are
    /// the two springs' response times, in seconds, both damped like
    /// ``standard``.
    public static let liquidLead = 0.26
    public static let liquidTrail = 0.44
    public static let liquidDamping = 0.9

    /// How far along a spring with this response is, `t` seconds in: 0 at the
    /// start, 1 once settled — for motion driven by a timeline rather than by
    /// an `Animation`.
    public static func spring(_ t: Double, response: Double, damping: Double = liquidDamping) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / response
        let decay = damping * omega
        let ringing = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-decay * t) * (cos(ringing * t) + decay / ringing * sin(ringing * t))
    }

    // Press scales — barely there, so a press reads as a press and not a pop.
    public static let pressCard: CGFloat = 0.99
    public static let pressButton: CGFloat = 0.975
    public static let pressIcon: CGFloat = 0.94
}

/// Corner radii, matching `tokens/radii.css` usage in the desktop composition.
public enum Radii {
    public static let chip: CGFloat = 6
    public static let field: CGFloat = 10
    public static let tile: CGFloat = 10
    public static let row: CGFloat = 12
    public static let card: CGFloat = 14
    public static let panel: CGFloat = 16
    public static let window: CGFloat = 12
    public static let pill: CGFloat = 999
}
