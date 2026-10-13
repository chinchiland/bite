import Foundation

/// Nutrition for some amount of a food. Optional values are unknown, never silently zero.
struct Nutrients: Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var sugar: Double? = nil
    var fiber: Double? = nil
    var saturatedFat: Double? = nil
    var salt: Double? = nil

    static let zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0)

    func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            kcal: kcal * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            sugar: sugar.map { $0 * factor },
            fiber: fiber.map { $0 * factor },
            saturatedFat: saturatedFat.map { $0 * factor },
            salt: salt.map { $0 * factor }
        )
    }

    static func + (a: Nutrients, b: Nutrients) -> Nutrients {
        Nutrients(
            kcal: a.kcal + b.kcal,
            protein: a.protein + b.protein,
            carbs: a.carbs + b.carbs,
            fat: a.fat + b.fat,
            sugar: sum(a.sugar, b.sugar),
            fiber: sum(a.fiber, b.fiber),
            saturatedFat: sum(a.saturatedFat, b.saturatedFat),
            salt: sum(a.salt, b.salt)
        )
    }

    private static func sum(_ a: Double?, _ b: Double?) -> Double? {
        if a == nil && b == nil { return nil }
        return (a ?? 0) + (b ?? 0)
    }

    /// Where the energy comes from: protein and carbs give 4 kcal per gram, fat 9.
    var energySplit: (protein: Double, carbs: Double, fat: Double) {
        let p = protein * 4
        let c = carbs * 4
        let f = fat * 9
        let total = p + c + f
        guard total > 0 else { return (protein: 0, carbs: 0, fat: 0) }
        return (protein: p / total, carbs: c / total, fat: f / total)
    }
}
