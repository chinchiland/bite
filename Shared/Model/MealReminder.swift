import Foundation

/// The mealtime nudge: offered once, after the second log, at the time of the first meal Bite
/// saw. It comes only on days that meal is not in yet, one a day at most, and it is planned
/// three days ahead at most, so it stops by itself when Bite is not opened.
struct MealReminder: Codable, Equatable {
    var mealRaw: String
    /// Minutes after midnight.
    var minute: Int

    var meal: Meal { Meal(rawValue: mealRaw) ?? .breakfast }

    init(meal: Meal, minute: Int) {
        self.mealRaw = meal.rawValue
        self.minute = min(max(minute, 0), 24 * 60 - 1)
    }

    /// From the first food Bite saw: its meal, or the meal its hour belongs to when it was a
    /// snack, at its time.
    init(firstLog date: Date, meal: Meal, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let chosen = meal == .snack ? Meal.likely(at: date, calendar: calendar) : meal
        self.init(meal: chosen == .snack ? .breakfast : chosen, minute: (parts.hour ?? 8) * 60 + (parts.minute ?? 0))
    }

    /// Offered once two foods are in, never again after an answer.
    static func shouldOffer(entries: Int, answered: Bool) -> Bool {
        entries >= 2 && !answered
    }

    /// When to remind, from now: today if its time is still ahead and the meal is not in yet,
    /// then the next days, three at most.
    func fireDates(now: Date, loggedToday: Bool, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<3).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let time = calendar.date(byAdding: .minute, value: minute, to: day) else { return nil }
            if offset == 0 && (loggedToday || time <= now) { return nil }
            return time
        }
    }

    /// The offer's question, by meal, so every language words it well.
    func question(timeText: String) -> String {
        switch meal {
        case .breakfast: String(format: tr("A nudge tomorrow at %@, only if breakfast isn't in?"), timeText)
        case .lunch: String(format: tr("A nudge tomorrow at %@, only if lunch isn't in?"), timeText)
        case .dinner, .snack: String(format: tr("A nudge tomorrow at %@, only if dinner isn't in?"), timeText)
        }
    }

    /// The notification's title.
    var title: String {
        switch meal {
        case .breakfast: tr("Breakfast?")
        case .lunch: tr("Lunch?")
        case .dinner, .snack: tr("Dinner?")
        }
    }
}
