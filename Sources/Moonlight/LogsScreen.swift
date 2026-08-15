import SwiftUI
import AppKit
import MoonlightDesign
import MoonlightCore

/// The log viewer.
///
/// Two sources on one timeline, and that pairing is the point: the core says
/// what happened to a connection, the client says what the app asked for. Read
/// apart, a failed connect is a core error with no cause; together it is "the
/// app switched to TUN, then the core could not take the route".
struct LogsScreen: View {
    @EnvironmentObject var tunnel: TunnelController
    @EnvironmentObject var logs: LogStore
    @Environment(\.palette) private var palette
    @Environment(\.appLocale) private var locale
    @Binding var page: Page

    @State private var source: LogEntry.Source?
    @State private var minimumLevel: LogEntry.Level = .info
    @State private var query = ""
    @State private var follow = true

    private var filtered: [LogEntry] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return logs.entries.filter { entry in
            if let source, entry.source != source { return false }
            guard Self.rank(entry.level) >= Self.rank(minimumLevel) else { return false }
            return text.isEmpty || entry.message.lowercased().contains(text)
        }
    }

    /// Levels are a floor, not a set: picking WARN means warnings *and* errors,
    /// which is what someone looking for a problem wants.
    private static func rank(_ level: LogEntry.Level) -> Int {
        switch level {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            table
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            SegmentedPill(
                selection: Binding(
                    get: { source ?? .client },
                    set: { source = $0 }
                ),
                options: [(LogEntry.Source.client, L.t(.logClient, locale)),
                          (LogEntry.Source.core, L.t(.logCore, locale))],
                height: 30
            )
            .frame(width: 190)
            .opacity(source == nil ? 0.55 : 1)

            Button {
                source = nil
            } label: {
                Text(L.t(.logAll, locale))
                    .font(.ml(12.5, .heavy))
                    .foregroundStyle(source == nil ? palette.textOnAccent : palette.textMuted)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(source == nil ? palette.accent : palette.surface2)
                    .clipShape(Capsule())
            }
            .pressButton()

            ForEach(LogEntry.Level.allCases, id: \.self) { level in
                Button {
                    minimumLevel = level
                } label: {
                    Text(level.label)
                        .font(.mlMono(11, .semibold))
                        .foregroundStyle(minimumLevel == level ? level.tint(palette) : palette.textMuted)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(minimumLevel == level
                                    ? level.tint(palette).opacity(0.16) : .clear)
                        .clipShape(Capsule())
                }
                .pressButton()
            }

            HStack(spacing: 8) {
                IconView(.search, size: 14).foregroundStyle(palette.textMuted)
                TextField(L.t(.searchApps, locale), text: $query)
                    .textFieldStyle(.plain)
                    .font(.ml(12.5))
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(palette.surface2)
            .clipShape(Capsule())

            Button {
                logs.clear()
            } label: {
                IconView(.trash2, size: 15)
                    .foregroundStyle(palette.textMuted)
                    .frame(width: 30, height: 30)
                    .background(palette.surface2)
                    .clipShape(Circle())
            }
            .pressIcon()
        }
    }

    private var table: some View {
        Panel(radius: Radii.card, padding: 0) {
            VStack(spacing: 0) {
                header
                palette.hairlineSoft.frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { entry in
                                LogRow(entry: entry).id(entry.id)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: filtered.count) { _ in
                        // Follow the tail, the way a terminal does, unless the
                        // reader has scrolled away to look at something.
                        guard follow, let last = filtered.last else { return }
                        withAnimation(Motion.paint) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                if filtered.isEmpty {
                    Text(L.t(.logEmpty, locale))
                        .font(.ml(TypeScale.meta))
                        .foregroundStyle(palette.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(L.t(.logTime, locale)).frame(width: 76, alignment: .leading)
            Text(L.t(.logLevel, locale)).frame(width: 62, alignment: .leading)
            Text(L.t(.logSource, locale)).frame(width: 74, alignment: .leading)
            Text(L.t(.logMessage, locale)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.ml(10.5, .heavy))
        .tracking(0.08 * 10.5)
        .foregroundStyle(palette.textMuted)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct LogRow: View {
    @Environment(\.palette) private var palette
    let entry: LogEntry

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(Self.clock.string(from: entry.at))
                .foregroundStyle(palette.textMuted)
                .frame(width: 76, alignment: .leading)
            Text(entry.level.label)
                .foregroundStyle(entry.level.tint(palette))
                .frame(width: 62, alignment: .leading)
            Text(entry.source.rawValue.uppercased())
                .foregroundStyle(palette.text2)
                .frame(width: 74, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.mlMono(11.5, .regular))
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

extension LogEntry.Level {
    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }

    func tint(_ palette: Palette) -> Color {
        switch self {
        case .debug: return palette.textMuted
        case .info: return palette.stUpInk
        case .warning: return palette.stDegradedInk
        case .error: return palette.stDownInk
        }
    }
}
