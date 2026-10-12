import Foundation

/// What people's calorie estimates for one dish add up to. Each estimate counts once, plus once
/// more for every person who agreed with it, so the estimates people trust weigh the most.
struct Consensus: Equatable {
    struct Estimate: Equatable {
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var agrees: Int
    }

    enum Tier: Equatable {
        case veryAccurate
        case accurate
        case rough
        case needsMore

        var title: String {
            switch self {
            case .veryAccurate: tr("Very accurate")
            case .accurate: tr("Accurate")
            case .rough: tr("Roughly right")
            case .needsMore: tr("Needs more estimates")
            }
        }
    }

    /// The dish's calories and macros: the weighted average of the estimates.
    let nutrients: Nutrients
    /// 0 to 100: how close the estimates are to each other, times how many people stand behind
    /// them. Three close estimates and a few agreements reach the 90s; one estimate alone stays low.
    let accuracy: Int
    /// How far the estimates sit from their average, as a share of it: 0.02 reads "within 2%".
    let spread: Double
    let estimates: Int
    let agrees: Int

    init(_ list: [Estimate]) {
        estimates = list.count
        agrees = list.reduce(0) { $0 + max($1.agrees, 0) }
        let weights = list.map { Double(1 + max($0.agrees, 0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            nutrients = .zero
            accuracy = 0
            spread = 0
            return
        }
        func mean(_ value: (Estimate) -> Double) -> Double {
            zip(list, weights).reduce(0) { $0 + value($1.0) * $1.1 } / total
        }
        let kcal = mean(\.kcal)
        nutrients = Nutrients(kcal: kcal, protein: mean(\.protein), carbs: mean(\.carbs), fat: mean(\.fat))
        let deviation = zip(list, weights).reduce(0) { $0 + abs($1.0.kcal - kcal) * $1.1 } / total
        spread = kcal > 0 ? deviation / kcal : 0
        let agreement = max(0, 1 - spread)
        let coverage = 1 - exp(-Double(estimates + agrees) / 6)
        accuracy = Int((agreement * coverage * 100).rounded())
    }

    var tier: Tier {
        switch accuracy {
        case 90...: .veryAccurate
        case 70...: .accurate
        case 50...: .rough
        default: .needsMore
        }
    }

    /// The spread as a whole percentage, never under 1: "within 2%".
    var spreadPercent: Int { max(1, Int((spread * 100).rounded())) }
}
