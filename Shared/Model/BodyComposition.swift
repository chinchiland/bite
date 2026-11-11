import Foundation

/// A body as two numbers: what it weighs and how much of that is fat.
struct BodyNumbers: Equatable, Codable {
    var kg: Double
    /// Body fat, in percent.
    var fat: Double

    var fatKg: Double { kg * fat / 100 }
    var leanKg: Double { kg - fatKg }
}

/// How much muscle a body carries for its height, by its fat-free mass index adjusted for height
/// (Kouri, 1995): about 25 is as much as most men build without drugs, about 21 for women.
enum MuscleLevel: Int, CaseIterable {
    case little, average, fit, muscular, nearLimit, beyond

    var title: String {
        switch self {
        case .little: tr("Little muscle")
        case .average: tr("Average muscle")
        case .fit: tr("Fit")
        case .muscular: tr("Muscular")
        case .nearLimit: tr("Near the limit")
        case .beyond: tr("Beyond natural")
        }
    }

    /// For a label under a small body.
    var short: String {
        switch self {
        case .little: tr("Little")
        case .average: tr("Average")
        case .fit: tr("Fit")
        case .muscular: tr("Muscular")
        case .nearLimit: tr("Near limit")
        case .beyond: tr("Beyond")
        }
    }
}

/// From one body to another: how much fat goes or comes, how much lean mass, and how long that
/// takes naturally.
struct BodyPlan: Equatable {
    let fatChange: Double
    let leanChange: Double
    /// Fat lost a week: about 0.7% of the weight, inside the 0.5 to 1% that keeps muscle (Helms, 2014).
    let fatPerWeek: Double
    /// Lean mass a month at the natural rate for the muscle you have now.
    let leanPerMonth: Double
    let months: Double
}

/// A sex and a height: what every body of that frame can be.
struct BodyFrame: Equatable {
    var sex: Sex
    var heightCm: Double

    private var meters: Double { min(max(heightCm, 120), 230) / 100 }
    private var squared: Double { meters * meters }
    /// Kouri's adjustment, so a short body's index compares with a tall one's.
    private var adjustment: Double { 6.1 * (1.8 - meters) }

    func index(leanKg: Double) -> Double { leanKg / squared + adjustment }
    func leanKg(index: Double) -> Double { (index - adjustment) * squared }

    func level(_ body: BodyNumbers) -> MuscleLevel { level(index: index(leanKg: body.leanKg)) }

    func level(index: Double) -> MuscleLevel {
        let edges: [Double] = sex == .male ? [18, 20, 22, 24, 25.5] : [14.5, 16, 17.5, 19, 21]
        return MuscleLevel(rawValue: edges.firstIndex { index < $0 } ?? 5) ?? .beyond
    }

    /// The most muscle a body builds without drugs, and the bounds of a human body at all.
    var naturalLimit: Double { sex == .male ? 25.5 : 21 }
    private var leastMuscle: Double { sex == .male ? 15 : 12 }
    private var mostMuscle: Double { sex == .male ? 28 : 24 }
    private var leastFat: Double { sex == .male ? 4 : 12 }

    /// The body fats a weight allows: between far more muscle than anyone builds and almost none.
    func fatRange(kg: Double) -> ClosedRange<Int> {
        let low = max(Int(leastFat), Int((100 * (1 - leanKg(index: mostMuscle) / kg)).rounded(.up)))
        let high = min(60, Int((100 * (1 - leanKg(index: leastMuscle) / kg)).rounded(.down)))
        return low...max(low, high)
    }

    /// The leanest a body of this weight can be without more muscle than nature allows.
    func naturalLeast(kg: Double) -> Double { 100 * (1 - leanKg(index: naturalLimit) / kg) }

    /// Weights for this height: a body now from a BMI of 16, a goal from 18.5, both up to 50.
    func weightRange(goal: Bool) -> ClosedRange<Double> {
        let low = max(35, (goal ? 18.5 : 16) * squared), high = min(180, 50 * squared)
        return ((low * 2).rounded(.up) / 2)...max((low * 2).rounded(.up) / 2, (high * 2).rounded(.down) / 2)
    }

    /// A body kept inside what a human can be: its weight for the height, then its fat for the weight.
    func settle(_ body: BodyNumbers, goal: Bool) -> BodyNumbers {
        let weights = weightRange(goal: goal)
        let kg = min(max((body.kg * 2).rounded() / 2, weights.lowerBound), weights.upperBound)
        let fats = fatRange(kg: kg)
        return BodyNumbers(kg: kg, fat: Double(min(max(Int(body.fat.rounded()), fats.lowerBound), fats.upperBound)))
    }

    /// Five round body fats, five points apart, from the leanest natural body up, holding this one.
    func choices(around body: BodyNumbers) -> [Int] {
        let fats = fatRange(kg: body.kg), fat = Int(body.fat.rounded())
        let floor5 = { (v: Int) in Int((Double(v) / 5).rounded(.down)) * 5 }
        let ceil5 = { (v: Int) in Int((Double(v) / 5).rounded(.up)) * 5 }
        var start = ceil5(max(fats.lowerBound, Int(naturalLeast(kg: body.kg).rounded(.up))))
        if fat < start { start = max(floor5(fat), ceil5(fats.lowerBound)) }
        if fat > start + 20 { start = ceil5(fat) - 20 }
        start = max(min(start, floor5(fats.upperBound) - 20), ceil5(fats.lowerBound))
        return (0..<5).map { start + 5 * $0 }.filter { fats.contains($0) }
    }

    /// MakeHuman's two sliders for a body, 0 to 1 with 0.5 the average body: muscle from the index,
    /// weight from the fat for the height. `bare` is the weight slider of the same body with
    /// almost no fat, which the fat map measures from.
    func sliders(_ body: BodyNumbers) -> (muscle: Double, weight: Double, bare: Double) {
        let female = sex == .female, fatIndex = body.fatKg / squared
        let muscle = 0.5 + (index(leanKg: body.leanKg) - (female ? 15.5 : 19)) / (female ? 10 : 12)
        let weight = 0.5 + (fatIndex - (female ? 5.7 : 4.5)) / 15
        return (min(max(muscle, 0), 1), min(max(weight, 0), 1), female ? 0.32 : 0.28)
    }

    /// From now to a goal: fat at about 0.7% of the weight a week, lean mass at the natural rate
    /// for the muscle you have (about 1 kg a month new to lifting, less the more you have, a woman
    /// about half), both at once.
    func plan(from now: BodyNumbers, to goal: BodyNumbers) -> BodyPlan {
        let fatChange = goal.fatKg - now.fatKg, leanChange = goal.leanKg - now.leanKg
        let perWeek = 0.007 * (now.kg + goal.kg) / 2
        let rates: [Double] = [1.0, 0.9, 0.6, 0.35, 0.15, 0.1]
        let perMonth = rates[level(now).rawValue] * (sex == .female ? 0.5 : 1)
        let fatMonths = fatChange < 0 ? -fatChange / perWeek / 4.35 : fatChange / 0.3 / 4.35
        let leanMonths = leanChange > 0 ? leanChange / perMonth : 0
        return BodyPlan(fatChange: fatChange, leanChange: leanChange, fatPerWeek: perWeek, leanPerMonth: perMonth, months: max(fatMonths, leanMonths))
    }

    /// Body fat from a tape measure, the US Navy's way (Hodgdon and Beckett, 1984), in cm.
    func tape(waist: Double, neck: Double, hips: Double) -> Double? {
        let h = min(max(heightCm, 120), 230)
        let percent: Double
        if sex == .male {
            guard waist > neck else { return nil }
            percent = 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(h)) - 450
        } else {
            guard waist + hips > neck else { return nil }
            percent = 495 / (1.29579 - 0.35004 * log10(waist + hips - neck) + 0.221 * log10(h)) - 450
        }
        return percent > 3 && percent < 60 ? percent : nil
    }
}
