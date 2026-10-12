import Foundation

/// Everyday whole foods (a banana, an egg, a bowl of rice) from USDA FoodData Central,
/// bundled so they show up instantly and offline. Rebuild with tools/build_basics.py.
enum BasicFoods {
    /// A basic and the phrases it answers to: its name in the reader's language first, then
    /// its English name, its names in the other languages and its French aliases.
    struct Entry {
        /// The English name, the same in every language, for code that looks a basic up.
        let key: String
        let food: Food
        let phrases: [[String]]
    }

    static let index: [Entry] = load(from: Bundle.main.url(forResource: "basics", withExtension: "json"))
    static var all: [Food] { index.map { $0.food } }

    private struct Record: Decodable {
        let id: Int
        let name: String
        /// The name in French and Spanish, keyed "fr" and "es".
        let names: [String: String]?
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
        let portions: [RecordPortion]
    }

    private struct RecordPortion: Decodable {
        let label: String
        let amount: Double
        let labels: [String: String]?
    }

    /// The basics with their names and portions in `language` ("en", "fr" or "es").
    static func load(from url: URL?, language: String = AppLanguage.current) -> [Entry] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records.map { record in
            let name = record.names?[language] ?? record.name
            let food = Food(
                id: "usda:\(record.id)",
                name: name,
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
                portions: record.portions.map { Portion(label: $0.labels?[language] ?? $0.label, amount: $0.amount) }
            )
            var seen = Set<String>()
            let names = [name, record.name] + (record.names ?? [:]).sorted { $0.key < $1.key }.map(\.value) + record.aliases
            let phrases = names.filter { seen.insert($0.lowercased()).inserted }.map(SearchText.words(in:))
            return Entry(key: record.name, food: food, phrases: phrases)
        }
    }

    static func search(_ query: String) -> [Food] {
        search(query, in: index)
    }

    /// Basics where every word of the query starts a word of one phrase. The name in your
    /// language beats the others, and a phrase with fewer extra words beats a longer one, so
    /// "riz" finds cooked rice before "riz cru"; the list's own order settles a tie, so "milk" is
    /// whole milk. When nothing starts that way, one slip per word is forgiven, so a typo still
    /// finds its food.
    static func search(_ query: String, in entries: [Entry]) -> [Food] {
        let terms = SearchText.words(in: query)
        let typed = ranked(terms, in: entries) { $0.hasPrefix($1) }
        guard typed.isEmpty else { return typed }
        return ranked(terms, in: entries, starts: SearchText.nearlyStarts)
    }

    private static func ranked(_ terms: [String], in entries: [Entry], starts: (String, String) -> Bool) -> [Food] {
        guard let firstTerm = terms.first else { return [] }

        var scored: [(food: Food, score: Int, order: Int)] = []
        for (order, entry) in entries.enumerated() {
            var best: Int?
            for (index, phrase) in entry.phrases.enumerated() {
                guard terms.allSatisfy({ term in phrase.contains { starts($0, term) } }) else { continue }
                var score = index == 0 ? 0 : 100
                if let first = phrase.first, !starts(first, firstTerm) { score += 50 }
                score += max(phrase.count - terms.count, 0) * 10
                if !terms.allSatisfy({ phrase.contains($0) }) { score += 1 }
                best = min(best ?? score, score)
            }
            if let best { scored.append((food: entry.food, score: best, order: order)) }
        }
        return scored
            .sorted { ($0.score, $0.order) < ($1.score, $1.order) }
            .map { $0.food }
    }
}
