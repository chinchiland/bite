import Foundation

/// Your goal, checked once a week: how your week went in your own numbers, and one capped step
/// toward what your body really burns. It stays silent until there is enough to say: four whole
/// days logged in the last seven, a weighing this week, and a learned goal at least 50 kcal from
/// yours. It follows what you ate and how your weight moved, never whether you hit past goals.
struct CheckIn: Equatable {
    /// How the smoothed weight moved over the week, in kilos; nil without weighings a week apart.
    let trendChange: Double?
    /// The average of the week's whole days, and how many there were.
    let averageEaten: Double
    let wholeDays: Int
    /// What you burn now, and how that moved since a week ago; nil when it was unknown then.
    let burned: Double
    let burnedChange: Double?
    let currentGoal: Int
    let offeredGoal: Int
    /// From your goal to the learned one, before the step is capped.
    let gap: Int

    var delta: Int { offeredGoal - currentGoal }

    static let minimumStep = 50
    static let maximumStep = 150
    static let minimumWholeDays = 4

    /// Half the gap, rounded to 10 kcal, at least 50 and at most 150; nothing under 50.
    static func step(gap: Int) -> Int {
        let size = Int(gap.magnitude)
        guard size >= minimumStep else { return 0 }
        let half = Int((Double(size) / 2 / 10).rounded()) * 10
        let capped = min(max(half, minimumStep), maximumStep)
        return gap < 0 ? -capped : capped
    }

    static func make(
        now: Date,
        dayKcals: [Date: Double],
        weighings: [LearnedMaintenance.Weighing],
        currentGoal: Int,
        weightGoal: WeightGoal,
        sex: Sex,
        calendar: Calendar = .current
    ) -> CheckIn? {
        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -7, to: today) else { return nil }
        let week = dayKcals.filter { $0.key >= weekStart && $0.key < today && $0.value >= WeightForecast.minimumDayKcal }
        guard week.count >= minimumWholeDays,
              weighings.contains(where: { $0.date >= weekStart && $0.date <= now }),
              let learned = LearnedMaintenance.learn(weighings: weighings, dayKcals: dayKcals, now: now, calendar: calendar) else { return nil }

        let gap = learned.goal(for: weightGoal, sex: sex) - currentGoal
        let step = Self.step(gap: gap)
        guard step != 0 else { return nil }
        // Never under the safe floor, never more than a quarter under what you burn.
        let floor = sex == .male ? 1500 : 1200
        let lowest = max(floor, Int((learned.kcal * 0.75 / 10).rounded(.up)) * 10)
        let offered = max(currentGoal + step, lowest)
        guard abs(offered - currentGoal) >= minimumStep else { return nil }

        let earlier = calendar.date(byAdding: .day, value: -7, to: now).flatMap {
            LearnedMaintenance.learn(weighings: weighings, dayKcals: dayKcals, now: $0, calendar: calendar)
        }
        return CheckIn(
            trendChange: trendChange(weighings, now: now, calendar: calendar),
            averageEaten: week.values.reduce(0, +) / Double(week.count),
            wholeDays: week.count,
            burned: learned.kcal,
            burnedChange: earlier.map { learned.kcal - $0.kcal },
            currentGoal: currentGoal,
            offeredGoal: offered,
            gap: gap
        )
    }

    /// The smoothed weight now against the one a week ago, so one salty dinner barely shows.
    static func trendChange(_ weighings: [LearnedMaintenance.Weighing], now: Date, calendar: Calendar = .current) -> Double? {
        let sorted = weighings.filter { $0.date <= now && $0.kilograms > 0 }.sorted { $0.date < $1.date }
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let before = sorted.lastIndex(where: { $0.date <= weekAgo }),
              sorted.last.map({ $0.date > weekAgo }) == true else { return nil }
        let trend = WeightForecast.trend(sorted.map(\.kilograms))
        guard let end = trend.last else { return nil }
        return end - trend[before]
    }
}

/// When the check-in shows, and what you answered. The check-in day is the weekday the learned
/// goal first had something to offer; the card shows from that morning until you answer or
/// three days pass. After "Keep" twice in a row it waits a week more, after three times until
/// the gap has grown by another 150 kcal.
struct CheckInHistory: Codable, Equatable {
    var weekday: Int?
    /// The check-in day you last answered, either way.
    var answeredDay: Date?
    var keepsInARow = 0
    var gapAtLastKeep: Int?
    /// The goal before "Use it", while Undo is offered that week.
    var undoGoal: Int?

    static let daysShown = 3

    /// The latest check-in day on or before now.
    func checkInDay(now: Date, calendar: Calendar = .current) -> Date? {
        guard let weekday else { return nil }
        let today = calendar.startOfDay(for: now)
        let back = (calendar.component(.weekday, from: today) - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: today)
    }

    /// Whether a check-in with this gap shows now.
    func isDue(now: Date, gap: Int, calendar: Calendar = .current) -> Bool {
        guard let day = checkInDay(now: now, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: Self.daysShown, to: day),
              now < end else { return false }
        if let answeredDay, answeredDay >= day { return false }
        switch keepsInARow {
        case ..<2:
            return true
        case 2:
            guard let answeredDay, let next = calendar.date(byAdding: .day, value: 14, to: answeredDay) else { return true }
            return day >= next
        default:
            return Int(gap.magnitude) >= (gapAtLastKeep ?? 0) + 150
        }
    }

    /// The check-in found something to say for the first time: today becomes the check-in day.
    mutating func start(now: Date, calendar: Calendar = .current) {
        guard weekday == nil else { return }
        weekday = calendar.component(.weekday, from: now)
    }

    mutating func used(previousGoal: Int, now: Date, calendar: Calendar = .current) {
        answeredDay = checkInDay(now: now, calendar: calendar)
        keepsInARow = 0
        gapAtLastKeep = nil
        undoGoal = previousGoal
    }

    mutating func kept(gap: Int, now: Date, calendar: Calendar = .current) {
        answeredDay = checkInDay(now: now, calendar: calendar)
        keepsInARow += 1
        gapAtLastKeep = Int(gap.magnitude)
        undoGoal = nil
    }

    /// Undo is offered for the rest of the week the goal was set in.
    func canUndo(now: Date, calendar: Calendar = .current) -> Bool {
        guard undoGoal != nil, let answeredDay, let day = checkInDay(now: now, calendar: calendar) else { return false }
        return answeredDay >= day
    }
}
