import SwiftUI
import WidgetKit

/// Log: your saved foods and water, one tap each, without opening Bite. A tap logs at once and
/// the tile says so with an Undo for five minutes, as everywhere in Bite.
struct LogWidget: Widget {
    let kind = "log"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogProvider()) { entry in
            LogWidgetView(entry: entry)
        }
        .configurationDisplayName("Log")
        .description("Log your saved foods and water in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let foods: [WidgetStore.ShelfFood]
    let canRead: Bool
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

struct LogWidgetView: View {
    let entry: LogEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Theme.page }
            .widgetURL(URL(string: "bite://today"))
    }

    @ViewBuilder private var content: some View {
        if !entry.canRead {
            OpenBiteOnce()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Log")
                        .font(.ui(13, .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 6)
                    Text(headlineText)
                        .font(.ui(12))
                        .monospacedDigit()
                        .foregroundStyle(entry.snapshot.isOver ? Theme.over : Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if entry.foods.isEmpty {
                    Text("Save a food in Bite to log it here in one tap.")
                        .font(.ui(12))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(entry.foods.prefix(family == .systemSmall ? 1 : 3)) { food in
                            foodTile(food)
                        }
                        waterTile
                    }
                }
            }
        }
    }

    private func foodTile(_ food: WidgetStore.ShelfFood) -> some View {
        Group {
            if let addedAt = food.addedAt, let undoID = food.undoID {
                VStack(spacing: 4) {
                    FoodTile(emoji: food.emoji, tint: food.tint, photo: food.photo, size: 50)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.onTarget, Theme.page)
                                .offset(x: 4, y: 4)
                        }
                    Text("Added \(addedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.ui(10))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Button(intent: UndoWidgetLogIntent(entryID: undoID)) {
                        Text("Undo")
                            .font(.ui(11, .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(intent: LogSavedFoodIntent(food: food.entity)) {
                    VStack(spacing: 4) {
                        FoodTile(emoji: food.emoji, tint: food.tint, photo: food.photo, size: 50)
                        Text(food.name)
                            .font(.ui(11))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(food.kcal.kcalText) kcal")
                            .font(.ui(10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(food.name)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var waterTile: some View {
        Button(intent: AddWaterIntent()) {
            VStack(spacing: 4) {
                ZStack {
                    Theme.tint(.sky)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.water)
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text("Water")
                    .font(.ui(11))
                    .foregroundStyle(Theme.ink)
                Text("\(entry.snapshot.water) of \(entry.snapshot.waterGoal)")
                    .font(.ui(10))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Add a glass of water")
    }

    private var headlineText: String {
        let snapshot = entry.snapshot
        let number = snapshot.headline.kcalText
        switch snapshot.headlineKind {
        case .left: return String(localized: "\(number) kcal left")
        case .over: return String(localized: "\(number) kcal over")
        case .eaten: return String(localized: "\(number) kcal eaten")
        }
    }
}
