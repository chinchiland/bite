import SwiftUI
import WidgetKit

/// Scan: one tap from the Home Screen or the Lock Screen to Bite's camera. It shows no data, so
/// one entry lasts forever.
struct ScanWidget: Widget {
    let kind = "scanTile"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScanProvider()) { _ in
            ScanWidgetEntryView()
        }
        .configurationDisplayName("Scan")
        .description("Open Bite on the camera, for your plate or a barcode.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct ScanEntry: TimelineEntry {
    let date: Date
}

struct ScanProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScanEntry { ScanEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ScanEntry) -> Void) {
        completion(ScanEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScanEntry>) -> Void) {
        completion(Timeline(entries: [ScanEntry(date: .now)], policy: .never))
    }
}

struct ScanWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ScanWidgetView(family: family)
    }
}

/// Water on the Lock Screen: the day's glasses as a ring, and a tap adds one.
struct WaterWidget: Widget {
    let kind = "waterRing"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            WaterWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Water")
        .description("Your glasses today. Tap to add one.")
        .supportedFamilies([.accessoryCircular])
    }
}
