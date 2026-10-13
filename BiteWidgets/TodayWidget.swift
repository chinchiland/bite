import SwiftUI
import WidgetKit

/// Today: what is left and the ring, at a glance. Small, medium with the macros and water,
/// and the three Lock Screen sizes. Every tap opens Today.
struct TodayWidget: Widget {
    let kind = "today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("See what's left today and how your macros stand.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let canRead: Bool
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

struct TodayWidgetView: View {
    let entry: TodayEntry

    @Environment(\.widgetFamily) private var family

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        content
            .containerBackground(for: .widget) { Theme.page }
            .widgetURL(URL(string: "bite://today"))
    }

    @ViewBuilder private var content: some View {
        if !entry.canRead {
            OpenBiteOnce()
        } else {
            switch family {
            case .systemMedium: medium
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            default: small
            }
        }
    }

    private var small: some View {
        ZStack {
            WidgetRing(snapshot: snapshot)
            HeadlineNumber(snapshot: snapshot)
                .frame(maxWidth: 84)
        }
        .padding(2)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            ZStack {
                WidgetRing(snapshot: snapshot)
                HeadlineNumber(snapshot: snapshot, size: 28)
                    .frame(maxWidth: 80)
            }
            .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Macro.allCases, id: \.self) { macro in
                    macroLine(macro)
                }
                waterLine
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func macroLine(_ macro: Macro) -> some View {
        let grams = grams(of: macro)
        let target = target(of: macro)
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                GlyphTile(macro: macro, size: 18)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(grams.gramsText)
                        .font(.number(13, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: " / \(target.kcalText) g")
                        .font(.ui(11))
                        .foregroundStyle(Theme.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(macro.color)
                        .frame(width: proxy.size.width * min(target > 0 ? grams / target : 0, 1))
                        .widgetAccentable()
                }
            }
            .frame(height: 3)
            .padding(.leading, 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.title): \(grams.gramsText) of \(target.kcalText) grams")
    }

    private var waterLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.water)
            Text("\(snapshot.water) of \(snapshot.waterGoal)")
                .font(.ui(12))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Button(intent: RemoveWaterIntent()) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take back a glass of water")
            Button(intent: AddWaterIntent()) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a glass of water")
        }
        .foregroundStyle(Theme.ink)
    }

    private var circular: some View {
        Gauge(value: snapshot.progress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text(snapshot.headline.kcalText)
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(headlineText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(headlineText)
                    .font(.ui(15, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: "flame.fill")
            }
            HStack(spacing: 8) {
                ForEach(Macro.allCases, id: \.self) { macro in
                    let share = target(of: macro) > 0 ? min(grams(of: macro) / target(of: macro), 1) : 0
                    Gauge(value: share) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .accessibilityLabel(macro.title)
                }
            }
        }
    }

    private var inline: some View {
        Label(headlineText, systemImage: "flame.fill")
    }

    /// "967 kcal left", "450 kcal over" or "2,450 kcal eaten".
    private var headlineText: String {
        let number = snapshot.headline.kcalText
        switch snapshot.headlineKind {
        case .left: return String(localized: "\(number) kcal left")
        case .over: return String(localized: "\(number) kcal over")
        case .eaten: return String(localized: "\(number) kcal eaten")
        }
    }

    private func grams(of macro: Macro) -> Double {
        switch macro {
        case .protein: snapshot.eaten.protein
        case .carbs: snapshot.eaten.carbs
        case .fat: snapshot.eaten.fat
        }
    }

    private func target(of macro: Macro) -> Double {
        switch macro {
        case .protein: snapshot.targets.protein
        case .carbs: snapshot.targets.carbs
        case .fat: snapshot.targets.fat
        }
    }
}
