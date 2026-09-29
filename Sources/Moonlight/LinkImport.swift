import SwiftUI
import AppKit
import MoonlightDesign
import MoonlightCore

/// A `moonlight://` link the app was opened with, waiting for the window to
/// ask about it. Kept here rather than in a view, because a link can arrive
/// before there is a window — the app launched by the link, or closed to the
/// menu bar — and the window that then appears picks it up.
@MainActor
final class DeepLinks: ObservableObject {
    static let shared = DeepLinks()

    struct Request: Identifiable {
        let id = UUID()
        /// The subscription link, or nil for a link that asked for nothing
        /// this app does.
        let subscription: String?
    }

    @Published var pending: Request?

    func receive(_ url: URL) {
        switch DeepLink(url) {
        case .addSubscription(let link):
            LogStore.shared.client("Opened with a link to add a subscription")
            pending = Request(subscription: link)
        case nil:
            LogStore.shared.client("Opened with a link it does not handle", level: .warning)
            pending = Request(subscription: nil)
        }
    }
}

/// Asks before a link adds a subscription, then adds it and says how it went.
///
/// The link itself is never shown: it is a credential, and anyone who reads
/// it off the screen has the subscription.
struct LinkImportSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @ObservedObject var tunnel: TunnelController
    let request: DeepLinks.Request
    let close: () -> Void
    let connect: () -> Void

    private enum Phase: Equatable {
        case ask, adding, done
        case failed(TunnelIssue)
    }

    @State private var phase: Phase = .ask

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 22)
            palette.hairlineSoft.frame(height: 1)
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 420)
        .animation(Motion.standard, value: phase)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let link = request.subscription {
            switch phase {
            case .ask, .adding:
                message(icon: nil,
                        title: L.t(.linkTitle, locale),
                        lines: [L.t(.linkBody, locale)] + replacementNote(link))
            case .done:
                message(icon: .check, title: L.t(.importDone, locale), lines: [summary])
            case .failed(let issue):
                message(icon: .circleAlert, title: L.t(.linkFailedTitle, locale),
                        lines: [L.issue(issue, locale)], danger: true)
            }
        } else {
            message(icon: .circleAlert, title: L.t(.linkInvalidTitle, locale),
                    lines: [L.t(.linkInvalidBody, locale)], danger: true)
        }
    }

    private func replacementNote(_ link: String) -> [String] {
        guard tunnel.hasSubscription else { return [] }
        return [L.t(tunnel.isCurrentSubscription(link) ? .linkSame : .linkReplaces, locale)]
    }

    private func message(icon: Icon?, title: String, lines: [String], danger: Bool = false) -> some View {
        VStack(spacing: 14) {
            ZStack {
                if let icon {
                    IconView(icon, size: 26, strokeWidth: 2.6)
                        .foregroundStyle(danger ? palette.danger : palette.textOnAccent)
                        .frame(width: 56, height: 56)
                        .mlGlass(.circle, tint: danger ? palette.danger.opacity(0.18) : palette.accent,
                                 fallback: danger ? palette.dangerQuiet : palette.accent)
                } else {
                    LogoTile(size: 56, radius: 16)
                }
            }
            Text(title)
                .font(.mlDisplay(19))
                .tracking(TypeScale.trackDisplay * 19)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
            VStack(spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.ml(13))
                        .foregroundStyle(danger ? palette.danger : palette.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "«moonlight vpn» · no expiry · 23 servers" — what was just added.
    private var summary: String {
        var parts: [String] = []
        if let title = tunnel.info.title { parts.append("«\(title)»") }
        if tunnel.info.daysLeft != nil || tunnel.info.expire == nil {
            parts.append(Format.days(tunnel.info.daysLeft, locale: locale))
        }
        if !tunnel.nodes.isEmpty { parts.append("\(tunnel.nodes.count) \(L.t(.nodesCount, locale))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 10) {
            Spacer()
            if let link = request.subscription {
                switch phase {
                case .ask, .adding:
                    secondary(L.t(.ruleCancel, locale), action: close)
                        .disabled(phase == .adding)
                    primary(phase == .adding ? L.t(.linkAdding, locale) : L.t(.linkAdd, locale),
                            busy: phase == .adding) { add(link) }
                case .done:
                    secondary(L.t(.linkLater, locale), action: close)
                    primary(L.t(.connectNow, locale), busy: false, action: connect)
                case .failed:
                    secondary(L.t(.linkClose, locale), action: close)
                    primary(L.t(.linkRetry, locale), busy: false) { add(link) }
                }
            } else {
                primary(L.t(.linkClose, locale), busy: false, action: close)
            }
        }
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ml(13, .heavy))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .contentShape(Rectangle())
        }
        .pressButton()
        .keyboardShortcut(.cancelAction)
    }

    private func primary(_ title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                Text(title)
            }
            .font(.ml(13, .heavy))
            .foregroundStyle(palette.textOnAccent)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .mlGlass(.capsule, tint: palette.accent, fallback: palette.accent)
        }
        .pressButton()
        .keyboardShortcut(.defaultAction)
        .disabled(busy)
    }

    private func add(_ link: String) {
        phase = .adding
        Task {
            if await tunnel.importSubscription(link) {
                phase = .done
            } else {
                phase = .failed(tunnel.issue ?? .serverUnavailable(code: nil))
            }
        }
    }
}
