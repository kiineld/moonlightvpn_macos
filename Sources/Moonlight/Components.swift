import SwiftUI
import MoonlightDesign
import MoonlightCore

// MARK: - Press

/// The system's only three press scales. Presses shrink; hovers change colour
/// or border, never scale up.
struct PressScale: ButtonStyle {
    var scale: CGFloat = Motion.pressButton

    func makeBody(configuration: Configuration) -> some View {
        PressScaleBody(configuration: configuration, scale: scale)
    }
}

/// A view rather than the style's body directly, so it can read whether the
/// button is enabled: a disabled control showing the pointing hand promises a
/// click that does nothing.
private struct PressScaleBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.paint, value: configuration.isPressed)
            .pointerCursor(isEnabled)
    }
}

extension View {
    /// `scrollIndicators` is macOS 13+. On 12 the scroller keeps its default
    /// behaviour, which is the same overlay style — the modifier only exists to
    /// hide it, and a visible scroller is a far smaller cost than dropping
    /// Monterey.
    @ViewBuilder
    func mlScrollIndicators(hidden: Bool) -> some View {
        if #available(macOS 13.0, *) {
            scrollIndicators(hidden ? .never : .visible)
        } else {
            self
        }
    }

    /// The pointing hand on hover.
    ///
    /// AppKit does not infer this from a SwiftUI `Button` the way the web does
    /// from an `<a>`, so every clickable surface has to ask. It lives in the
    /// shared button style, which is what most of the app goes through.
    ///
    /// On 15 SwiftUI owns the cursor itself (`pointerStyle`). Before that the
    /// cursor has to be set by hand, and a `push`/`pop` pair on hover — what
    /// this used to be everywhere — drifts: a view re-rendered or removed while
    /// hovered never pops, the stack unbalances, and the hand goes missing on
    /// some controls and sticks on others. Setting it on every move inside the
    /// view re-asserts it instead.
    @ViewBuilder
    func pointerCursor(_ enabled: Bool = true) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(enabled ? .link : nil)
        } else if #available(macOS 13.0, *) {
            onContinuousHover { phase in
                guard enabled else { return }
                switch phase {
                case .active: NSCursor.pointingHand.set()
                case .ended: NSCursor.arrow.set()
                }
            }
        } else {
            onHover { inside in
                guard enabled else { return }
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

extension View {
    func pressCard() -> some View { buttonStyle(PressScale(scale: Motion.pressCard)) }
    func pressButton() -> some View { buttonStyle(PressScale(scale: Motion.pressButton)) }
    func pressIcon() -> some View { buttonStyle(PressScale(scale: Motion.pressIcon)) }

    /// The staggered entrance the design gives every screen's cards.
    func rise(_ delay: Double = 0, _ trigger: some Hashable) -> some View {
        modifier(RiseIn(delay: delay, trigger: AnyHashable(trigger)))
    }
}

/// The entrance attaches its animation to the view with `.animation(_:value:)`
/// rather than firing `withAnimation` from `onAppear`. A `withAnimation`
/// transaction that never gets ticked leaves the render stuck at its *start*
/// value, which for an entrance means an invisible card; attaching the animation
/// to the view instead means the rendered state always follows the model, so a
/// dropped animation costs only the slide.
private struct RiseIn: ViewModifier {
    let delay: Double
    let trigger: AnyHashable
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.riseDistance)
            .animation(Motion.rise(delay: delay), value: shown)
            .onAppear { shown = true }
            .onChange(of: trigger) { _ in
                // Two transactions: hiding and revealing in one pass coalesces
                // to "no change" and the stagger never plays.
                shown = false
                DispatchQueue.main.async { shown = true }
            }
    }
}

// MARK: - Containers

/// A card at one of the system radii: glass on 26 and later, `--ml-surface`
/// before it.
///
/// No outline. The canvas behind every card is `bgDeep`, a step darker than
/// the surface in both themes, so the fill alone separates them — a hairline
/// on top of that was a second edge saying the same thing. The content is
/// clipped to the card and the glass sits behind, unclipped, so its rim is
/// not shaved off.
struct Panel<Content: View>: View {
    @Environment(\.palette) private var palette
    var radius: CGFloat = Radii.card
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .mlGlass(.rounded(radius), fallback: palette.surface)
    }
}

/// A card of rows with no padding of its own — the rows carry it, so the hairline
/// between them can run to the card's edge or be inset past an icon.
struct RowGroup<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: Radii.card, style: .continuous))
            .mlGlass(.rounded(Radii.card), fallback: palette.surface)
    }
}

/// Content at its own height while it fits, a scroll view once it does not.
///
/// A `ScrollView` takes all the height it is offered, so a list of four
/// servers in one stretched its card to the bottom of the window. On 12 there
/// is no `ViewThatFits`, and the scroll view is the safe half of the pair.
struct FitOrScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 13.0, *) {
            ViewThatFits(in: .vertical) {
                content
                ScrollView { content }.mlScrollIndicators(hidden: true)
            }
        } else {
            ScrollView { content }
        }
    }
}

struct RowDivider: View {
    @Environment(\.palette) private var palette
    /// The design insets the rule past the icon column on rows that have one.
    var leading: CGFloat = 18

    var body: some View {
        palette.hairlineSoft
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

/// A table column heading.
///
/// The tracking lives on the `Text`, not on the row: `View.tracking` is macOS
/// 13+, while `Text.tracking` goes back much further, and a header row is an
/// `HStack` of several texts.
struct ColumnHeading: View {
    @Environment(\.palette) private var palette
    let text: String
    var width: CGFloat?
    var alignment: Alignment = .leading

    var body: some View {
        Text(text)
            .font(.ml(10.5, .heavy))
            .tracking(0.08 * 10.5)
            .foregroundStyle(palette.textMuted)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

/// `11.5px / 800 / .1em`, uppercase — the label above every group.
struct Overline: View {
    @Environment(\.palette) private var palette
    let text: String

    var body: some View {
        Text(text)
            .font(.ml(TypeScale.micro, .heavy))
            .tracking(TypeScale.trackOverline * TypeScale.micro)
            .foregroundStyle(palette.textMuted)
    }
}

/// The rounded tile a row's glyph sits in: a quiet grey step with the glyph
/// in the text colour.
struct IconTile: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    var fill: Color
    var size: CGFloat = 40
    var glyph: CGFloat = 17
    /// Turns the glyph while something is in flight. The glyph alone: turning
    /// the whole tile turned its glass with it, and rotated glass draws as a
    /// skewed slab swinging out past the row.
    var spinning = false

    var body: some View {
        IconView(icon, size: glyph)
            .inFlight(.spin, spinning)
            .foregroundStyle(palette.text)
            .frame(width: size, height: size)
            .mlGlass(.rounded(Radii.tile), fallback: fill)
    }
}

/// Turns or pulses a glyph while something is in flight.
///
/// Driven by the clock, never by a repeating animation: `repeatForever` claims
/// every other change in its transaction and every layout change while it
/// runs, so a spinning refresh icon dragged its own button round in a loop
/// whenever the page around it moved.
struct InFlight: ViewModifier {
    enum Kind { case spin, pulse }
    let kind: Kind
    let active: Bool
    var period: Double = 0.9

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: period) / period
                switch kind {
                case .spin: content.rotationEffect(.degrees(phase * 360))
                case .pulse: content.opacity(0.35 + 0.65 * abs(cos(phase * .pi)))
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func inFlight(_ kind: InFlight.Kind, _ active: Bool) -> some View {
        modifier(InFlight(kind: kind, active: active))
    }
}

// MARK: - Controls

/// 44×26 track, 20px knob, 18px of travel — the one switch in the system.
struct MLToggle: View {
    @Environment(\.palette) private var palette
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                // A translucent ink rather than `surface3` when off: on glass the
                // solid grey all but vanished against the light theme.
                Capsule().fill(isOn ? palette.accent : palette.text.opacity(0.12))
                // The knob is the opposite of its track: on a white track in
                // the dark theme a white knob would vanish.
                Circle()
                    .fill(isOn ? palette.textOnAccent : palette.text)
                    .frame(width: 20, height: 20)
                    .offset(x: isOn ? 21 : 3)
            }
            .frame(width: 44, height: 26)
            .animation(Motion.slide, value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .pointerCursor(enabled)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// The segmented pill: one accent capsule slides between the options.
///
/// The capsule is a single view positioned by index rather than a background on
/// whichever option is active paired with `matchedGeometryEffect`. That pairing
/// animates only when SwiftUI matches the two across the same transaction, which
/// it does not do reliably when the options are rebuilt by a `ForEach` — the
/// fill jumped instead of sliding. One view that moves cannot jump.
struct SegmentedPill<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var height: CGFloat = 34
    var onSelect: ((Value) -> Void)?

    private var index: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(max(1, options.count))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: width, height: height)
                    .offset(x: width * CGFloat(index))

                HStack(spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        let active = option.value == selection
                        Button {
                            selection = option.value
                            onSelect?(option.value)
                        } label: {
                            Text(option.label)
                                .font(.ml(12.5, .heavy))
                                .foregroundStyle(active ? palette.textOnAccent : palette.textMuted)
                                .frame(width: width, height: height)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }
            .animation(Motion.slide, value: index)
        }
        .frame(height: height)
        .padding(3)
        .mlGlass(.capsule, fallback: palette.surface2)
    }
}

/// A small round action on glass: accent-ink glyph, no label — the label is
/// the tooltip.
struct GlassIconButton: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    var spinning = false
    var blinking = false
    var action: () -> Void


    var body: some View {
        Button(action: action) {
            IconView(icon, size: 15, strokeWidth: 2)
                .inFlight(.spin, spinning)
                .inFlight(.pulse, blinking)
                .foregroundStyle(palette.accentInk)
                .frame(width: 32, height: 32)
                .mlGlass(.circle, fallback: palette.surface)
                .contentShape(Circle())
        }
        .pressIcon()
    }
}

/// A filled accent button — the one primary action shape.
struct AccentButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var height: CGFloat = 50
    var fullWidth = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ml(15, .heavy))
                .foregroundStyle(palette.textOnAccent)
                .padding(.horizontal, 32)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .mlGlass(.capsule, tint: palette.accent, fallback: palette.accent)
        }
        .pressButton()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// A tappable row: tile, title, subtitle, trailing chevron or external-link mark.
struct ActionRow: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    let fill: Color
    let title: String
    let subtitle: String
    var trailing: Icon? = .chevronRight
    var spinning = false
    var action: () -> Void


    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconTile(icon: icon, fill: fill, spinning: spinning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ml(15, .heavy))
                        .foregroundStyle(palette.text)
                    Text(subtitle)
                        .font(.ml(TypeScale.meta))
                        .foregroundStyle(palette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    IconView(trailing, size: trailing == .chevronRight ? 18 : 17,
                             strokeWidth: trailing == .chevronRight ? 2.2 : 2)
                        .foregroundStyle(palette.textMuted)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .pressCard()
    }
}

/// A settings row with a switch on the right.
struct ToggleRow: View {
    @Environment(\.palette) private var palette
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var enabled = true

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            MLToggle(isOn: $isOn, enabled: enabled)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

/// A progress bar at the two sizes the design uses (6px in the sidebar, 8px on
/// the subscription card).
/// A quota bar. The fill is the portion **used**.
///
/// Named `used` rather than `fraction` on purpose: the two bars showing this
/// same number disagreed for a while, one filling with what was spent and the
/// other with what was left, because the parameter said neither. A name that
/// states the direction is what stops that recurring.
struct QuotaBar: View {
    @Environment(\.palette) private var palette
    /// Portion of the quota consumed, 0…1. Nil means there is no quota, which
    /// draws empty — an unlimited plan has used none *of a limit*, and filling
    /// the bar would read as "all of it".
    let used: Double?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.text.opacity(0.1))
                Capsule()
                    .fill(palette.accent)
                    .frame(width: geometry.size.width * min(1, max(0, used ?? 0)))
            }
        }
        .frame(height: height)
        .animation(Motion.paint, value: used)
    }
}


/// The subscription service's announcement (`announce`), as it wrote it.
///
/// Hidden per message: dismissing one does not hide the next, which is new
/// news by definition.
struct AnnounceBanner: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let text: String

    @AppStorage("dismissedAnnouncement") private var dismissed = ""

    var body: some View {
        if dismissed != text {
            HStack(alignment: .top, spacing: 12) {
                IconView(.messageCircle, size: 17)
                    .foregroundStyle(palette.accentInk)
                    .padding(.top, 1)
                Text(text)
                    .font(.ml(13, .medium))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(Motion.standard) { dismissed = text }
                } label: {
                    IconView(.x, size: 14)
                        .foregroundStyle(palette.textMuted)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .pressIcon()
                .help(L.t(.hideAnnounce, locale))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .mlGlass(.rounded(Radii.card), tint: palette.accent.opacity(0.18),
                     fallback: palette.accentQuiet)
        }
    }
}

/// A short line for the current ``TunnelIssue``, in the danger colour.
struct IssueLine: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    let issue: TunnelIssue
    var centered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            IconView(.circleAlert, size: 15).padding(.top, 1)
            Text(L.issue(issue, locale))
                .font(.ml(12.5, .medium))
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(palette.danger)
    }
}
