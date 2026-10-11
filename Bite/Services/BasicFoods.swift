import Foundation

/// Everyday whole foods (a banana, an egg, a bowl of rice) from USDA FoodData Central,
/// bundled so they show up instantly and offline. Rebuild with tools/build_basics.py.
enum BasicFoods {
    /// A basic and the phrases it answers to: its English name first, then its French names.
    struct Entry {
        let food: Food
        let phrases: [[String]]
    }

    static let index: [Entry] = load(from: Bundle.main.url(forResource: "basics", withExtension: "json"))
    static var all: [Food] { index.map { $0.food } }

    private struct Record: Decodable {
        let id: Int
        let name: String
        let emoji: String
        let unit: String
        let aliases: [String]
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let sugar: Double?
        let fiber: Double?
        let saturatedFat: Double?
        let salt: Double?
        let portions: [Portion]
    }

    static func load(from url: URL?) -> [Entry] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records.map { record in
            let food = Food(
                id: "usda:\(record.id)",
                name: record.name,
                emoji: record.emoji,
                source: .usda,
                unit: record.unit == "ml" ? .milliliter : .gram,
                per: 100,
                nutrients: Nutrients(
                    kcal: record.kcal,
                    protein: record.protein,
                    carbs: record.carbs,
                    fat: record.fat,
                    sugar: record.sugar,
                    fiber: record.fiber,
                    saturatedFat: record.saturatedFat,
                    salt: record.salt
                ),
                portions: record.portions
            )
            return Entry(food: food, phrases: ([record.name] + record.aliases).map(SearchText.words(in:)))
        }
    }

    static func search(_ query: String) -> [Food] {
        search(query, in: index)
    }

    /// Basics where every word of the query starts a word of one phrase. The English name
    /// beats a French alias, and a phrase with fewer extra words beats a longer one, so
    /// "riz" finds cooked rice before "riz cru".
    static func search(_ query: String, in entries: [Entry]) -> [Food] {
        let terms = SearchText.words(in: query)
        guard let firstTerm = terms.first else { return [] }

        var scored: [(food: Food, score: Int)] = []
        for entry in entries {
            var best: Int?
            for (index, phrase) in entry.phrases.enumerated() {
                guard SearchText.matches(terms, in: phrase) else { continue }
                var score = index == 0 ? 0 : 100
                if phrase.first?.hasPrefix(firstTerm) != true { score += 50 }
                score += max(phrase.count - terms.count, 0) * 10
                if !terms.allSatisfy({ phrase.contains($0) }) { score += 1 }
                best = min(best ?? score, score)
            }
            if let best { scored.append((food: entry.food, score: best)) }
        }
        return scored
            .sorted { ($0.score, $0.food.name.count) < ($1.score, $1.food.name.count) }
            .map { $0.food }
    }
}
