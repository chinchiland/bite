import Foundation

/// The meal you have most: the same foods at the same meal on three days or more of the last
/// two weeks. Today offers it once, quietly, from an hour before the time you usually eat it
/// until two hours after, and only while that meal is still empty.
struct UsualMeal: Equatable {
    let meal: Meal
    /// The last day you had it: today copies that day's amounts.
    let lastDay: Date
    /// When you usually eat it, in minutes after midnight: the middle of those days.
    let minute: Int
    /// On how many of the last two weeks' days you had it.
    let days: Int

    /// One food in the log, as much of it as this needs.
    struct Logged {
        let date: Date
        let meal: Meal
        let foodID: String
    }

    static let minimumDays = 3
    static let lookbackDays = 14
    static let minutesBefore = 60
    static let minutesAfter = 120

    static func find(in logged: [Logged], now: Date, calendar: Calendar = .current) -> UsualMeal? {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }

        struct MealDay: Hashable { let day: Date; let meal: Meal }
        struct Combo: Hashable { let meal: Meal; let foods: Set<String> }

        var eatenToday = Set<Meal>()
        var meals: [MealDay: (foods: Set<String>, first: Date)] = [:]
        for item in logged {
            if item.date >= today && item.date < tomorrow {
                eatenToday.insert(item.meal)
                continue
            }
            guard item.date >= start && item.date < today else { continue }
            let key = MealDay(day: calendar.startOfDay(for: item.date), meal: item.meal)
            var value = meals[key] ?? (foods: [], first: item.date)
            value.foods.insert(item.foodID)
            value.first = min(value.first, item.date)
            meals[key] = value
        }

        var combos: [Combo: [(day: Date, first: Date)]] = [:]
        for (key, value) in meals {
            combos[Combo(meal: key.meal, foods: value.foods), default: []].append((day: key.day, first: value.first))
        }

        let minuteNow = minutes(of: now, calendar: calendar)
        let found = combos.compactMap { combo, days -> UsualMeal? in
            guard days.count >= minimumDays, !eatenToday.contains(combo.meal),
                  let lastDay = days.map(\.day).max() else { return nil }
            let times = days.map { minutes(of: $0.first, calendar: calendar) }.sorted()
            let usual = times[times.count / 2]
            guard minuteNow >= usual - minutesBefore, minuteNow <= usual + minutesAfter else { return nil }
            return UsualMeal(meal: combo.meal, lastDay: lastDay, minute: usual, days: days.count)
        }
        // The one you have most often, then the one you had last.
        return found.max { ($0.days, $0.lastDay) < ($1.days, $1.lastDay) }
    }

    /// The usual time today, for the time column.
    func time(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: minute, to: calendar.startOfDay(for: day)) ?? day
    }

    /// Remembers "Not today" for this meal on this day only.
    func dismissalKey(on day: Date, calendar: Calendar = .current) -> String {
        "\(Int(calendar.startOfDay(for: day).timeIntervalSince1970)) \(meal.rawValue)"
    }

    private static func minutes(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
