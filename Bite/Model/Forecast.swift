import Foundation

/// Where your weight is heading if you keep eating like this: your recent days' average against
/// what your body burns in a day, at about 7,700 kcal to a kilo. An estimate, and said so.
struct WeightForecast: Equatable {
    /// Kilocalories in a kilo of body weight, the usual rule of thumb.
    static let kcalPerKg = 7700.0
    /// Days that count: enough food logged to be a whole day, not a forgotten one.
    static let minimumDayKcal = 800.0
    static let minimumDays = 3

    let startKg: Double
    /// What you eat in a day minus what you burn: below zero is a deficit.
    let dailyBalance: Double
    /// How many logged days the average comes from.
    let days: Int

    /// Kilos a week, below zero when losing.
    var perWeek: Double { dailyBalance * 7 / Self.kcalPerKg }

    func weight(afterDays days: Double) -> Double {
        startKg + dailyBalance * days / Self.kcalPerKg
    }

    enum Direction: Equatable {
        case losing
        case holding
        case gaining
    }

    /// Within 50 kcal a day of what you burn is holding steady.
    var direction: Direction {
        if dailyBalance < -50 { return .losing }
        if dailyBalance > 50 { return .gaining }
        return .holding
    }

    /// Nil until a few whole days are logged: a forecast from one day would only be noise.
    static func make(currentKg: Double, maintenance: Double, dayKcals: [Double]) -> WeightForecast? {
        let whole = dayKcals.filter { $0 >= minimumDayKcal }
        guard whole.count >= minimumDays, currentKg > 0, maintenance > 0 else { return nil }
        let average = whole.reduce(0, +) / Double(whole.count)
        return WeightForecast(startKg: currentKg, dailyBalance: average - maintenance, days: whole.count)
    }
}

extension GoalCalculator {
    /// What a body burns in a day: Mifflin-St Jeor resting energy times activity, before any
    /// goal is taken off or added.
    static func maintenance(sex: Sex, age: Int, heightCm: Double, weightKg: Double, activity: Activity) -> Double {
        let weightKg = min(max(weightKg, 25), 400)
        let heightCm = min(max(heightCm, 100), 250)
        let age = min(max(age, 10), 110)
        let resting = 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
        return resting * activity.factor
    }
}
