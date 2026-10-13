import Foundation

/// How the daily calories split between protein, carbs and fat.
enum MacroSplit: String, CaseIterable, Identifiable {
    case balanced
    case highProtein
    case lowCarb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: tr("Balanced")
        case .highProtein: tr("High protein")
        case .lowCarb: tr("Low carb")
        }
    }

    /// Share of calories from each macro.
    var shares: (protein: Double, carbs: Double, fat: Double) {
        switch self {
        case .balanced: (protein: 0.25, carbs: 0.45, fat: 0.30)
        case .highProtein: (protein: 0.35, carbs: 0.35, fat: 0.30)
        case .lowCarb: (protein: 0.30, carbs: 0.20, fat: 0.50)
        }
    }
}

/// Daily grams for each macro.
struct MacroTargets: Equatable {
    var protein: Double
    var carbs: Double
    var fat: Double

    init(kcal: Double, split: MacroSplit) {
        let shares = split.shares
        protein = (kcal * shares.protein / 4).rounded()
        carbs = (kcal * shares.carbs / 4).rounded()
        fat = (kcal * shares.fat / 9).rounded()
    }
}

enum Sex: String, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
    var title: String { self == .female ? tr("Female") : tr("Male") }
}

enum Activity: String, CaseIterable, Identifiable {
    case sedentary
    case light
    case moderate
    case active

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: tr("Mostly sitting")
        case .light: tr("Lightly active")
        case .moderate: tr("Active")
        case .active: tr("Very active")
        }
    }

    var detail: String {
        switch self {
        case .sedentary: tr("Desk job, little exercise")
        case .light: tr("Walks, or training 1 to 3 days a week")
        case .moderate: tr("Training 3 to 5 days a week")
        case .active: tr("Hard training most days")
        }
    }

    var factor: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        }
    }
}

enum WeightGoal: String, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: tr("Lose")
        case .maintain: tr("Maintain")
        case .gain: tr("Gain")
        }
    }

    /// About half a kilo a week down, or a slow lean gain.
    var adjustment: Double {
        switch self {
        case .lose: -500
        case .maintain: 0
        case .gain: 300
        }
    }
}

/// Fiber to reach in a day: 14 g for each 1,000 kcal of the goal, the US guidelines' ratio,
/// which follows sex, age and activity through the goal. Never under 25 g (EFSA and the WHO's
/// floor for adults) or over 38 g. It is a floor, not a limit: more is never "over".
enum FiberTarget {
    static func grams(forGoal kcal: Double) -> Double {
        min(max(kcal / 1000 * 14, 25), 38).rounded()
    }
}

/// The day's fiber, and how much of the day it can see. Fiber is optional on European labels,
/// so a food with carbs and no fiber on record is a gap; meat, eggs or oil with none on record
/// have none to speak of and leave no gap.
struct FiberDay: Equatable {
    struct Item: Equatable {
        var fiber: Double?
        var carbs: Double
    }

    let grams: Double
    /// Foods with fiber on record.
    let known: Int
    /// Foods that matter for fiber: those with fiber on record, and those with carbs.
    let counted: Int
    /// The share of the day's carbs that comes from foods with fiber on record.
    let knownCarbShare: Double

    static func make(_ items: [Item]) -> FiberDay {
        var grams = 0.0
        var known = 0
        var counted = 0
        var carbs = 0.0
        var knownCarbs = 0.0
        for item in items {
            let itemCarbs = max(item.carbs, 0)
            carbs += itemCarbs
            if let fiber = item.fiber {
                grams += max(fiber, 0)
                known += 1
                counted += 1
                knownCarbs += itemCarbs
            } else if itemCarbs >= 1 {
                counted += 1
            }
        }
        let share = carbs > 0 ? knownCarbs / carbs : (known > 0 ? 1 : 0)
        return FiberDay(grams: grams, known: known, counted: counted, knownCarbShare: share)
    }

    /// Worth a line once at least half the day's carbs come from foods with fiber on record;
    /// below that the total would read as "you eat no fiber".
    var isShown: Bool { known > 0 && knownCarbShare >= 0.5 }
    /// Foods without fiber carry more than 15% of the day's carbs: say how many were counted.
    var isPartial: Bool { knownCarbShare < 0.85 }
}

enum GoalCalculator {
    /// Mifflin-St Jeor resting energy, times activity, plus the goal adjustment.
    /// Rounded to 10 kcal and never below a safe floor.
    static func dailyCalories(
        sex: Sex,
        age: Int,
        heightCm: Double,
        weightKg: Double,
        activity: Activity,
        goal: WeightGoal
    ) -> Int {
        let weightKg = min(max(weightKg, 25), 400)
        let heightCm = min(max(heightCm, 100), 250)
        let age = min(max(age, 10), 110)
        let resting = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
        let target = resting * activity.factor + goal.adjustment
        let floor: Double = sex == .male ? 1500 : 1200
        return Int((max(target, floor) / 10).rounded()) * 10
    }
}
