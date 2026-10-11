import Foundation
import Observation

/// Lets any screen say "this just went into today", so Today can show it landing.
@Observable
final class LogEvents {
    struct Added: Equatable, Identifiable {
        let id = UUID()
        let food: Food
        let meal: Meal
        let kcal: Double
    }

    private(set) var lastAdded: Added?

    func added(_ food: Food, amount: Double, meal: Meal) {
        lastAdded = Added(food: food, meal: meal, kcal: food.nutrients(for: amount).kcal)
    }

    func dismiss() {
        lastAdded = nil
    }
}
