import Foundation

/// What a widget shows for today, worked out from the day's log and your settings: what is
/// left (or over, or eaten without a target), the macros against their targets, the ring's
/// parts, and water. Foundation only, so the same numbers as Today are tested on Linux.
struct WidgetSnapshot: Equatable {
    var eaten: Nutrients
    /// The goal, plus today's burned calories when you add them to it.
    var budget: Double
    var targets: MacroTargets
    var water: Int
    var waterGoal: Int
    var noTarget: Bool

    var isOver: Bool { !noTarget && eaten.kcal > budget }

    /// The number a widget leads with: what is left, what went over, or what was eaten.
    var headline: Double {
        if noTarget { return eaten.kcal }
        return abs(budget - eaten.kcal)
    }

    enum Headline: Equatable {
        case left
        case over
        case eaten
    }

    var headlineKind: Headline {
        if noTarget { return .eaten }
        return isOver ? .over : .left
    }

    /// The ring: each macro's share of the whole ring, filled toward the goal, and how far past
    /// it the day went (0 to 1). Without a target the ring fills toward the goal as a guide
    /// and never runs red.
    var ring: (protein: Double, carbs: Double, fat: Double, overflow: Double) {
        guard budget > 0, eaten.kcal > 0 else { return (0, 0, 0, 0) }
        let progress = eaten.kcal / budget
        let filled = min(progress, 1)
        let split = eaten.energySplit
        let overflow = noTarget ? 0 : min(max(progress - 1, 0), 1)
        return (split.protein * filled, split.carbs * filled, split.fat * filled, overflow)
    }

    /// How far today has come toward the goal, 0 to 1, for a gauge.
    var progress: Double {
        guard budget > 0 else { return 0 }
        return min(max(eaten.kcal / budget, 0), 1)
    }

    static func make(
        day: Nutrients,
        goal: Double,
        burned: Double = 0,
        split: MacroSplit = .balanced,
        water: Int = 0,
        waterGoal: Int = 8,
        noTarget: Bool = false
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            eaten: day,
            budget: goal + max(burned, 0),
            targets: MacroTargets(kcal: goal, split: split),
            water: max(water, 0),
            waterGoal: max(waterGoal, 1),
            noTarget: noTarget
        )
    }

    /// The day Bite Demo shows in its widgets: the demo's lunch at El Beirout.
    static let sample = WidgetSnapshot.make(
        day: Nutrients(kcal: 1033, protein: 62, carbs: 79, fat: 55),
        goal: 2000,
        water: 3
    )
}
