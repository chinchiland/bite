import Foundation
import Observation

/// Lets any screen say "this just landed in today" or "this just went", so Today can show it
/// in a toast and offer to undo it. Nothing in Bite asks "are you sure?": it does, then lets
/// you take it back.
@Observable
final class LogEvents {
    /// What a log entry was, so a delete can be undone after the entry itself is gone.
    struct Snapshot: Equatable {
        let food: Food
        let amount: Double
        let meal: Meal
        let date: Date
        let place: MealPlace?

        init(_ entry: FoodEntry) {
            food = entry.food
            amount = entry.amount
            meal = entry.meal
            date = entry.date
            place = entry.place
        }
    }

    enum Change: Equatable {
        case added([FoodEntry])
        case deleted([Snapshot])
    }

    struct Event: Equatable, Identifiable {
        let id = UUID()
        /// The food the toast pictures: the first of the change.
        let food: Food
        let meal: Meal
        let kcal: Double
        let count: Int
        let change: Change
    }

    private(set) var last: Event?

    func added(_ entry: FoodEntry) {
        added([entry])
    }

    func added(_ entries: [FoodEntry]) {
        guard let first = entries.first else { return }
        last = Event(
            food: first.food,
            meal: first.meal,
            kcal: entries.reduce(0) { $0 + $1.totals.kcal },
            count: entries.count,
            change: .added(entries)
        )
    }

    func deleted(_ snapshots: [Snapshot]) {
        guard let first = snapshots.first else { return }
        last = Event(
            food: first.food,
            meal: first.meal,
            kcal: snapshots.reduce(0) { $0 + $1.food.nutrients(for: $1.amount).kcal },
            count: snapshots.count,
            change: .deleted(snapshots)
        )
    }

    func dismiss() {
        last = nil
    }
}
