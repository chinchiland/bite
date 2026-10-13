import Foundation

/// What Claude sees in a photo of a meal: each food with its estimated amount and nutrition.
struct MealEstimate: Decodable, Equatable {
    struct Item: Decodable, Equatable {
        var name: String
        var emoji: String
        var grams: Double
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double? = nil
        var sugar: Double? = nil

        var nutrients: Nutrients {
            Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat, sugar: sugar, fiber: fiber)
        }

        /// The same food at a different amount, nutrition scaled to match.
        func with(grams newGrams: Double) -> Item {
            guard grams > 0, newGrams.isFinite, newGrams >= 0 else { return self }
            let factor = newGrams / grams
            return Item(
                name: name,
                emoji: emoji,
                grams: newGrams,
                kcal: kcal * factor,
                protein: protein * factor,
                carbs: carbs * factor,
                fat: fat * factor,
                fiber: fiber.map { $0 * factor },
                sugar: sugar.map { $0 * factor }
            )
        }
    }

    enum Confidence: String, Decodable {
        case high
        case medium
        case low

        var label: String {
            switch self {
            case .high: tr("Sure about this one")
            case .medium: tr("Good estimate")
            case .low: tr("Rough estimate")
            }
        }
    }

    /// The one thing most likely to change the number, as a question answered in one tap:
    /// each answer is how many grams of one item there were.
    struct Doubt: Decodable, Equatable {
        struct Answer: Decodable, Equatable {
            var label: String
            var grams: Double
        }

        var question: String
        /// The item the answers are about, by its place in `items`.
        var item: Int
        var answers: [Answer]

        /// A question, two or three answers with real amounts, about an item with grams to
        /// scale from. Anything less is left as the note.
        func isAskable(about item: Item) -> Bool {
            !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (2...3).contains(answers.count)
                && item.grams > 0
                && answers.allSatisfy { !$0.label.isEmpty && $0.grams.isFinite && $0.grams >= 0 && $0.grams < 5000 }
        }

        /// The answer that matches the item's grams now, if one does.
        func chosen(in items: [Item]) -> Int? {
            guard items.indices.contains(item) else { return nil }
            return answers.firstIndex { abs($0.grams - items[item].grams) < 0.5 }
        }
    }

    var title: String
    var emoji: String
    var confidence: Confidence
    var note: String
    var items: [Item]
    var doubt: Doubt? = nil

    var totals: Nutrients {
        items.reduce(Nutrients.zero) { $0 + $1.nutrients }
    }

    /// The plate with one item at another amount, scaled from `original`, what Claude first
    /// saw, so an item set to nothing can come back.
    func setting(item index: Int, grams: Double, from original: MealEstimate) -> MealEstimate {
        guard items.indices.contains(index), original.items.indices.contains(index) else { return self }
        var copy = self
        copy.items[index] = original.items[index].with(grams: grams)
        return copy
    }

    /// The whole plate as one food you can log: one serving is everything in the photo.
    func food(imageData: Data?) -> Food {
        Food(
            id: "ai:\(UUID().uuidString)",
            name: title,
            emoji: emoji.isEmpty ? "🍽️" : emoji,
            source: .ai,
            unit: .serving,
            per: 1,
            nutrients: totals,
            imageData: imageData
        )
    }

    /// The JSON shape Claude must answer in. Every object closes with additionalProperties
    /// false, which structured outputs require.
    static var schema: [String: Any] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "emoji": ["type": "string"],
                "grams": ["type": "number"],
                "kcal": ["type": "number"],
                "protein": ["type": "number"],
                "carbs": ["type": "number"],
                "fat": ["type": "number"],
                "fiber": ["type": "number"],
                "sugar": ["type": "number"],
            ],
            "required": ["name", "emoji", "grams", "kcal", "protein", "carbs", "fat", "fiber", "sugar"],
            "additionalProperties": false,
        ]
        let answer: [String: Any] = [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "Two or three words, in the requested language."],
                "grams": ["type": "number", "description": "Grams of the item for this answer."],
            ],
            "required": ["label", "grams"],
            "additionalProperties": false,
        ]
        let doubt: [String: Any] = [
            "type": "object",
            "properties": [
                "question": ["type": "string", "description": "A short question about the one thing most likely to change the number, or empty."],
                "item": ["type": "integer", "description": "Index in items, 0 for the first, of the food the answers are about."],
                "answers": ["type": "array", "items": answer, "description": "Two or three answers from least to most, or none."],
            ],
            "required": ["question", "item", "answers"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "Short name for the whole meal, in the requested language."],
                "emoji": ["type": "string", "description": "One food emoji for the meal."],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                "note": ["type": "string", "description": "One short sentence on what could change the estimate, or empty."],
                "items": ["type": "array", "items": item],
                "doubt": doubt,
            ],
            "required": ["title", "emoji", "confidence", "note", "items", "doubt"],
            "additionalProperties": false,
        ]
    }
}
