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

    @StateObject private var updater = Updater()
    @State private var helperBusy = false
    @State private var helperError: String?

    var body: some View {
        // The design's content area scrolls; settings is the screen that
        // overflows first on a short window.
        ScrollView {
            columns.padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.helperInstalled
                     ? L.t(.helperInstalled, locale)
                     : L.t(.helperInstall, locale))
                    .font(.ml(14.5, .bold))
                    .foregroundStyle(palette.text)
                    // Wrap rather than truncate: a clipped "Установить помощ…"
                    // is worse than two lines.
                    .fixedSize(horizontal: false, vertical: true)
                Text(helperError ?? L.t(.helperInstallSub, locale))
                    .font(.ml(12))
                    .foregroundStyle(helperError == nil ? palette.textMuted : palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task {
                    tunnel.helperInstalled ? await removeHelper() : await installHelper()
                }
            } label: {
                Text(L.t(tunnel.helperInstalled ? .remove : .install, locale))
                    .font(.ml(12.5, .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(palette.surface2)
                    .clipShape(Capsule())
            }
            .pressButton()
            .disabled(helperBusy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private func installHelper() async {
        helperBusy = true
        helperError = nil
        defer { helperBusy = false }
        do {
            try HelperInstaller.install(
                helper: Bundle.main.helperBinaryURL,
                core: Bundle.main.coreBinaryURL
            )
            // launchd takes a moment to bring the daemon up and create its
            // socket; reporting failure before that is a false negative.
            try? await Task.sleep(nanoseconds: 800_000_000)
            settings.bumpHelperState()
        } catch HelperInstaller.Failure.cancelled {
            helperError = nil
        } catch {
            helperError = error.localizedDescription
        }
    }

    private func removeHelper() async {
        helperBusy = true
        defer { helperBusy = false }
        if tunnel.tunnelMode == .tun { await tunnel.setTunnelMode(.systemProxy) }
        do {
            try HelperInstaller.uninstall()
            settings.bumpHelperState()
        } catch HelperInstaller.Failure.cancelled {
        } catch {
            helperError = error.localizedDescription
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
        }
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
                NSWorkspace.shared.open(AppConfig.supportURL)
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
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    LogoTile(size: 42, radius: Radii.tile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("moonlight")
                            .fixedSize()
                            .font(.mlDisplay(16, .bold))
                            .tracking(-0.025 * 16)
                            .foregroundStyle(palette.text)
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

                if case .available(let version, _) = updater.state {
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
        switch updater.state {
        case .checking, .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L.t(progressLabel, locale))
                    .font(.ml(12.5, .heavy))
                    .foregroundStyle(palette.textMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 15)
            .frame(height: 36)

        case .available:
            Button {
                Task { await updater.install() }
            } label: {
                Text(L.t(.updateInstall, locale))
                    .font(.ml(12.5, .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.textOnAccent)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(palette.accent)
                    .clipShape(Capsule())
            }
            .pressButton()

        default:
            Button {
                Task { await updater.check() }
            } label: {
                Text(L.t(.checkUpdates, locale))
                    .font(.ml(12.5, .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(palette.surface2)
                    .clipShape(Capsule())
            }
            .pressButton()
        }
    }

    private var progressLabel: L.Key {
        switch updater.state {
        case .checking: return .updateChecking
        case .installing: return .updateInstalling
        default: return .updateDownloading
        }
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
