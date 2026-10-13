import Foundation
import ImageIO
import SwiftData
import UIKit

/// What the widgets read: today from the shared log, the settings the app mirrors into the App
/// Group, and the shelf for the Log widget. Bite Demo's widgets draw its sample day.
enum WidgetStore {
    /// False in a copy signed without the App Group, or before Bite has been opened once: the
    /// widgets then say so instead of showing an empty day.
    static var canRead: Bool {
        #if BITE_DEMO
        return true
        #else
        guard let url = AppGroup.storeURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
        #endif
    }

    static func today(now: Date = .now) -> WidgetSnapshot {
        #if BITE_DEMO
        return .sample
        #else
        let settings = AppGroup.defaults
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard canRead, let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return .make(day: .zero, goal: 2000)
        }
        let goal = Double(settings.object(forKey: AppGroup.Key.goal) as? Int ?? 2000)
        let split = MacroSplit(rawValue: settings.string(forKey: AppGroup.Key.split) ?? "") ?? .balanced
        let burnedToday = settings.double(forKey: AppGroup.Key.burnedDay) == start.timeIntervalSince1970
        let burned = settings.bool(forKey: AppGroup.Key.addBurned) && burnedToday ? settings.double(forKey: AppGroup.Key.burned) : 0
        let context = ModelContext(BiteStore.container)
        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterDay>(predicate: #Predicate { $0.day == start })))?.first?.glasses ?? 0
        return .make(
            day: entries.reduce(Nutrients.zero) { $0 + $1.totals },
            goal: goal,
            burned: burned,
            split: split,
            water: water,
            waterGoal: settings.object(forKey: AppGroup.Key.waterGoal) as? Int ?? 8,
            noTarget: settings.bool(forKey: AppGroup.Key.noTarget)
        )
        #endif
    }

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

    /// How long a widget's Undo stays.
    static let undoWindow: TimeInterval = 5 * 60

    /// The shelf's foods for the Log widget: the ones that fit what is left first, then the
    /// shelf's own order, as Today orders them.
    static func shelf(limit: Int, left: Double, now: Date = .now) -> [ShelfFood] {
        #if BITE_DEMO
        let sample: [ShelfFood] = [
            ShelfFood(id: "demo:skyr", name: tr("Morning skyr"), kcal: 68, emoji: "🥣", tint: .butter, photo: nil),
            ShelfFood(id: "demo:coffee", name: tr("Coffee, black"), kcal: 2, emoji: "☕", tint: .sky, photo: nil),
            ShelfFood(id: "demo:almonds", name: tr("Almonds"), kcal: 162, emoji: "🌰", tint: .sand, photo: nil),
        ]
        return Array(sample.prefix(limit))
        #else
        guard canRead else { return [] }
        let context = ModelContext(BiteStore.container)
        let items = (try? context.fetch(FetchDescriptor<SavedFood>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        let ordered = items.enumerated().sorted { a, b in
            let fitsA = left > 0 && a.element.totals.kcal <= left
            let fitsB = left > 0 && b.element.totals.kcal <= left
            if fitsA != fitsB { return fitsA }
            return a.offset < b.offset
        }
        .map(\.element)
        let recent = lastAdd(now: now, in: context)
        return ordered.prefix(limit).map { item in
            var food = ShelfFood(
                id: item.foodID,
                name: item.name,
                kcal: item.totals.kcal,
                emoji: item.emoji,
                tint: FoodTint(rawValue: item.tintRaw) ?? .sand,
                photo: item.emoji == nil ? item.imageData.flatMap { thumbnail($0, pixels: 150) } : nil
            )
            if let recent, recent.foodID == item.foodID {
                food.addedAt = recent.at
                food.undoID = recent.id
            }
            return food
        }
        #endif
    }

    /// The food a widget logged last, while its Undo is offered.
    private static func lastAdd(now: Date, in context: ModelContext) -> (id: String, foodID: String, at: Date)? {
        let settings = AppGroup.defaults
        let at = Date(timeIntervalSince1970: settings.double(forKey: AppGroup.Key.lastAddAt))
        guard now.timeIntervalSince(at) < undoWindow,
              let id = settings.string(forKey: AppGroup.Key.lastAddID),
              let uuid = UUID(uuidString: id) else { return nil }
        let wanted: UUID? = uuid
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.entryID == wanted })
        guard let entry = try? context.fetch(descriptor).first else { return nil }
        return (id: id, foodID: entry.foodID, at: at)
    }

    /// When the widget's Undo ends, for the timeline.
    static func undoEnds(now: Date = .now) -> Date? {
        let at = Date(timeIntervalSince1970: AppGroup.defaults.double(forKey: AppGroup.Key.lastAddAt))
        let end = at.addingTimeInterval(undoWindow)
        return end > now && AppGroup.defaults.string(forKey: AppGroup.Key.lastAddID) != nil ? end : nil
    }

    /// A photo at the size a tile shows it, decoded small: widgets have little memory.
    private static func thumbnail(_ data: Data, pixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
