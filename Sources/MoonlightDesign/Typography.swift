import SwiftUI
import CoreText

/// Moonlight type — Onest carries every UI/body string, Unbounded is display
/// only (page titles, hero numbers, plan names, stat values, the wordmark).
/// Unbounded never appears below 15px and never in running text.
///
/// Weights run heavy: 500 is the lightest body weight, 700 is a row title, 800
/// is the default for anything emphatic — labels, buttons, chips, numbers.
///
/// The design ships `woff2`, which Core Text cannot load, so the build fetches
/// the variable TTFs from Google Fonts (`scripts/fetch-fonts.sh`) and
/// ``Fonts/register()`` registers them from the app bundle at launch. If a face
/// is missing the accessors fall back to the system font at the same weight,
/// which is why every call site goes through here rather than naming a family.
public enum Fonts {
    public static let uiFamily = "Onest"
    public static let displayFamily = "Unbounded"

    private static var registered = false
    /// Cached because the lookup is not cheap: `CTFontManagerCopyAvailableFont-
    /// FamilyNames` is a round trip to `fontd` that copies every installed
    /// family name. `Font.ml(_:_:)` is called from inside view bodies, several
    /// times per body, on every re-render — querying live pegs the main thread
    /// hard enough to starve the async work scheduled on the main actor.
    private static var familyCache: Set<String>?

    /// Registers the bundled faces with Core Text. Idempotent, and safe to call
    /// when the resources are absent — a debug build run straight out of
    /// `.build` has no bundle.
    public static func register(in bundle: Bundle = .main) {
        guard !registered else { return }
        registered = true

        let urls = ["ttf", "otf"].flatMap { ext in
            bundle.urls(forResourcesWithExtension: ext, subdirectory: "fonts") ?? []
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        familyCache = nil
    }

    /// Whether a family is installed. Read from the cache, which `register()`
    /// invalidates — the only moment the answer can change.
    ///
    /// Main-thread only, which every call site is: these are read from view
    /// bodies.
    static func available(_ family: String) -> Bool {
        if familyCache == nil {
            familyCache = Set(CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
        }
        return familyCache?.contains(family) ?? false
    }
}

public extension Font {
    /// Onest at an explicit size and weight.
    static func ml(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        Fonts.available(Fonts.uiFamily)
            ? .custom(Fonts.uiFamily, fixedSize: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    /// Unbounded. Display only — never below 15px, never in running text.
    static func mlDisplay(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        Fonts.available(Fonts.displayFamily)
            ? .custom(Fonts.displayFamily, fixedSize: size).weight(weight)
            : .system(size: size, weight: weight, design: .rounded)
    }

    /// The mono face carries timers, latency figures and the subscription URL.
    static func mlMono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Type steps, named as the source names them.
public enum TypeScale {
    // Display steps (Unbounded, weight 800)
    public static let hero: CGFloat = 40
    public static let plan: CGFloat = 30
    public static let title: CGFloat = 24
    public static let lead: CGFloat = 19

    // Text steps (Onest)
    public static let body: CGFloat = 15
    public static let bodySm: CGFloat = 14
    public static let meta: CGFloat = 12.5
    public static let micro: CGFloat = 11.5

    // Tracking — display type is always negative-tracked, body is not.
    public static let trackDisplay: CGFloat = -0.03
    public static let trackTitle: CGFloat = -0.02
    public static let trackTight: CGFloat = -0.01
    public static let trackOverline: CGFloat = 0.1
}
