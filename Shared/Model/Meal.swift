import Foundation

enum Meal: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: tr("Breakfast")
        case .lunch: tr("Lunch")
        case .dinner: tr("Dinner")
        case .snack: tr("Snacks")
        }
    }

    /// The name a whole meal gets when you save it to your shelf: "My breakfast".
    var savedTitle: String {
        switch self {
        case .breakfast: tr("My breakfast")
        case .lunch: tr("My lunch")
        case .dinner: tr("My dinner")
        case .snack: tr("My snacks")
        }
    }

    /// "Your usual dinner?", worded for each meal so every language can agree with it.
    var usualQuestion: String {
        switch self {
        case .breakfast: tr("Your usual breakfast?")
        case .lunch: tr("Your usual lunch?")
        case .dinner: tr("Your usual dinner?")
        case .snack: tr("Your usual snack?")
        }
    }

    /// The meal you are most likely logging at this time of day.
    static func likely(at date: Date = .now, calendar: Calendar = .current) -> Meal {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}
