import SwiftUI
import AppKit
import MoonlightDesign
import MoonlightCore

struct ImportScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @State private var link = ""
    @State private var done = false
    @State private var working = false
    /// This screen's own failure — not whatever went wrong last elsewhere.
    @State private var failure: TunnelIssue?
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            if done { success } else { form }
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.t(.importIntro, locale))
                .font(.ml(13.5))
                .lineSpacing(4)
                .foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField(L.t(.importPlaceholder, locale), text: $link)
                    .textFieldStyle(.plain)
                    .font(.mlMono(12.5))
                    .foregroundStyle(palette.text)
                    .focused($focused)
                    .onSubmit { submit() }
                Button(action: submit) {
                    // The fetch can take seconds; a button that only greys out
                    // looks like it did nothing.
                    Group {
                        if working {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L.t(.importAdd, locale))
                        }
                    }
                    .font(.ml(13, .heavy))
                    .foregroundStyle(palette.textOnAccent)
                    .padding(.horizontal, 18)
                    .frame(minWidth: 96)
                    .frame(height: 40)
                    .mlGlass(.capsule, tint: palette.accent, fallback: palette.accent)
                }
                .pressButton()
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(height: 52)
            .mlGlass(.rounded(16), fallback: palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? palette.accentLine : .clear, lineWidth: 1)
            )
            .animation(Motion.paint, value: focused)

            OutlineButton(
                icon: .link2,
                title: "\(L.t(.pasteFromClipboard, locale)) · ⌘V"
            ) {
                if let clipboard = NSPasteboard.general.string(forType: .string) {
                    link = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
                    submit()
                }
            }

            if let failure {
                HStack(spacing: 8) {
                    IconView(.circleAlert, size: 16)
                    Text(L.issue(failure, locale))
                        .font(.ml(TypeScale.meta))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(palette.danger)
            }

        }
        .onAppear { focused = true }
    }

    private func submit() {
        let candidate = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !working else { return }
        working = true
        failure = nil
        Task {
            let ok = await tunnel.importSubscription(candidate)
            working = false
            if ok {
                withAnimation(Motion.enter) { done = true }
            } else {
                failure = tunnel.issue ?? .serverUnavailable(code: nil)
            }
        }
    }

    // MARK: - Success

    private var success: some View {
        VStack(spacing: 0) {
            IconView(.check, size: 40, strokeWidth: 2.6)
                .foregroundStyle(palette.textOnAccent)
                .frame(width: 88, height: 88)
                .mlGlass(.circle, tint: palette.accent, fallback: palette.accent)
                .transition(.scale(scale: 0.72).combined(with: .opacity))

            Text(L.t(.importDone, locale))
                .font(.mlDisplay(28))
                .tracking(TypeScale.trackDisplay * 28)
                .foregroundStyle(palette.text)
                .padding(.top, 24)

            Text(summary)
                .font(.ml(14))
                .foregroundStyle(palette.text2)
                .padding(.top, 10)

            AccentButton(title: L.t(.connectNow, locale)) {
                page = .connect
                Task { await tunnel.connect() }
            }
            .padding(.top, 30)
        }
        .padding(.top, 48)
    }

    private var summary: String {
        var parts: [String] = []
        if let title = tunnel.info.title { parts.append("«\(title)»") }
        if let days = tunnel.info.daysLeft { parts.append(Format.days(days, locale: locale)) }
        parts.append(Format.nodes(tunnel.nodes.count, locale: locale))
        if let total = tunnel.info.total {
            parts.append(Format.bytes(total, locale: locale))
        }
        return parts.joined(separator: " · ")
    }
}

/// A full-width hairline button — the paste row and the helper actions use it.
struct OutlineButton: View {
    @Environment(\.palette) private var palette
    var icon: Icon?
    let title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { IconView(icon, size: 17) }
                Text(title).font(.ml(14, .heavy))
            }
            .foregroundStyle(palette.text)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .mlGlass(.capsule, fallback: palette.surface)
            .overlay(
                Capsule().strokeBorder(
                    hovering ? palette.accentLine : .clear, lineWidth: 1
                )
            )
        }
        .pressCard()
        .onHover { hovering = $0 }
        .animation(Motion.paint, value: hovering)
    }
}
