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

extension WeightForecast {
    /// Your weighings smoothed, oldest first: each day's number pulled a quarter of the way from
    /// the trend so far, so one salty dinner never moves the line much.
    static func trend(_ kilograms: [Double], smoothing: Double = 0.25) -> [Double] {
        var result: [Double] = []
        for value in kilograms {
            result.append(result.last.map { $0 + smoothing * (value - $0) } ?? value)
        }
        return result
    }
}

/// What your body really burns, learned from your weighings and your meals: what you ate on
/// the days you logged, minus what the weighings' straight line says changed, at 7,700 kcal a
/// kilo. It needs two weeks of both: weighings spread over at least 14 days, and most of
/// those days logged whole.
struct LearnedMaintenance: Equatable {
    let kcal: Double
    /// The days of weighings and meals it comes from.
    let days: Int

    struct Weighing {
        let date: Date
        let kilograms: Double
    }

    static let lookbackDays = 28
    static let minimumDays = 14
    static let minimumWeighings = 5

    static func learn(weighings: [Weighing], dayKcals: [Date: Double], now: Date, calendar: Calendar = .current) -> LearnedMaintenance? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return nil }
        // Whole days logged in the last four weeks, today aside: it is not over yet.
        let logged = dayKcals.filter { $0.key >= start && $0.key < today && $0.value >= WeightForecast.minimumDayKcal }
        guard let firstLogged = logged.keys.min() else { return nil }
        // The weighings from the first logged day on: both have to cover the same days.
        let recent = weighings
            .filter { $0.date >= firstLogged && $0.date <= now && $0.kilograms > 0 && $0.kilograms.isFinite }
            .sorted { $0.date < $1.date }
        guard recent.count >= minimumWeighings, let first = recent.first, let last = recent.last else { return nil }
        let span = last.date.timeIntervalSince(first.date) / 86_400
        let days = Int(span.rounded())
        guard days >= minimumDays, logged.count >= max(10, days * 2 / 3) else { return nil }

        // The straight line through the weighings, in kilos a day: one salty dinner barely moves it.
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map(\.kilograms)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx

        let intake = logged.values.reduce(0, +) / Double(logged.count)
        let kcal = intake - slope * WeightForecast.kcalPerKg
        guard (1000...5000).contains(kcal) else { return nil }
        return LearnedMaintenance(kcal: kcal, days: days)
    }

    /// A daily goal from what you really burn: your weight goal's step taken off or added,
    /// rounded to 10 kcal and never under the safe floor.
    func goal(for weightGoal: WeightGoal, sex: Sex) -> Int {
        let floor: Double = sex == .male ? 1500 : 1200
        return Int((max(kcal + weightGoal.adjustment, floor) / 10).rounded()) * 10
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
