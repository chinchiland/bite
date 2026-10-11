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

        var nutrients: Nutrients {
            Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
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
                fat: fat * factor
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

    var title: String
    var emoji: String
    var confidence: Confidence
    var note: String
    var items: [Item]

    var totals: Nutrients {
        items.reduce(Nutrients.zero) { $0 + $1.nutrients }
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
            ],
            "required": ["name", "emoji", "grams", "kcal", "protein", "carbs", "fat"],
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
            ],
            "required": ["title", "emoji", "confidence", "note", "items"],
            "additionalProperties": false,
        ]
    }
}
