import AppIntents
import Foundation
import Observation
import SwiftData

/// Things the system asks the app to do when it opens: scan straight away, for the Action
/// button, Siri or a Control Center shortcut.
@MainActor
@Observable
final class AppActions {
    static let shared = AppActions()
    var pendingScan = false
}

/// "Scan food with Bite": opens on the camera. Put it on the Action button to scan in one
/// press.
struct ScanFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan food"
    static let description = IntentDescription("Opens Bite on the camera, ready for a barcode or your plate.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppActions.shared.pendingScan = true }
        return .result()
    }
}

/// "Log Morning skyr in Bite": adds a saved food to today without opening the app.
struct LogSavedFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a saved food"
    static let description = IntentDescription("Adds one of your saved foods to today, with its usual amount.")

    @Parameter(title: "Food")
    var food: SavedFoodEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(BiteStore.container)
        let foodID = food.id
        let descriptor = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.foodID == foodID })
        guard let item = try context.fetch(descriptor).first else {
            throw BiteIntentError.missingFood
        }
        let meal = item.meal ?? Meal.likely()
        context.insert(FoodEntry(food: item.food, amount: item.amount, meal: meal, date: .now))
        item.timesAdded += 1
        try context.save()
        let text = String(format: tr("Added %@ to %@, %@ kcal."), item.name, meal.title, item.totals.kcal.kcalText)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

enum BiteIntentError: Error, CustomLocalizedStringResourceConvertible {
    case missingFood

    var localizedStringResource: LocalizedStringResource {
        "That saved food isn't on your shelf any more."
    }
}

/// A saved food as Siri and Shortcuts see it.
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

/// The phrases Siri knows, and the actions Spotlight, Shortcuts and the Action button list.
struct BiteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanFoodIntent(),
            phrases: [
                "Scan food with \(.applicationName)",
                "Scan with \(.applicationName)",
                "Open the \(.applicationName) scanner",
            ],
            shortTitle: "Scan food",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: LogSavedFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)",
            ],
            shortTitle: "Log a saved food",
            systemImageName: "bookmark"
        )
    }
}
