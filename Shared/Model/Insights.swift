import Foundation

/// One day of logs, boiled down to what the scores and ranks need.
struct DaySummary: Hashable {
    let day: Date
    let kcal: Double
    let protein: Double
    let entries: Int
    /// Average food quality from Nutri-Score, 0 to 1, weighted by calories. Nil when nothing
    /// that day had a grade.
    let quality: Double?
}

/// How a day went against the goal, in words people can live with.
enum DayVerdict: Equatable {
    case empty
    case light
    case onTarget
    case over(kcal: Double)

    init(kcal: Double, entries: Int, goal: Double) {
        if entries == 0 || goal <= 0 {
            self = .empty
        } else if kcal > goal * 1.05 {
            self = .over(kcal: kcal - goal)
        } else if kcal >= goal * 0.9 {
            self = .onTarget
        } else {
            self = .light
        }
    }

    /// Friendly and never shaming: going over is a fact, not a failure. The screens add the
    /// symbol; emoji stay for food.
    var label: String? {
        switch self {
        case .empty: nil
        case .light: tr("Light day")
        case .onTarget: tr("On target")
        case .over(let kcal): tr("%@ kcal over", kcal.kcalText)
        }
    }

    var isOnTarget: Bool { self == .onTarget }
}

enum Insights {
    /// Nutri-Score as a share of the best grade.
    static func qualityPoints(grade: String?) -> Double? {
        switch grade?.lowercased() {
        case "a": 1.0
        case "b": 0.8
        case "c": 0.55
        case "d": 0.3
        case "e": 0.1
        default: nil
        }
    }

    /// A day out of 100: 60 for landing near the calorie goal, 25 for protein, 15 for the
    /// quality of what you ate. The same rules every day, so days can be ranked fairly.
    static func score(_ day: DaySummary, goal: Double, proteinTarget: Double) -> Int {
        guard day.entries > 0, goal > 0 else { return 0 }
        let calories = 60 * max(0, 1 - abs(day.kcal - goal) / (goal * 0.4))
        let protein = proteinTarget > 0 ? 25 * min(1, day.protein / proteinTarget) : 0
        let quality = 15 * (day.quality ?? 0.6)
        return Int((calories + protein + quality).rounded())
    }

    /// Days logged in a row, up to today. Today joins as soon as something is logged, and a
    /// day over or light keeps the streak going: it counts showing up, and the week's dots say
    /// how the days went. A day with nothing logged ends it.
    static func streak(_ days: [DaySummary], goal: Double, today: Date, calendar: Calendar = .current) -> Int {
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        var cursor = calendar.startOfDay(for: today)
        var count = 0
        if let todays = byDay[cursor], todays.entries > 0 {
            count = 1
        }
        while let previous = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = previous
            guard let day = byDay[cursor], day.entries > 0 else { break }
            count += 1
        }
        return count
    }

    /// The best logged days, highest score first, newest first on a tie.
    static func bestDays(_ days: [DaySummary], goal: Double, proteinTarget: Double, limit: Int = 3) -> [(day: DaySummary, score: Int)] {
        days.filter { $0.entries > 0 }
            .map { (day: $0, score: score($0, goal: goal, proteinTarget: proteinTarget)) }
            .sorted { ($0.score, $0.day.day) > ($1.score, $1.day.day) }
            .prefix(limit)
            .map { $0 }
    }

    /// Averages over the days that have logs, and how they moved against the period before.
    struct Period: Equatable {
        var loggedDays: Int
        var averageKcal: Double
        var averageProtein: Double
        var daysOnTarget: Int
    }

    static func period(_ days: [DaySummary], goal: Double) -> Period {
        let logged = days.filter { $0.entries > 0 }
        guard !logged.isEmpty else { return Period(loggedDays: 0, averageKcal: 0, averageProtein: 0, daysOnTarget: 0) }
        let count = Double(logged.count)
        return Period(
            loggedDays: logged.count,
            averageKcal: logged.reduce(0) { $0 + $1.kcal } / count,
            averageProtein: logged.reduce(0) { $0 + $1.protein } / count,
            daysOnTarget: logged.filter { DayVerdict(kcal: $0.kcal, entries: $0.entries, goal: goal).isOnTarget }.count
        )
    }

    /// Change from `before` to `now` as a fraction, or nil when there is nothing to compare.
    static func change(from before: Double, to now: Double) -> Double? {
        guard before > 0, now > 0 else { return nil }
        return (now - before) / before
    }

    /// A food you keep coming back to.
    struct FoodCount: Equatable {
        var foodID: String
        var name: String
        var times: Int
        var kcal: Double
    }

    /// Most eaten foods: most logs first, then most calories.
    static func topFoods(_ logs: [(foodID: String, name: String, kcal: Double)], limit: Int = 5) -> [FoodCount] {
        var counts: [String: FoodCount] = [:]
        var order: [String] = []
        for log in logs {
            if counts[log.foodID] == nil {
                counts[log.foodID] = FoodCount(foodID: log.foodID, name: log.name, times: 0, kcal: 0)
                order.append(log.foodID)
            }
            counts[log.foodID]?.times += 1
            counts[log.foodID]?.kcal += log.kcal
        }
        return order.compactMap { counts[$0] }
            .sorted { ($0.times, $0.kcal) > ($1.times, $1.kcal) }
            .prefix(limit)
            .map { $0 }
    }
}
