import SwiftUI
import WidgetKit

// Data is written by lib/services/home_widget_bridge.dart through home_widget
// into the shared App Group below.
private let appGroupId = "group.dev.tokenbar.app"

struct QuotaRow: Identifiable {
    let id: Int
    let name: String
    let session: Int  // remaining %, -1 when unknown
    let weekly: Int
    let detail: String
}

struct QuotaEntry: TimelineEntry {
    let date: Date
    let updated: String
    let rows: [QuotaRow]
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), updated: "", rows: [
            QuotaRow(id: 0, name: "Codex", session: 72, weekly: 64, detail: "2小时后重置"),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        // The app pushes updates via HomeWidget.updateWidget; this is a fallback reload.
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> QuotaEntry {
        let d = UserDefaults(suiteName: appGroupId)
        let count = min(d?.integer(forKey: "tb_count") ?? 0, 4)
        let rows = (0..<count).map { i in
            QuotaRow(
                id: i,
                name: d?.string(forKey: "tb_\(i)_name") ?? "",
                session: (d?.object(forKey: "tb_\(i)_session") as? Int) ?? -1,
                weekly: (d?.object(forKey: "tb_\(i)_weekly") as? Int) ?? -1,
                detail: d?.string(forKey: "tb_\(i)_detail") ?? ""
            )
        }
        return QuotaEntry(date: Date(), updated: d?.string(forKey: "tb_updated") ?? "", rows: rows)
    }
}

private func quotaColor(_ remaining: Int) -> Color {
    if remaining < 0 { return .gray }
    if remaining > 50 { return Color(red: 0.20, green: 0.83, blue: 0.60) }
    if remaining > 20 { return Color(red: 0.98, green: 0.75, blue: 0.14) }
    return Color(red: 0.97, green: 0.44, blue: 0.44)
}

struct TokenBarWidgetView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TokenBar").font(.caption).bold()
                Spacer()
                Text(entry.updated).font(.caption2).foregroundStyle(.secondary)
            }
            if entry.rows.isEmpty {
                Text("打开 TokenBar 同步额度数据").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(entry.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.name).font(.caption2).lineLimit(1)
                        Spacer()
                        Text(row.session < 0 ? "—" : "\(row.session)%")
                            .font(.caption).bold()
                            .foregroundStyle(quotaColor(row.session))
                    }
                    ProgressView(value: Double(max(row.session, 0)), total: 100)
                        .tint(quotaColor(row.session))
                    Text([row.weekly >= 0 ? "周 \(row.weekly)%" : nil, row.detail.isEmpty ? nil : row.detail]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        // Same deep-indigo "liquid glass" gradient as the Android widget and the dark theme.
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.14, green: 0.12, blue: 0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .environment(\.colorScheme, .dark)
    }
}

@main
struct TokenBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBarWidget", provider: QuotaProvider()) { entry in
            TokenBarWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenBar")
        .description("AI 额度剩余与重置倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
