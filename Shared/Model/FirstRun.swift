import Foundation

/// Bite's first minute: a welcome, then the first bite logged, then the goal made yours. Kept
/// as a word, so an app closed halfway picks up where it was.
enum FirstRun: String {
    /// The welcome screen is up.
    case welcome
    /// The first-bite sheet is up over Today.
    case firstBite
    /// You went to scan or search for the first food; the goal comes once it is logged.
    case awaitingLog
    /// The goal sheet comes next, or is up.
    case goal
    case done
}

/// Foods for the hour, from the basics: what most people have at this time of day, for the
/// first bite and for an empty day. Hours as `Meal.likely` splits them.
enum HourFoods {
    enum Moment: Equatable {
        case morning
        case noon
        case afternoon
        case evening
    }

    static func moment(at date: Date, calendar: Calendar = .current) -> Moment {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .morning
        case 11..<15: .noon
        case 15..<18: .afternoon
        default: .evening
        }
    }

    /// Eight basics for the moment, by their USDA id, most likely first.
    static func ids(for moment: Moment) -> [Int] {
        switch moment {
        // Coffee, croissant, Greek yogurt, banana, egg, white bread, orange juice, granola.
        case .morning: [171890, 174987, 171304, 173944, 171287, 174924, 169098, 171646]
        // Pasta, chicken breast, rice, cheese pizza, salmon, a wrap, apple, Greek yogurt.
        case .noon: [169737, 171477, 168878, 170317, 175168, 175037, 171688, 171304]
        // Apple, banana, almonds, dark chocolate, Greek yogurt, coffee, a cookie, peanuts.
        case .afternoon: [171688, 173944, 170567, 170273, 171304, 171890, 172716, 173806]
        // Pasta, salmon, cheese pizza, chicken breast, rice, red wine, beer, vanilla ice cream.
        case .evening: [169737, 175168, 170317, 171477, 168878, 173190, 168746, 167575]
        }
    }

    /// The short name a food tile shows ("Chicken breast", not "Chicken breast, cooked"), so
    /// every tile reads in one or two lines at the same size. Nil for any other food.
    static func label(for foodID: String) -> String? {
        guard foodID.hasPrefix("usda:"), let id = Int(foodID.dropFirst(5)) else { return nil }
        return switch id {
        case 171890: tr("Coffee")
        case 174987: tr("Croissant")
        case 171304: tr("Greek yogurt")
        case 173944: tr("Banana")
        case 171287: tr("Egg")
        case 174924: tr("White bread")
        case 169098: tr("Orange juice")
        case 171646: tr("Granola")
        case 169737: tr("Pasta")
        case 171477: tr("Chicken breast")
        case 168878: tr("Rice")
        case 170317: tr("Pizza")
        case 175168: tr("Salmon")
        case 175037: tr("Wrap")
        case 171688: tr("Apple")
        case 170567: tr("Almonds")
        case 170273: tr("Dark chocolate")
        case 172716: tr("Cookie")
        case 173806: tr("Peanuts")
        case 173190: tr("Red wine")
        case 168746: tr("Beer")
        case 167575: tr("Ice cream")
        default: nil
        }
    }

    static func foodIDs(at date: Date, calendar: Calendar = .current) -> [String] {
        ids(for: moment(at: date, calendar: calendar)).map { "usda:\($0)" }
    }

    /// The first bite's question, by the hour.
    static func question(at date: Date, calendar: Calendar = .current) -> String {
        switch moment(at: date, calendar: calendar) {
        case .morning: tr("What did you have this morning?")
        case .noon: tr("What did you have for lunch?")
        case .afternoon, .evening: tr("What did you eat last?")
        }
    }

    /// Late in the evening, the first run offers to start tomorrow instead of "Nothing yet".
    static func isLate(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 21 || hour < 4
    }
}
