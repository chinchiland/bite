import Foundation

enum FoodSource: String, Hashable {
    case openFoodFacts
    case usda
    case manual
    /// Estimated by Claude from a photo of the meal.
    case ai
}

enum FoodUnit: String, Hashable {
    case gram
    case milliliter
    case serving

    var symbol: String {
        switch self {
        case .gram: "g"
        case .milliliter: "ml"
        case .serving: tr("serving")
        }
    }

    /// How far one tap on − or + moves the amount.
    var step: Double { self == .serving ? 0.5 : 10 }

    /// "150 g", "250 ml", "1 serving", "1.5 servings".
    func format(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...1)))
        switch self {
        case .gram, .milliliter: return "\(number) \(symbol)"
        case .serving: return amount == 1 ? tr("1 serving") : tr("%@ servings", number)
        }
    }
}

/// A named amount people actually eat: "1 medium" banana is 118 g.
struct Portion: Hashable, Codable {
    var label: String
    var amount: Double
}

/// A food you can log, whatever it came from: a scanned product, a basic food or a quick add.
struct Food: Identifiable, Hashable {
    var id: String
    var name: String
    var brand: String?
    var barcode: String?
    var imageURL: URL?
    var emoji: String?
    var source: FoodSource
    var unit: FoodUnit
    /// The amount `nutrients` describe: 100 g or 100 ml, or 1 serving for quick adds.
    var per: Double
    var nutrients: Nutrients
    var portions: [Portion]
    /// Nutri-Score grade, "a" to "e".
    var nutriScore: String?
    /// NOVA processing group, 1 (unprocessed) to 4 (ultra-processed).
    var novaGroup: Int?
    var allergens: [String]
    var hasNutrition: Bool
    /// The soft color behind the emoji; nil picks one from the emoji.
    var tint: FoodTint?
    /// A photo you took, small enough to keep: a meal you estimated or a saved food's picture.
    var imageData: Data?

    init(
        id: String,
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        imageURL: URL? = nil,
        emoji: String? = nil,
        source: FoodSource,
        unit: FoodUnit = .gram,
        per: Double = 100,
        nutrients: Nutrients,
        portions: [Portion] = [],
        nutriScore: String? = nil,
        novaGroup: Int? = nil,
        allergens: [String] = [],
        hasNutrition: Bool = true,
        tint: FoodTint? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.imageURL = imageURL
        self.emoji = emoji
        self.source = source
        self.unit = unit
        self.per = per
        self.nutrients = nutrients
        self.portions = portions
        self.nutriScore = nutriScore
        self.novaGroup = novaGroup
        self.allergens = allergens
        self.hasNutrition = hasNutrition
        self.tint = tint
        self.imageData = imageData
    }

    var displayTint: FoodTint { tint ?? FoodTint.suggested(for: emoji) }

    /// The amount a fresh log starts at: the first named portion, else the nutrient basis.
    var defaultAmount: Double { portions.first?.amount ?? per }

    func nutrients(for amount: Double) -> Nutrients {
        nutrients.scaled(by: per > 0 ? amount / per : 0)
    }

    /// "1 medium · 118 g" when the amount has a name, otherwise just "150 g".
    func portionText(for amount: Double) -> String {
        let measure = unit.format(amount)
        if unit != .serving,
           let portion = portions.first(where: { abs($0.amount - amount) < 0.01 }),
           portion.label != measure {
            return "\(portion.label) · \(measure)"
        }
        return measure
    }

    var sourceName: String {
        switch source {
        case .openFoodFacts: "Open Food Facts"
        case .usda: "USDA FoodData Central"
        case .manual: "you"
        case .ai: "Claude"
        }
    }

    /// The page that holds this food's data, so every number can be checked at its source.
    var sourceURL: URL? {
        switch source {
        case .openFoodFacts:
            guard let barcode else { return nil }
            return URL(string: "https://world.openfoodfacts.org/product/\(barcode)")
        case .usda:
            guard let fdcID = id.split(separator: ":").last else { return nil }
            return URL(string: "https://fdc.nal.usda.gov/food-details/\(fdcID)/nutrients")
        case .manual, .ai:
            return nil
        }
    }
}
