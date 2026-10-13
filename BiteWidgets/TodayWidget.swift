import SwiftUI
import WidgetKit

/// Today: what is left and the ring, at a glance. Small, medium with the macros and water,
/// and the three Lock Screen sizes. Every tap opens Today.
struct TodayWidget: Widget {
    let kind = "today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("See what's left today and how your macros stand.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample, canRead: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    /// Now, then midnight, when the day starts again; the app asks for a redraw after each log.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> TodayEntry {
        TodayEntry(date: date, snapshot: WidgetStore.today(now: date), canRead: WidgetStore.canRead)
    }
}

/// The face, from Shared, with the family the widget is shown at.
struct TodayWidgetEntryView: View {
    let entry: TodayEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        TodayWidgetView(entry: entry, family: family)
    }
}
