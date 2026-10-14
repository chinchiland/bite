import Foundation

/// A dish as it is usually served, read off a menu or typed in search: one typical portion's
/// grams and nutrition, then made yours in two taps, how rich it was and how big. Foundation
/// only, so the math is tested on Linux. The server answers in this shape
/// (server/supabase/functions/estimate/menu.ts): change the two together.
struct TypicalDish: Codable, Equatable, Hashable {
    var title: String
    var emoji: String
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var sugar: Double?

    /// How rich it was: what changes is the fat (the oil, the cheese, the sauce), and its
    /// calories with it, at 9 kcal a gram.
    enum Richness: String, CaseIterable, Codable, Hashable {
        case lean
        case regular
        case rich

        var fatFactor: Double {
            switch self {
            case .lean: 0.6
            case .regular: 1
            case .rich: 1.5
            }
        }

        var title: String {
            switch self {
            case .lean: tr("Lean")
            case .regular: tr("Regular")
            case .rich: tr("Rich")
            }
        }
    }

    /// How big it was, against the usual portion.
    enum Size: String, CaseIterable, Codable, Hashable {
        case small
        case regular
        case big
        case huge

        var factor: Double {
            switch self {
            case .small: 0.7
            case .regular: 1
            case .big: 1.35
            case .huge: 1.75
            }
        }

        var title: String {
            switch self {
            case .small: tr("Small")
            case .regular: tr("Usual")
            case .big: tr("Big")
            case .huge: tr("Huge")
            }
        }
    }

    /// Why a dish typed in search came back without one.
    enum Failure: Error, Equatable {
        /// The words were not a food or a drink.
        case notFood
        case unreadable
    }

    /// Real amounts only: anything else and the dish is not offered. Water and black coffee
    /// are real at zero calories; a dish of no grams is not.
    var isUsable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && [grams, kcal, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 < 20_000 }
            && grams > 0
    }

    /// The usual portion at this richness.
    func nutrients(_ richness: Richness) -> Nutrients {
        let newFat = fat * richness.fatFactor
        return Nutrients(
            kcal: max(kcal + (newFat - fat) * 9, 0),
            protein: protein,
            carbs: carbs,
            fat: newFat,
            sugar: sugar.flatMap { $0.isFinite && $0 >= 0 && $0 <= carbs + 1 ? $0 : nil },
            fiber: fiber.flatMap { $0.isFinite && $0 >= 0 && $0 <= carbs + 1 ? $0 : nil }
        )
    }

    /// What you had: this richness, this size.
    func nutrients(_ richness: Richness, _ size: Size) -> Nutrients {
        nutrients(richness).scaled(by: size.factor)
    }

    func grams(_ size: Size) -> Double {
        (grams * size.factor).rounded()
    }

    /// The dish as a food to log, in grams so it reads "Chicken shawarma · 473 g" in your day,
    /// with the four sizes named for next time, the usual one first so it is where a new log
    /// starts. `id` names the dish, and each richness is its own food: the same lean shawarma
    /// logged again is one line in Recent.
    func food(_ richness: Richness, id: String, brand: String? = nil) -> Food {
        Food(
            id: "\(id):\(richness.rawValue)",
            name: title,
            brand: brand.flatMap { $0.isEmpty ? nil : $0 },
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            source: .typical,
            unit: .gram,
            per: grams,
            nutrients: nutrients(richness),
            portions: [Size.regular, .small, .big, .huge].map { Portion(label: $0.title, amount: grams($0)) }
        )
    }

    /// "typical:chicken-shawarma": a typed dish is the same food whatever words found it.
    static func typedID(_ title: String) -> String {
        "typical:" + SearchText.words(in: title).joined(separator: "-")
    }

    /// The words of a dish typed in search as they are sent: one line, no quotes, 80 characters
    /// at most. The server cleans them the same way.
    static func cleanName(_ text: String) -> String {
        let flat = text.map { "\"\n\r".contains($0) ? " " : $0 }
        return String(String(flat).trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    /// The answer for a dish typed in search: the dish, or why there is none.
    static func read(_ data: Data) throws -> TypicalDish {
        struct Answer: Decodable {
            var title: String
            var isFood: Bool
            var emoji: String
            var grams: Double
            var kcal: Double
            var protein: Double
            var carbs: Double
            var fat: Double
            var fiber: Double?
            var sugar: Double?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw Failure.unreadable }
        guard answer.isFood else { throw Failure.notFood }
        let dish = TypicalDish(
            title: answer.title.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: answer.emoji,
            grams: answer.grams,
            kcal: answer.kcal,
            protein: answer.protein,
            carbs: answer.carbs,
            fat: answer.fat,
            fiber: answer.fiber,
            sugar: answer.sugar
        )
        guard dish.isUsable else { throw Failure.unreadable }
        return dish
    }

    /// The nutrition every typical dish carries, in the answer's JSON schema.
    static var schemaProperties: [String: Any] {
        [
            "emoji": ["type": "string", "description": "One food emoji."],
            "grams": ["type": "number", "description": "Grams of a typical portion."],
            "kcal": ["type": "number"],
            "protein": ["type": "number"],
            "carbs": ["type": "number"],
            "fat": ["type": "number"],
            "fiber": ["type": "number"],
            "sugar": ["type": "number"],
        ]
    }

    static let schemaRequired = ["emoji", "grams", "kcal", "protein", "carbs", "fat", "fiber", "sugar"]

    /// The JSON schema of the answer for a dish typed in search.
    static var schema: [String: Any] {
        var properties = schemaProperties
        properties["title"] = ["type": "string", "description": "Short name of the dish, in the requested language."]
        properties["isFood"] = ["type": "boolean"]
        return [
            "type": "object",
            "properties": properties,
            "required": ["title", "isFood"] + schemaRequired,
            "additionalProperties": false,
        ]
    }
}

/// A menu read from a photo: the restaurant when it says so, and its dishes as usually served.
struct MenuScan: Codable, Equatable, Hashable, Identifiable {
    struct Dish: Codable, Equatable, Hashable, Identifiable {
        var name: String
        var description: String
        var price: String
        var dish: TypicalDish

        var id: String { "\(name)|\(price)" }
    }

    var id = UUID()
    var takenAt = Date.now
    var restaurant: String
    var dishes: [Dish]
    /// Where you photographed it, when you said.
    var place: MealPlace?

    /// What the menu is called: its restaurant, the place you set, or just Menu.
    var title: String {
        if !restaurant.isEmpty { return restaurant }
        if let place, !place.name.isEmpty { return place.name }
        return tr("Menu")
    }

    /// One of its dishes as a food to log: the restaurant as its brand, so it reads
    /// "Shawarma poulet · El Beirout" in Recent.
    func food(_ dish: Dish, _ richness: TypicalDish.Richness) -> Food {
        let id = "menu:\(self.id.uuidString):" + SearchText.words(in: "\(dish.name) \(dish.price)").joined(separator: "-")
        let brand = restaurant.isEmpty ? place?.name : restaurant
        return dish.dish.food(richness, id: id, brand: brand)
    }

    /// The server's answer, made safe: dishes with real amounts, at most 60, no repeats.
    static func read(_ data: Data) -> MenuScan? {
        struct Answer: Decodable {
            struct Item: Decodable {
                var name: String
                var description: String
                var price: String
                var emoji: String
                var grams: Double
                var kcal: Double
                var protein: Double
                var carbs: Double
                var fat: Double
                var fiber: Double?
                var sugar: Double?
            }

            var restaurant: String
            var dishes: [Item]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return nil }
        var seen: Set<String> = []
        let dishes: [Dish] = answer.dishes.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let dish = TypicalDish(title: name, emoji: item.emoji, grams: item.grams, kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat, fiber: item.fiber, sugar: item.sugar)
            let entry = Dish(name: name, description: item.description.trimmingCharacters(in: .whitespacesAndNewlines), price: item.price.trimmingCharacters(in: .whitespacesAndNewlines), dish: dish)
            guard dish.isUsable, seen.insert(entry.id).inserted else { return nil }
            return entry
        }
        return MenuScan(restaurant: answer.restaurant.trimmingCharacters(in: .whitespacesAndNewlines), dishes: Array(dishes.prefix(60)))
    }

    /// The menu's dishes whose name holds every word typed, for search.
    func dishes(matching query: String) -> [Dish] {
        let terms = SearchText.words(in: query)
        guard !terms.isEmpty else { return [] }
        return dishes.filter { SearchText.matches(terms, in: SearchText.words(in: "\($0.name) \($0.description)")) }
    }

    /// The JSON schema of a menu's answer.
    static var schema: [String: Any] {
        var properties = TypicalDish.schemaProperties
        properties["name"] = ["type": "string"]
        properties["description"] = ["type": "string", "description": "A few words, or empty."]
        properties["price"] = ["type": "string", "description": "As written on the menu, or empty."]
        let dish: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["name", "description", "price"] + TypicalDish.schemaRequired,
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "restaurant": ["type": "string", "description": "The restaurant's name as the menu shows it, or empty."],
                "dishes": ["type": "array", "items": dish],
            ],
            "required": ["restaurant", "dishes"],
            "additionalProperties": false,
        ]
    }
}
