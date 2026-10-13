import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// The widgets' faces. They live in Shared so the app can draw them too (a Debug gallery shows
// every size for screenshots); the widget extension only adds the timelines around them. Each
// takes its family as a value, since only a widget reads it from the environment.

/// Today: what is left and the ring, at a glance.
struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let canRead: Bool
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    let family: WidgetFamily

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
        .accessibilityLabel(snapshot.headlineText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(snapshot.headlineText)
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
        Label(snapshot.headlineText, systemImage: "flame.fill")
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

extension WidgetSnapshot {
    /// "967 kcal left", "450 kcal over" or "2,450 kcal eaten".
    var headlineText: String {
        let number = headline.kcalText
        switch headlineKind {
        case .left: return String(localized: "\(number) kcal left")
        case .over: return String(localized: "\(number) kcal over")
        case .eaten: return String(localized: "\(number) kcal eaten")
        }
    }
}

// MARK: - Log

/// A saved food as a Log widget tile.
struct ShelfFood: Identifiable {
    let id: String
    let name: String
    let kcal: Double
    let emoji: String?
    let tint: FoodTint
    let photo: UIImage?
    /// Logged from this widget in the last five minutes: the tile says so and offers Undo.
    var addedAt: Date?
    var undoID: String?

    var entity: SavedFoodEntity { SavedFoodEntity(id: id, name: name, kcal: kcal) }
}

/// Log: your saved foods and water, one tap each, without opening Bite.
struct LogEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let foods: [ShelfFood]
    let canRead: Bool
}

struct LogWidgetView: View {
    let entry: LogEntry
    let family: WidgetFamily

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
                    Text(entry.snapshot.headlineText)
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

    private func foodTile(_ food: ShelfFood) -> some View {
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
}

// MARK: - Scan and water

/// Scan: the fastest way in, one tap from the Home Screen or the Lock Screen, opening Bite on
/// the camera. It shows no data, so it never goes stale.
struct ScanWidgetView: View {
    let family: WidgetFamily

    var body: some View {
        content
            .containerBackground(for: .widget) { Theme.ink }
            .widgetURL(URL(string: "bite://scan"))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .medium))
                    .widgetAccentable()
            }
            .accessibilityLabel("Scan food")
        default:
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.page)
                    .frame(width: 52, height: 52)
                    .background(Theme.page.opacity(0.14), in: Circle())
                Spacer(minLength: 8)
                Text("Snap a meal")
                    .font(.ui(17, .semibold))
                    .foregroundStyle(Theme.page)
                Text("or scan a barcode")
                    .font(.ui(13))
                    .foregroundStyle(Theme.page.opacity(0.7))
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Water on the Lock Screen: the day's glasses as a ring; a tap adds one, without opening Bite.
struct WaterWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Button(intent: AddWaterIntent()) {
            Gauge(value: Double(min(snapshot.water, snapshot.waterGoal)), in: 0...Double(max(snapshot.waterGoal, 1))) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(verbatim: "\(snapshot.water)")
            }
            .gaugeStyle(.accessoryCircular)
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityLabel("\(snapshot.water) of \(snapshot.waterGoal) glasses. Add a glass of water")
    }
}
