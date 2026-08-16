import SwiftUI
import MoonlightDesign
import MoonlightCore

// MARK: - Press

/// The system's only three press scales. Presses shrink; hovers change colour
/// or border, never scale up.
struct PressScale: ButtonStyle {
    var scale: CGFloat = Motion.pressButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.paint, value: configuration.isPressed)
            .pointerCursor()
    }
}

extension View {
    /// The pointing hand on hover.
    ///
    /// AppKit does not infer this from a SwiftUI `Button` the way the web does
    /// from an `<a>`, so every clickable surface has to ask. It lives in the
    /// shared button style, which is what most of the app goes through.
    func pointerCursor(_ enabled: Bool = true) -> some View {
        onHover { inside in
            guard enabled else { return }
            // `push`/`pop` rather than `set`: nested hovers unwind correctly,
            // and a view that disappears mid-hover does not strand the cursor.
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
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
            .offset(y: shown ? 0 : 18)
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

/// A surface card: `--ml-surface` behind a hairline, at one of the system radii.
struct Panel<Content: View>: View {
    @Environment(\.palette) private var palette
    var radius: CGFloat = Radii.card
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            )
    }
}

/// A card of rows with no padding of its own — the rows carry it, so the hairline
/// between them can run to the card's edge or be inset past an icon.
struct RowGroup<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radii.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.card, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            )
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

/// The 42×42 rounded tile a category-coloured glyph sits in.
struct IconTile: View {
    @Environment(\.palette) private var palette
    let icon: Icon
    var fill: Color
    var size: CGFloat = 42
    var glyph: CGFloat = 19

    var body: some View {
        IconView(icon, size: glyph)
            .foregroundStyle(palette.textOnAccent)
            .frame(width: size, height: size)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Radii.tile, style: .continuous))
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
                Capsule().fill(isOn ? palette.accent : palette.surface3)
                Circle()
                    .fill(.white)
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
        .background(palette.surface2)
        .clipShape(Capsule())
    }
}

/// A header action: hairline pill, accent-ink label, border lifts on hover.
struct PillButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var icon: Icon?
    var spinning = false
    var blinking = false
    var action: () -> Void

    @State private var hovering = false
    @State private var phase: Double = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    IconView(icon, size: 16, strokeWidth: 2.2)
                        .rotationEffect(.degrees(spinning ? phase : 0))
                        .opacity(blinking ? 0.35 + 0.65 * abs(cos(phase / 90)) : 1)
                }
                Text(title).font(.ml(13, .heavy))
            }
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(palette.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    hovering ? palette.accentLine : palette.hairline, lineWidth: 1
                )
            )
        }
        .pressButton()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
        .onAppear { advance() }
        .onChange(of: spinning) { _ in advance() }
        .onChange(of: blinking) { _ in advance() }
    }

    /// The design spins the refresh glyph and blinks the ping glyph while each
    /// is in flight. A repeating rotation drives both.
    private func advance() {
        phase = 0
        guard spinning || blinking else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            phase = 360
        }
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
                .background(palette.accent)
                .clipShape(Capsule())
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

    @State private var phase: Double = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconTile(icon: icon, fill: fill)
                    .rotationEffect(.degrees(spinning ? phase : 0))
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
        .onChange(of: spinning) { _ in
            phase = 0
            guard spinning else { return }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
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
                Capsule().fill(palette.surface3)
                Capsule()
                    .fill(palette.accent)
                    .frame(width: geometry.size.width * min(1, max(0, used ?? 0)))
            }
        }
        .frame(height: height)
        .animation(Motion.paint, value: used)
    }
}

