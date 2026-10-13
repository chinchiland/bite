import Foundation

/// One logged food as Apple Health keeps it: a food correlation at the time it was eaten,
/// named after the food, holding a sample for each nutrient Bite knows.
struct HealthMeal: Equatable {
    let id: UUID
    let date: Date
    let name: String
    let nutrients: Nutrients

    /// Health's sync identifier for the correlation; each sample adds its nutrient's name.
    var syncID: String { Self.prefix + id.uuidString }
    static let prefix = "bite."

    enum Nutrient: String, CaseIterable {
        case energy
        case protein
        case carbs
        case fat
        case fiber
        case sugar
        case saturatedFat
        case sodium
    }

    /// Salt is 40% sodium; Health keeps sodium in milligrams.
    static func sodiumMilligrams(fromSaltGrams salt: Double) -> Double {
        salt * 400
    }

    /// What to write, in Health's units: kcal for energy, milligrams for sodium, grams for the
    /// rest. Energy always; anything else only when there is some, so a black coffee is not
    /// six zeros in Health.
    var samples: [(nutrient: Nutrient, value: Double)] {
        var out: [(nutrient: Nutrient, value: Double)] = [(.energy, max(nutrients.kcal, 0))]
        let rest: [(Nutrient, Double?)] = [
            (.protein, nutrients.protein),
            (.carbs, nutrients.carbs),
            (.fat, nutrients.fat),
            (.fiber, nutrients.fiber),
            (.sugar, nutrients.sugar),
            (.saturatedFat, nutrients.saturatedFat),
            (.sodium, nutrients.salt.map(Self.sodiumMilligrams)),
        ]
        for (nutrient, value) in rest {
            if let value, value.isFinite, value > 0 { out.append((nutrient, value)) }
        }
        return out
    }

    /// What Health would show, rounded as it shows it, so an edit that changes nothing there
    /// writes nothing.
    var signature: String {
        let values = samples.map { "\($0.nutrient.rawValue)=\(Int(($0.value * 10).rounded()))" }
        return "\(Int(date.timeIntervalSince1970))|\(name)|" + values.joined(separator: ",")
    }
}

/// A meal Bite already wrote, read back from Health.
struct HealthWritten: Equatable {
    let syncID: String
    let version: Int
    let signature: String
}

/// What to change in Health so it shows exactly the log: new and changed meals are written with
/// a higher version, which makes Health replace its copy, and meals that left the log go.
/// Running it twice changes nothing the second time, so it can run whenever Bite likes.
struct HealthPlan: Equatable {
    struct Save: Equatable {
        let meal: HealthMeal
        let version: Int
    }

    var saves: [Save] = []
    var deletes: [String] = []

    var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }

    static func make(desired: [HealthMeal], written: [HealthWritten]) -> HealthPlan {
        var latest: [String: HealthWritten] = [:]
        for item in written where (latest[item.syncID]?.version ?? -1) < item.version {
            latest[item.syncID] = item
        }
        var plan = HealthPlan()
        var wanted = Set<String>()
        for meal in desired.sorted(by: { $0.date < $1.date }) {
            wanted.insert(meal.syncID)
            if let old = latest[meal.syncID] {
                if old.signature != meal.signature {
                    plan.saves.append(Save(meal: meal, version: old.version + 1))
                }
            } else {
                plan.saves.append(Save(meal: meal, version: 1))
            }
        }
        plan.deletes = latest.keys.filter { !wanted.contains($0) }.sorted()
        return plan
    }
}
