import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// "Log Morning skyr in Bite": adds a saved food to today without opening the app. Siri, the
/// Action button and the Log widget's tiles all run this.
struct LogSavedFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a saved food"
    static let description = IntentDescription("Adds one of your saved foods to today, with its usual amount.")

    @Parameter(title: "Food")
    var food: SavedFoodEntity

    init() {}

    init(food: SavedFoodEntity) {
        self.food = food
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(BiteStore.container)
        let foodID = food.id
        let descriptor = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.foodID == foodID })
        guard let item = try context.fetch(descriptor).first else {
            throw BiteIntentError.missingFood
        }
        let meal = item.meal ?? Meal.likely()
        let entry = FoodEntry(food: item.food, amount: item.amount, meal: meal, date: .now)
        entry.entryID = UUID()
        context.insert(entry)
        item.timesAdded += 1
        try context.save()
        LogStore.wrote(added: entry.entryID)
        let text = String(format: tr("Added %@ to %@, %@ kcal."), item.name, meal.title, item.totals.kcal.kcalText)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// A glass of water, from the widget or Control Center, without opening the app.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a glass of water"
    static let description = IntentDescription("Adds a glass of water to today.")

    func perform() async throws -> some IntentResult {
        try LogStore.changeWater(by: 1)
        return .result()
    }
}

/// The glass taken back: the widget's minus, which is its Undo for water.
struct RemoveWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Take back a glass of water"
    static let description = IntentDescription("Takes the last glass of water off today.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try LogStore.changeWater(by: -1)
        return .result()
    }
}

/// Undo for a food a widget just logged: it goes, as if never added.
struct UndoWidgetLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo"
    static let isDiscoverable = false

    @Parameter(title: "Entry")
    var entryID: String

    init() {}

    init(entryID: String) {
        self.entryID = entryID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: entryID) else { return .result() }
        let wanted: UUID? = id
        let context = ModelContext(BiteStore.container)
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.entryID == wanted })
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
        LogStore.wrote(added: nil, clearsUndo: true)
        return .result()
    }
}

enum BiteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case missingFood

    var localizedStringResource: LocalizedStringResource {
        "That saved food isn't on your shelf any more."
    }
}

/// A saved food as Siri, Shortcuts and the widgets see it.
struct SavedFoodEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved food"
    static let defaultQuery = SavedFoodQuery()

    let id: String
    let name: String
    let kcal: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(kcal.kcalText) kcal")
    }
}

struct SavedFoodQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SavedFoodEntity] {
        try shelf().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SavedFoodEntity] {
        try shelf()
    }

    private func shelf() throws -> [SavedFoodEntity] {
        let context = ModelContext(BiteStore.container)
        let items = try context.fetch(FetchDescriptor<SavedFood>(sortBy: [SortDescriptor(\.sortIndex)]))
        return items.map { SavedFoodEntity(id: $0.foodID, name: $0.name, kcal: $0.totals.kcal) }
    }
}

/// Writes made outside the app's screens: water from a widget, and the note that tells the app
/// to read the log again and the widgets to redraw.
enum LogStore {
    static func changeWater(by change: Int, now: Date = .now) throws {
        let context = ModelContext(BiteStore.container)
        let day = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<WaterDay>(predicate: #Predicate { $0.day == day })
        if let today = try context.fetch(descriptor).first {
            today.glasses = max(today.glasses + change, 0)
        } else if change > 0 {
            context.insert(WaterDay(day: day, glasses: change))
        }
        try context.save()
        wrote(added: nil)
    }

    /// The log changed outside the app's screens. A food a widget logged is kept for its Undo,
    /// until that Undo is used.
    static func wrote(added entryID: UUID?, clearsUndo: Bool = false) {
        let defaults = AppGroup.defaults
        let now = Date.now.timeIntervalSince1970
        defaults.set(now, forKey: AppGroup.Key.wroteAt)
        if let entryID {
            defaults.set(entryID.uuidString, forKey: AppGroup.Key.lastAddID)
            defaults.set(now, forKey: AppGroup.Key.lastAddAt)
        } else if clearsUndo {
            defaults.removeObject(forKey: AppGroup.Key.lastAddID)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
