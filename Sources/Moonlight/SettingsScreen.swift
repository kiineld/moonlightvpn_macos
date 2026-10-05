import SwiftUI
import AppKit
import ServiceManagement
import MoonlightDesign
import MoonlightCore

struct SettingsScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var settings: AppSettings
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @EnvironmentObject var updater: Updater
    @State private var helperBusy = false
    @State private var helperError: String?

    var body: some View {
        // The design's content area scrolls; settings is the screen that
        // overflows first on a short window.
        ScrollViewReader { scroller in
            PageScroll {
                columns
            }
            // The helper may have been replaced or removed since this screen
            // last looked; checked off the main thread, never while drawing.
            .task { await tunnel.refreshHelperStatus() }
            // Sent here to install the helper for TUN, and left without doing
            // it: the next visit is an ordinary one.
            .onDisappear { settings.tunAwaitingHelper = false }
            // The update card is the last thing on the page, and its progress
            // opens beneath it — below the window's edge on a short window.
            .onChange(of: updater.state.isUnderWay) { underWay in
                guard underWay else { return }
                withAnimation(Motion.slide) { scroller.scrollTo(Self.aboutID, anchor: .bottom) }
            }
            // Arrived from the update banner, the install may already be under
            // way by the time the page appears, and then nothing changes to
            // bring the progress into view.
            .onAppear {
                guard updater.state.isUnderWay else { return }
                DispatchQueue.main.async {
                    withAnimation(Motion.slide) { scroller.scrollTo(Self.aboutID, anchor: .bottom) }
                }
            }
        }
    }

    private static let aboutID = "about"

    private var columns: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Overline(text: L.t(.sectionTunnel, locale)).padding(.horizontal, 2)
                tunnelSection

                Overline(text: L.t(.sectionSystem, locale))
                    .padding(.horizontal, 2).padding(.top, 8)
                systemSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Overline(text: L.t(.sectionApp, locale)).padding(.horizontal, 2)
                appSection

                Overline(text: L.t(.sectionSupport, locale))
                    .padding(.horizontal, 2).padding(.top, 8)
                supportSection
                aboutCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Tunnel

    private var tunnelSection: some View {
        RowGroup {
            ModeRow(
                title: L.t(.modeSystemProxy, locale),
                subtitle: L.t(.modeSystemProxySub, locale),
                selected: tunnel.tunnelMode == .systemProxy
            ) {
                Task { await tunnel.setTunnelMode(.systemProxy) }
            }
            RowDivider()
            ModeRow(
                title: L.t(.modeTun, locale),
                subtitle: L.t(.modeTunSub, locale),
                selected: tunnel.tunnelMode == .tun
            ) {
                Task {
                    // TUN cannot run without the helper, so asking for it here —
                    // rather than failing at the next connect — is the whole
                    // point of putting the install on this row.
                    if !tunnel.helperInstalled { await installHelper() }
                    if tunnel.helperInstalled { await tunnel.setTunnelMode(.tun) }
                }
            }
            RowDivider()
            helperRow
        }
    }

    private var helperRow: some View {
        // Read once per render rather than per use: it can launch the core.
        let stale = tunnel.helperInstalled && !tunnel.helperIsCurrent
        // Arrived from the connect page's TUN switch: the install is what
        // they came for, so it is the one lit control on the page.
        let wanted = settings.tunAwaitingHelper && !tunnel.helperInstalled
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stale ? L.t(.helperStale, locale)
                     : tunnel.helperInstalled ? L.t(.helperInstalled, locale)
                     : L.t(.helperInstall, locale))
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                    // Wrap rather than truncate: a clipped "Установить помощ…"
                    // is worse than two lines.
                    .fixedSize(horizontal: false, vertical: true)
                Text(helperError ?? L.t(stale ? .helperStaleSub : .helperInstallSub, locale))
                    .font(.ml(12))
                    .foregroundStyle(helperError == nil ? palette.textMuted : palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    if stale { await installHelper() }
                    else if tunnel.helperInstalled { await removeHelper() }
                    else { await installHelper() }
                }
            } label: {
                Text(L.t(stale ? .updateInstall : tunnel.helperInstalled ? .remove : .install, locale))
                    .font(.ml(12.5, .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(wanted ? palette.textOnAccent : palette.text)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .mlGlass(.capsule, tint: wanted ? palette.accent : nil,
                             fallback: wanted ? palette.accent : palette.surface2)
            }
            .pressButton()
            .disabled(helperBusy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(palette.text.opacity(wanted ? 0.05 : 0))
        .animation(Motion.paint, value: wanted)
    }

    private func installHelper() async {
        helperBusy = true
        helperError = nil
        defer { helperBusy = false }
        do {
            // Through the controller, which knows what core the helper had:
            // installed around it, that stayed cached, and a successful update
            // went on saying "needs an update". It also waits for the daemon to
            // come back and open its socket, where reporting early was a false
            // negative.
            try await tunnel.updateHelper()
            settings.bumpHelperState()
            // Installed because TUN was asked for: now it can have it.
            if settings.tunAwaitingHelper, tunnel.helperInstalled {
                settings.tunAwaitingHelper = false
                await tunnel.setTunnelMode(.tun)
            }
        } catch HelperInstaller.Failure.cancelled {
            helperError = nil
        } catch {
            // What went wrong in words; osascript's own text — "0:181:
            // execution error: Bootstrap failed: 5" — goes to the log.
            helperError = L.t(.helperInstallFailed, locale)
            LogStore.shared.client("Helper install failed: \(error.localizedDescription)", level: .error)
        }
    }

    private func removeHelper() async {
        helperBusy = true
        defer { helperBusy = false }
        if tunnel.tunnelMode == .tun { await tunnel.setTunnelMode(.systemProxy) }
        do {
            try HelperInstaller.uninstall()
            await tunnel.refreshHelperStatus()
            settings.bumpHelperState()
        } catch HelperInstaller.Failure.cancelled {
        } catch {
            helperError = L.t(.helperRemoveFailed, locale)
            LogStore.shared.client("Helper removal failed: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - System

    private var systemSection: some View {
        RowGroup {
            ToggleRow(
                title: L.t(.launchAtLogin, locale),
                subtitle: L.t(.launchAtLoginSub, locale),
                isOn: $settings.launchAtLogin
            )
            RowDivider()
            ToggleRow(
                title: L.t(.menuBarIcon, locale),
                subtitle: L.t(.menuBarIconSub, locale),
                isOn: $settings.menuBarIcon
            )
            RowDivider()
            ToggleRow(
                title: L.t(.autoConnect, locale),
                subtitle: L.t(.autoConnectSub, locale),
                isOn: $settings.autoConnect
            )
            RowDivider()
            autoUpdateRow
        }
    }

    /// How often the subscription refreshes itself. The choice lives under
    /// the title rather than beside it: five options do not fit next to a
    /// label in half the window.
    private var autoUpdateRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(.autoUpdate, locale))
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                Text(autoUpdateSubtitle)
                    .font(.ml(12))
                    .foregroundStyle(palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SegmentedPill(
                selection: Binding(
                    get: {
                        TunnelController.autoUpdateChoice(
                            nearest: settings.autoUpdateHours ?? tunnel.info.updateIntervalHours ?? 24)
                    },
                    set: { hours in
                        settings.autoUpdateHours = hours
                        Task { await tunnel.refreshIfDue() }
                    }
                ),
                options: TunnelController.autoUpdateChoices.map { hours in
                    (hours, hours == 0
                        ? L.t(.autoUpdateOff, locale)
                        : "\(hours) \(L.t(.hoursShort, locale))")
                },
                height: 28
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var autoUpdateSubtitle: String {
        guard tunnel.hasSubscription else { return L.t(.autoUpdateSub, locale) }
        let last = tunnel.lastRefresh.map { "\(L.t(.lastUpdated, locale)) \(L.ago($0, locale))" }
            ?? L.t(.neverUpdated, locale)
        return "\(L.t(.autoUpdateSub, locale)) · \(last)"
    }

    // MARK: - App

    private var appSection: some View {
        RowGroup {
            HStack(spacing: 14) {
                Text(L.t(.language, locale))
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SegmentedPill(
                    selection: $settings.locale,
                    options: [(AppLocale.ru, "RU"), (AppLocale.en, "EN")],
                    height: 28
                )
                .frame(width: 104)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            RowDivider()
            HStack(spacing: 14) {
                Text(L.t(.theme, locale))
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SegmentedPill(
                    selection: Binding(
                        get: { settings.theme },
                        set: { theme in withAnimation(Motion.enter) { settings.theme = theme } }
                    ),
                    options: [(Theme.dark, L.t(.themeDark, locale)),
                              (Theme.light, L.t(.themeLight, locale))],
                    height: 28
                )
                .frame(width: 176)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            if GlassShape.systemHasGlass {
                RowDivider()
                ToggleRow(
                    title: L.t(.liquidGlass, locale),
                    subtitle: L.t(.liquidGlassSub, locale),
                    // Animated at the source, like the theme: every surface in
                    // the window changes with it, and they change together.
                    isOn: Binding(
                        get: { settings.liquidGlass },
                        set: { on in withAnimation(Motion.standard) { settings.liquidGlass = on } }
                    )
                )
            }
            RowDivider()
            ToggleRow(
                title: L.t(.notifications, locale),
                subtitle: L.t(.notificationsSub, locale),
                isOn: $settings.notifications
            )
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        RowGroup {
            ActionRow(
                icon: .messageCircle,
                fill: palette.cat1,
                title: L.t(.ourChannel, locale),
                subtitle: L.t(.ourChannelSub, locale),
                trailing: .externalLink
            ) {
                NSWorkspace.shared.open(AppConfig.telegramChannelURL)
            }
            RowDivider(leading: 74)
            ActionRow(
                icon: .headphones,
                fill: palette.cat4,
                title: L.t(.support, locale),
                subtitle: L.t(.supportSub, locale),
                trailing: .externalLink
            ) {
                // The subscription's own support contact when it names one.
                NSWorkspace.shared.open(tunnel.info.supportURL ?? AppConfig.supportURL)
            }
            RowDivider(leading: 74)
            ActionRow(
                icon: .circleAlert,
                fill: palette.cat3,
                title: L.t(.navLogs, locale),
                subtitle: L.t(.subtitleLogs, locale)
            ) {
                page = .logs
            }
        }
    }

    private var aboutCard: some View {
        aboutPanel.id(Self.aboutID)
    }

    private var aboutPanel: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    LogoTile(size: 42, radius: Radii.tile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("moonlight")
                            .font(.mlWordmark(16))
                            .tracking(-0.025 * 16)
                            .foregroundStyle(palette.text)
                            .fixedSize()
                        Text("\(L.t(.version, locale)) \(AppConfig.version) · \(AppConfig.deviceName)")
                            .font(.ml(TypeScale.meta))
                            .foregroundStyle(palette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    updateButton
                }

                // The result eases in under the header on the one curve rather
                // than growing the card in a single frame.
                Group {
                    if let progress = updateProgress {
                        progress.padding(.top, 14)
                    } else if case .available(let version, _) = updater.state {
                        Text("\(L.t(.updateAvailable, locale)) \(version)")
                            .font(.ml(12))
                            .foregroundStyle(palette.accentInk)
                            .padding(.top, 10)
                    } else if case .failed(let reason) = updater.state {
                        Text("\(L.t(.updateFailed, locale)): \(reason)")
                            .font(.ml(12))
                            .foregroundStyle(palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    } else if updater.state == .upToDate {
                        Text(L.t(.updateUpToDate, locale))
                            .font(.ml(12))
                            .foregroundStyle(palette.textMuted)
                            .padding(.top, 10)
                    }
                }
                .transition(.opacity)
                .animation(Motion.standard, value: statusKind)

                palette.hairlineSoft.frame(height: 1).padding(.vertical, 16)

                HStack(spacing: 8) {
                    IconView(.lock, size: 15).foregroundStyle(palette.accentInk)
                    Text(L.t(.keysStayHere, locale))
                        .font(.ml(TypeScale.meta))
                        .foregroundStyle(palette.textMuted)
                    Spacer(minLength: 0)
                }

            }
        }
    }

    // MARK: - Updates

    /// One button that walks the whole update: check, then install.
    ///
    /// The app is not notarised and there is no App Store to hand this to, so
    /// the alternative was sending people to a download page to do by hand
    /// exactly what this does — fetch the release, swap the bundle, relaunch.
    @ViewBuilder
    private var updateButton: some View {
        let available: Bool = { if case .available = updater.state { return true }; return false }()
        let busy = updater.state.isUnderWay || updater.state == .checking
        return Button {
            guard !busy else { return }
            Task { available ? await updater.install() : await updater.check() }
        } label: {
            // One control through every state, the same size throughout: the
            // widest label is laid out invisibly and the current one sits on
            // it. Swapping the glass button for a bare spinner and back made
            // the card jump twice on every check, and the version line beside
            // it re-truncated each time.
            ZStack {
                Text(L.t(.checkUpdates, locale)).hidden()
                if busy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progressText).monospacedDigit()
                    }
                    .transition(.opacity)
                } else {
                    Text(L.t(available ? .updateInstall : .checkUpdates, locale))
                        .transition(.opacity)
                }
            }
            .font(.ml(12.5, .heavy))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(available ? palette.textOnAccent : busy ? palette.textMuted : palette.text)
            .padding(.horizontal, 15)
            .frame(height: 36)
            .mlGlass(.capsule, tint: available ? palette.accent : nil,
                     fallback: available ? palette.accent : palette.surface2)
        }
        .pressButton()
        // Not disabled while busy — it ignores the click instead. Disabling the
        // focused button moved focus on to the next control, and the scroll
        // view jumped to show it: the page leapt the moment a check began.
        .animation(Motion.standard, value: busy)
        .animation(Motion.paint, value: available)
    }

    /// Beside the spinner: how much has arrived while downloading, the stage
    /// otherwise.
    private var progressText: String {
        if case .downloading(let received, let total) = updater.state {
            return Format.transfer(received, of: total, locale: locale)
        }
        return L.t(progressLabel, locale)
    }

    /// Which status line shows — changes only when the line itself does, not
    /// on every download tick, so the curve runs once per change.
    private var statusKind: Int {
        switch updater.state {
        case .downloading, .verifying, .installing: return 1
        case .available: return 2
        case .failed: return 3
        case .upToDate: return 4
        default: return 0
        }
    }

    private var progressLabel: L.Key {
        switch updater.state {
        case .checking: return .updateChecking
        case .verifying: return .updateVerifying
        case .installing: return .updateInstalling
        default: return .updateDownloading
        }
    }

    /// While an update is under way: what it is doing, how far along it is,
    /// and what happens next. A spinner alone left people unsure whether a
    /// 35 MB download was moving at all, or what they were waiting for.
    private var updateProgress: AnyView? {
        let version = updater.pendingVersion.map { " \($0)" } ?? ""
        let fraction: Double?
        let detail: String
        switch updater.state {
        case .downloading(let received, let total):
            // The megabytes are beside the spinner; this line says what the
            // wait ends in.
            fraction = total.map { Double(received) / Double(max($0, 1)) } ?? 0
            detail = L.t(.updateDownloadHint, locale)
        case .verifying:
            fraction = 1
            detail = L.t(.updateVerifyingHint, locale)
        case .installing:
            fraction = 1
            detail = L.t(.updateRestartHint, locale)
        default:
            return nil
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(L.t(.updateTo, locale))\(version)")
                        .font(.ml(12.5, .bold))
                        .foregroundStyle(palette.text)
                    Spacer(minLength: 8)
                    if case .downloading(_, .some) = updater.state, let fraction {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.mlMono(12))
                            .foregroundStyle(palette.accentInk)
                    }
                }
                QuotaBar(used: fraction, height: 6)
                Text(detail)
                    .font(.ml(12))
                    .foregroundStyle(palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

}

/// A radio-style row for the two tunnel transports.
private struct ModeRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(
                        selected ? palette.accent : palette.hairline, lineWidth: 2
                    )
                    if selected {
                        Circle().fill(palette.accent).padding(5)
                    }
                }
                .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ml(14.5, .bold))
                        .foregroundStyle(palette.text)
                    Text(subtitle)
                        .font(.ml(12))
                        .foregroundStyle(palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .pressCard()
        .animation(Motion.paint, value: selected)
    }
}
