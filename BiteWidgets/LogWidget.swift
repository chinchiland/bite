import SwiftUI
import WidgetKit

/// Log: your saved foods and water, one tap each, without opening Bite. A tap logs at once and
/// the tile says so with an Undo for five minutes, as everywhere in Bite.
struct LogWidget: Widget {
    let kind = "log"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogProvider()) { entry in
            LogWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Log")
        .description("Log your saved foods and water in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogProvider: TimelineProvider {
    func placeholder(in context: Context) -> LogEntry {
        LogEntry(date: .now, snapshot: .sample, foods: [], canRead: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (LogEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Now; again when an Undo runs out; and at midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LogEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        var entries = [entry(at: now)]
        if let undoEnds = WidgetStore.undoEnds(now: now) {
            entries.append(entry(at: undoEnds.addingTimeInterval(1)))
        }
        entries.append(entry(at: midnight))
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }

    private func entry(at date: Date) -> LogEntry {
        let snapshot = WidgetStore.today(now: date)
        let left = snapshot.noTarget ? .infinity : snapshot.budget - snapshot.eaten.kcal
        return LogEntry(date: date, snapshot: snapshot, foods: WidgetStore.shelf(limit: 3, left: left, now: date), canRead: WidgetStore.canRead)
    }
}

/// The face, from Shared, with the family the widget is shown at.
struct LogWidgetEntryView: View {
    let entry: LogEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        LogWidgetView(entry: entry, family: family)
    }
}
