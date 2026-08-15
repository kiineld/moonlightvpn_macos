import SwiftUI
import MoonlightCore

/// Russian and English, with Russian as the source of truth.
///
/// The design is written in Russian and its strings are the specification — the
/// English column is a translation of them, not the other way round. Strings
/// live in one table rather than in `.strings` files because the language
/// switch in Settings changes them live, and a bundle-based lookup would need a
/// relaunch to follow.
public enum L {

    public static func t(_ key: Key, _ locale: AppLocale) -> String {
        locale == .ru ? key.ru : key.en
    }

    public enum Key {
        // Navigation and page headers
        case navConnect, navSubscription, navApps, navSettings
        case titleConnect, subtitleConnect
        case titleSubscription, subtitleSubscription
        case titleApps, subtitleApps
        case titleSettings, subtitleSettings
        case titleImport, subtitleImport

        // Header actions
        case ping, pinging, refresh, refreshing, theme

        // Connect
        case secured, disconnected, connecting, disconnecting
        case bigConnect, bigConnected
        case hintConnect, hintDisconnect
        case downloaded, uploaded, remaining
        case servers, nodesCount, auto, autoSubtitle, autoPicked
        case noSubscription, noSubscriptionHint, addSubscription

        // Sidebar card
        case remainingCaps, active, expired, trafficOf

        // Subscription
        case plan, planUnknown, traffic, devices
        case trafficCaps, subscriptionLink, copy, copied
        case refreshSubscription, refreshMetaIdle, refreshMetaSyncing, refreshMetaDone
        case extendSubscription, extendSubtitle
        case addSubscriptionRow, addSubscriptionSubtitle
        case devicesCaps, thisDevice, slotsFree, validUntil, unlimited
        case sourceMihomo, sourceClash, sourceShareLinks

        // Import
        case importIntro, importPlaceholder, importAdd
        case pasteFromClipboard, openTelegramBot, telegramBotSubtitle
        case backToSubscription, importDone, importDoneSubtitle, connectNow
        case removeSubscription

        // Apps / split tunnelling
        case splitAll, splitOnly, splitExcept
        case splitHintAll, splitHintOnly, splitHintExcept
        case splitNeedsTun, splitNeedsTunAction, splitSummaryAll, splitSummaryCount
        case searchApps, runningNow, installedApps, noApps, rules, rulesHelp

        // Settings
        case sectionSystem, sectionApp, sectionSupport, sectionTunnel
        case launchAtLogin, launchAtLoginSub
        case menuBarIcon, menuBarIconSub
        case autoConnect, autoConnectSub
        case splitTunnelling
        case language, notifications, notificationsSub
        case ourChannel, ourChannelSub, support, supportSub
        case version, checkUpdates, keysStayHere
        case modeSystemProxy, modeSystemProxySub, modeTun, modeTunSub
        case helperInstall, helperInstallSub, helperRemove, helperInstalled
        case coreVersion, viewLog, viewLogSub, install, remove

        var ru: String {
            switch self {
            case .navConnect: return "Подключение"
            case .navSubscription: return "Подписка"
            case .navApps: return "Приложения"
            case .navSettings: return "Настройки"
            case .titleConnect: return "Подключение"
            case .subtitleConnect: return "Выберите узел и включите туннель"
            case .titleSubscription: return "Подписка"
            case .subtitleSubscription: return "Тариф и трафик"
            case .titleApps: return "Приложения"
            case .subtitleApps: return "Какой трафик идёт через туннель"
            case .titleSettings: return "Настройки"
            case .subtitleSettings: return "Система, приложение и поддержка"
            case .titleImport: return "Добавить подписку"
            case .subtitleImport: return "Ссылка из бота или личного кабинета"

            case .ping: return "Пинг"
            case .pinging: return "Замер…"
            case .refresh: return "Обновить"
            case .refreshing: return "Обновление"
            case .theme: return "Тема"

            case .secured: return "Защищено"
            case .disconnected: return "Отключено"
            case .connecting: return "Подключение"
            case .disconnecting: return "Отключение"
            case .bigConnect: return "Подключить"
            case .bigConnected: return "Соединение"
            case .hintConnect: return "нажмите, чтобы подключиться"
            case .hintDisconnect: return "нажмите, чтобы отключить"
            case .downloaded: return "СКАЧАНО"
            case .uploaded: return "ОТДАНО"
            case .remaining: return "ОСТАЛОСЬ"
            case .servers: return "СЕРВЕРЫ"
            case .nodesCount: return "узлов"
            case .auto: return "Авто"
            case .autoSubtitle: return "Ближайший узел по пингу"
            case .autoPicked: return "Выбран"
            case .noSubscription: return "Нет подписки"
            case .noSubscriptionHint: return "Добавьте ссылку из бота, чтобы увидеть серверы"
            case .addSubscription: return "Добавить подписку"

            case .remainingCaps: return "ОСТАЛОСЬ"
            case .active: return "Активна"
            case .expired: return "Истекла"
            case .trafficOf: return "трафика"

            case .plan: return "Тариф"
            case .planUnknown: return "Подписка"
            case .traffic: return "ТРАФИК"
            case .devices: return "УСТРОЙСТВА"
            case .trafficCaps: return "ТРАФИК"
            case .subscriptionLink: return "ССЫЛКА ПОДПИСКИ"
            case .copy: return "Скопировать"
            case .copied: return "Скопировано"
            case .refreshSubscription: return "Обновить подписку"
            case .refreshMetaIdle: return "Проверить серверы, дни и трафик"
            case .refreshMetaSyncing: return "Синхронизация с сервером…"
            case .refreshMetaDone: return "Обновлено только что"
            case .extendSubscription: return "Продлить подписку"
            case .extendSubtitle: return "Откроется личный кабинет"
            case .addSubscriptionRow: return "Добавить подписку"
            case .addSubscriptionSubtitle: return "Вставить ссылку из бота"
            case .devicesCaps: return "УСТРОЙСТВА"
            case .thisDevice: return "это устройство"
            case .slotsFree: return "Свободно"
            case .validUntil: return "действует до"
            case .unlimited: return "без лимита"
            case .sourceMihomo: return "Конфигурация панели (mihomo)"
            case .sourceClash: return "Конфигурация панели (clash)"
            case .sourceShareLinks: return "Список ссылок — группы и правила панели недоступны"

            case .importIntro:
                return "Вставьте ссылку подписки из Telegram-бота или личного кабинета. Ключи останутся на этом компьютере."
            case .importPlaceholder: return "https://sub.moonlight.vpn/…"
            case .importAdd: return "Добавить"
            case .pasteFromClipboard: return "Вставить из буфера"
            case .openTelegramBot: return "Открыть Telegram-бота"
            case .telegramBotSubtitle: return "Ссылка придёт в чат и добавится сама"
            case .backToSubscription: return "Назад к подписке"
            case .importDone: return "Подписка активирована!"
            case .importDoneSubtitle: return "Готово к подключению"
            case .connectNow: return "Подключиться"
            case .removeSubscription: return "Удалить подписку"

            case .splitAll: return "Весь трафик"
            case .splitOnly: return "Только эти"
            case .splitExcept: return "Кроме этих"
            case .splitHintAll: return "Через туннель идёт весь трафик компьютера."
            case .splitHintOnly: return "Через туннель пойдут только отмеченные программы — остальные напрямую."
            case .splitHintExcept: return "Отмеченные программы пойдут напрямую, весь остальной трафик — через туннель."
            case .splitNeedsTun:
                return "Правила PROCESS-* не работают: системный прокси не показывает ядру, какая программа открыла соединение. Остальные правила действуют."
            case .splitNeedsTunAction: return "Включить TUN"
            case .splitSummaryAll: return "Весь трафик"
            case .splitSummaryCount: return "прогр."
            case .searchApps: return "Поиск"
            case .runningNow: return "Запущено"
            case .installedApps: return "ПРОГРАММЫ"
            case .noApps: return "Ничего не найдено"
            case .rules: return "ПРАВИЛА"
            case .rulesHelp: return "Правила по доменам, адресам и портам работают в обоих режимах. PROCESS-* требуют TUN."

            case .sectionSystem: return "СИСТЕМА"
            case .sectionApp: return "ПРИЛОЖЕНИЕ"
            case .sectionSupport: return "ПОДДЕРЖКА"
            case .sectionTunnel: return "ТУННЕЛЬ"
            case .launchAtLogin: return "Запускать при входе в систему"
            case .launchAtLoginSub: return "Клиент стартует свёрнутым"
            case .menuBarIcon: return "Значок в строке меню"
            case .menuBarIconSub: return "Управление подключением из строки меню"
            case .autoConnect: return "Подключаться автоматически"
            case .autoConnectSub: return "Сразу после запуска клиента"
            case .splitTunnelling: return "Раздельное туннелирование"
            case .language: return "Язык"
            case .notifications: return "Уведомления"
            case .notificationsSub: return "Об окончании подписки и трафика"
            case .ourChannel: return "Наш канал"
            case .ourChannelSub: return "Новости и обновления"
            case .support: return "Поддержка"
            case .supportSub: return "Мы на связи 24/7"
            case .version: return "Версия"
            case .checkUpdates: return "Проверить обновления"
            case .keysStayHere: return "Ключи хранятся только на этом компьютере"
            case .modeSystemProxy: return "Системный прокси"
            case .modeSystemProxySub: return "Без пароля. Идут только программы, которые уважают настройки прокси"
            case .modeTun: return "TUN"
            case .modeTunSub: return "Весь трафик и правила по программам. Нужен системный помощник"
            case .helperInstall: return "Установить помощник"
            case .helperInstallSub: return "Один запрос пароля администратора"
            case .helperRemove: return "Удалить помощник"
            case .helperInstalled: return "Помощник установлен"
            case .coreVersion: return "Ядро"
            case .viewLog: return "Журнал ядра"
            case .viewLogSub: return "Последние строки от mihomo"
            case .install: return "Установить"
            case .remove: return "Удалить"
            }
        }

        var en: String {
            switch self {
            case .navConnect: return "Connection"
            case .navSubscription: return "Subscription"
            case .navApps: return "Apps"
            case .navSettings: return "Settings"
            case .titleConnect: return "Connection"
            case .subtitleConnect: return "Pick a node and switch the tunnel on"
            case .titleSubscription: return "Subscription"
            case .subtitleSubscription: return "Plan and traffic"
            case .titleApps: return "Apps"
            case .subtitleApps: return "Which traffic goes through the tunnel"
            case .titleSettings: return "Settings"
            case .subtitleSettings: return "System, app and support"
            case .titleImport: return "Add a subscription"
            case .subtitleImport: return "A link from the bot or your account"

            case .ping: return "Ping"
            case .pinging: return "Measuring…"
            case .refresh: return "Refresh"
            case .refreshing: return "Refreshing"
            case .theme: return "Theme"

            case .secured: return "Secured"
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .disconnecting: return "Disconnecting"
            case .bigConnect: return "Connect"
            case .bigConnected: return "Connected"
            case .hintConnect: return "click to connect"
            case .hintDisconnect: return "click to disconnect"
            case .downloaded: return "DOWNLOADED"
            case .uploaded: return "UPLOADED"
            case .remaining: return "REMAINING"
            case .servers: return "SERVERS"
            case .nodesCount: return "nodes"
            case .auto: return "Auto"
            case .autoSubtitle: return "Fastest node by latency"
            case .autoPicked: return "Using"
            case .noSubscription: return "No subscription"
            case .noSubscriptionHint: return "Add a link from the bot to see servers"
            case .addSubscription: return "Add a subscription"

            case .remainingCaps: return "REMAINING"
            case .active: return "Active"
            case .expired: return "Expired"
            case .trafficOf: return "of traffic"

            case .plan: return "Plan"
            case .planUnknown: return "Subscription"
            case .traffic: return "TRAFFIC"
            case .devices: return "DEVICES"
            case .trafficCaps: return "TRAFFIC"
            case .subscriptionLink: return "SUBSCRIPTION LINK"
            case .copy: return "Copy"
            case .copied: return "Copied"
            case .refreshSubscription: return "Refresh subscription"
            case .refreshMetaIdle: return "Check servers, days and traffic"
            case .refreshMetaSyncing: return "Syncing with the panel…"
            case .refreshMetaDone: return "Updated just now"
            case .extendSubscription: return "Extend subscription"
            case .extendSubtitle: return "Opens your account"
            case .addSubscriptionRow: return "Add a subscription"
            case .addSubscriptionSubtitle: return "Paste a link from the bot"
            case .devicesCaps: return "DEVICES"
            case .thisDevice: return "this device"
            case .slotsFree: return "Free"
            case .validUntil: return "valid until"
            case .unlimited: return "unlimited"
            case .sourceMihomo: return "Panel configuration (mihomo)"
            case .sourceClash: return "Panel configuration (clash)"
            case .sourceShareLinks: return "Share-link list — the panel's groups and rules are not available"

            case .importIntro:
                return "Paste the subscription link from the Telegram bot or your account. The keys stay on this computer."
            case .importPlaceholder: return "https://sub.moonlight.vpn/…"
            case .importAdd: return "Add"
            case .pasteFromClipboard: return "Paste from clipboard"
            case .openTelegramBot: return "Open the Telegram bot"
            case .telegramBotSubtitle: return "The link arrives in the chat and adds itself"
            case .backToSubscription: return "Back to subscription"
            case .importDone: return "Subscription activated!"
            case .importDoneSubtitle: return "Ready to connect"
            case .connectNow: return "Connect"
            case .removeSubscription: return "Remove subscription"

            case .splitAll: return "All traffic"
            case .splitOnly: return "Only these"
            case .splitExcept: return "Except these"
            case .splitHintAll: return "Every connection on this computer goes through the tunnel."
            case .splitHintOnly: return "Only the selected apps go through the tunnel — everything else goes direct."
            case .splitHintExcept: return "The selected apps go direct; all other traffic goes through the tunnel."
            case .splitNeedsTun:
                return "PROCESS-* rules do not match: a system proxy never tells the core which app opened a connection. The other rules still apply."
            case .splitNeedsTunAction: return "Switch to TUN"
            case .splitSummaryAll: return "All traffic"
            case .splitSummaryCount: return "apps"
            case .searchApps: return "Search"
            case .runningNow: return "Running"
            case .installedApps: return "APPS"
            case .noApps: return "Nothing found"
            case .rules: return "RULES"
            case .rulesHelp: return "Domain, address and port rules work in both modes. PROCESS-* rules need TUN."

            case .sectionSystem: return "SYSTEM"
            case .sectionApp: return "APP"
            case .sectionSupport: return "SUPPORT"
            case .sectionTunnel: return "TUNNEL"
            case .launchAtLogin: return "Launch at login"
            case .launchAtLoginSub: return "Starts minimised"
            case .menuBarIcon: return "Menu bar icon"
            case .menuBarIconSub: return "Control the connection from the menu bar"
            case .autoConnect: return "Connect automatically"
            case .autoConnectSub: return "Right after the client starts"
            case .splitTunnelling: return "Split tunnelling"
            case .language: return "Language"
            case .notifications: return "Notifications"
            case .notificationsSub: return "When the plan or traffic runs out"
            case .ourChannel: return "Our channel"
            case .ourChannelSub: return "News and updates"
            case .support: return "Support"
            case .supportSub: return "We answer 24/7"
            case .version: return "Version"
            case .checkUpdates: return "Check for updates"
            case .keysStayHere: return "Keys are kept only on this computer"
            case .modeSystemProxy: return "System proxy"
            case .modeSystemProxySub: return "No password. Only apps that honour proxy settings are captured"
            case .modeTun: return "TUN"
            case .modeTunSub: return "All traffic and per-app rules. Needs the system helper"
            case .helperInstall: return "Install the helper"
            case .helperInstallSub: return "One administrator prompt"
            case .helperRemove: return "Remove the helper"
            case .helperInstalled: return "Helper installed"
            case .coreVersion: return "Core"
            case .viewLog: return "Core log"
            case .viewLogSub: return "The last lines from mihomo"
            case .install: return "Install"
            case .remove: return "Remove"
            }
        }
    }
}

private struct LocaleKey: EnvironmentKey {
    static let defaultValue = AppLocale.ru
}

extension EnvironmentValues {
    var appLocale: AppLocale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
}

extension View {
    /// `Text(L.t(.navConnect, locale))` at every call site is noise; this keeps
    /// the string table lookup to one short form.
    func mlLocale(_ locale: AppLocale) -> some View {
        environment(\.appLocale, locale)
    }
}
