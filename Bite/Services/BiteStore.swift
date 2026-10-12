import Foundation
import SwiftData

/// The one food log, shared by the app and its Siri and Shortcuts actions.
enum BiteStore {
    /// `-demo` (Debug builds only) runs on a seeded log in memory, for screenshots.
    static let isDemo: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }()

    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: FoodEntry.self, SavedFood.self, WaterDay.self, CommunityDish.self, DishEstimate.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: isDemo)
            )
        } catch {
            fatalError("Could not open the food log: \(error)")
        }
    }()
}
