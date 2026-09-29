import SwiftUI
import MoonlightDesign
import MoonlightCore

/// "Update available", in the corner of the window, after the check the app
/// makes when it opens.
///
/// A click goes to Settings and starts the install there, where the download's
/// progress is shown; the cross puts it away until the next launch. Until this,
/// the about card on the Settings page was the only place an update was ever
/// mentioned, and nobody opens Settings to find out.
struct UpdateBanner: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @ObservedObject var updater: Updater
    @Binding var page: Page

    @State private var dismissed = false

    /// The version on offer, while there is one to install.
    private var version: String? {
        if case .available(let version, _) = updater.state { return version }
        return nil
    }

    /// Not on Settings, whose about card already says the same.
    private var shown: Bool { version != nil && !dismissed && page != .settings }

    var body: some View {
        // The curve is scoped to the banner, which observes download ticks the
        // rest of the window does not.
        ZStack {
            if shown, let version {
                card(version)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(Motion.standard, value: shown)
    }

    private func card(_ version: String) -> some View {
        HStack(spacing: 10) {
            Button(action: install) {
                HStack(spacing: 12) {
                    LogoTile(size: 34, radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.t(.updateBannerTitle, locale))
                            .font(.ml(13.5, .heavy))
                            .foregroundStyle(palette.text)
                        Text(L.t(.updateBannerBody, locale)
                                .replacingOccurrences(of: "{version}", with: version))
                            .font(.ml(12))
                            .foregroundStyle(palette.textMuted)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .pressCard()

            Button {
                dismissed = true
            } label: {
                IconView(.x, size: 13, strokeWidth: 2.2)
                    .foregroundStyle(palette.textMuted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .pressIcon()
            .help(L.t(.hideAnnounce, locale))
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.vertical, 9)
        .fixedSize()
        .mlGlass(.rounded(20), fallback: palette.surface)
    }

    /// To Settings, where the download's progress and what comes next are
    /// shown, with the install already started.
    private func install() {
        page = .settings
        Task { await updater.install() }
    }
}
