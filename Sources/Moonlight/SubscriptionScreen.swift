import SwiftUI
import AppKit
import MoonlightDesign
import MoonlightCore

struct SubscriptionScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    var body: some View {
        ScrollView {
            columns.padding(.bottom, 8)
        }
        .scrollIndicators(.never)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 14) {
                planCard.rise(0, page)
                trafficCard.rise(0.06, page)
            }
            VStack(spacing: 14) {
                refreshRow.rise(0.1, page)
                actionRows.rise(0.16, page)
            }
            .frame(width: 360)
        }
    }

    // MARK: - Plan

    private var planCard: some View {
        // The wash is a background rather than a ZStack sibling: a 280pt circle
        // laid out alongside the content would set the card's height, leaving a
        // slab of empty accent below the stats.
        VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t(.plan, locale))
                            .font(.ml(TypeScale.meta, .heavy))
                            .opacity(0.6)
                        Text(tunnel.info.title ?? L.t(.planUnknown, locale))
                            .font(.mlDisplay(36))
                            .tracking(TypeScale.trackDisplay * 36)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(L.t(tunnel.info.isActive ? .active : .expired, locale))
                        .font(.ml(TypeScale.micro, .heavy))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(palette.inkWash)
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    heroStat(L.t(.remainingCaps, locale),
                             Format.days(tunnel.info.daysLeft, locale: locale))
                    heroStat(L.t(.traffic, locale),
                             Format.bytes(tunnel.info.used, locale: locale))
                    heroStat(L.t(.devices, locale), deviceText)
                }
                .padding(.top, 22)
            }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .foregroundStyle(palette.textOnAccent)
        .background(alignment: .bottomTrailing) {
            Circle()
                .fill(palette.inkWashSoft)
                .frame(width: 280, height: 280)
                .offset(x: 80, y: 140)
        }
        .background(palette.accent)
        .clipShape(RoundedRectangle(cornerRadius: Radii.panel, style: .continuous))
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.ml(10.5, .heavy))
                .tracking(0.06 * 10.5)
                .opacity(0.65)
            Text(value)
                .font(.mlDisplay(18))
                .tracking(TypeScale.trackDisplay * 18)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceText: String {
        guard let limit = tunnel.info.deviceLimit else { return "—" }
        return "\(tunnel.info.devicesUsed ?? 1) / \(limit)"
    }

    // MARK: - Traffic

    private var trafficCard: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Overline(text: L.t(.trafficCaps, locale))
                    Spacer()
                    Text(Format.quota(used: tunnel.info.used,
                                      total: tunnel.info.total, locale: locale))
                        .font(.ml(TypeScale.meta, .bold))
                        .foregroundStyle(palette.text2)
                }
                QuotaBar(fraction: tunnel.info.usedFraction).padding(.top, 14)
                Text(expiryLine)
                    .font(.ml(TypeScale.meta))
                    .foregroundStyle(palette.textMuted)
                    .padding(.top, 12)
            }
        }
    }

    private var expiryLine: String {
        guard let expire = tunnel.info.expire else { return L.t(.unlimited, locale) }
        return "\(L.t(.validUntil, locale)) \(Format.date(expire, locale: locale))"
    }

    // MARK: - Actions

    private var refreshRow: some View {
        RowGroup {
            ActionRow(
                icon: .refreshCW,
                fill: palette.cat1,
                title: L.t(.refreshSubscription, locale),
                subtitle: refreshMeta,
                trailing: nil,
                spinning: tunnel.isRefreshing
            ) {
                Task { await tunnel.refresh() }
            }
        }
    }

    private var refreshMeta: String {
        if tunnel.isRefreshing { return L.t(.refreshMetaSyncing, locale) }
        if let last = tunnel.lastRefresh, Date().timeIntervalSince(last) < 120 {
            return L.t(.refreshMetaDone, locale)
        }
        return L.t(.refreshMetaIdle, locale)
    }

    private var actionRows: some View {
        RowGroup {
            ActionRow(
                icon: .sparkles,
                fill: palette.cat2,
                title: L.t(.extendSubscription, locale),
                subtitle: L.t(.extendSubtitle, locale),
                trailing: .externalLink
            ) {
                NSWorkspace.shared.open(AppConfig.telegramBotURL)
            }
            RowDivider(leading: 74)
            ActionRow(
                icon: .plus,
                fill: palette.cat4,
                title: L.t(.addSubscriptionRow, locale),
                subtitle: L.t(.addSubscriptionSubtitle, locale)
            ) {
                page = .importSubscription
            }
            if tunnel.hasSubscription {
                RowDivider(leading: 74)
                ActionRow(
                    icon: .trash2,
                    fill: palette.cat5,
                    title: L.t(.removeSubscription, locale),
                    subtitle: tunnel.subscriptionURL ?? "",
                    trailing: nil
                ) {
                    Task { await tunnel.removeSubscription() }
                }
            }
        }
    }

}
