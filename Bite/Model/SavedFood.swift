import Foundation
import SwiftData

/// A food you keep at hand. One tap adds it to today, and you choose how it looks:
/// its name, a line under it, an emoji or a photo, and its color.
@Model
final class SavedFood {
    var createdAt: Date = Date.now
    var sortIndex: Int = 0
    var name: String = ""
    var subtitle: String?
    /// When set, the emoji is the picture; when nil, the photo is.
    var emoji: String?
    var tintRaw: String = FoodTint.sand.rawValue
    @Attribute(.externalStorage) var imageData: Data?
    var imageURLString: String?
    var foodID: String = ""
    var brand: String?
    var barcode: String?
    var sourceRaw: String = FoodSource.manual.rawValue
    var unitRaw: String = FoodUnit.gram.rawValue
    var per: Double = 100
    /// How much one tap adds.
    var amount: Double = 100
    /// The meal it goes to; nil follows the time of day.
    var mealRaw: String?
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var sugar: Double?
    var fiber: Double?
    var saturatedFat: Double?
    var salt: Double?
    var nutriScore: String?
    var novaGroup: Int?
    var portionsData: Data?
    var timesAdded: Int = 0

    init(food: Food, amount: Double, sortIndex: Int = 0) {
        self.sortIndex = sortIndex
        self.name = food.name
        let hasPhoto = food.imageData != nil || food.imageURL != nil
        self.emoji = hasPhoto ? nil : (food.emoji ?? "🍽️")
        self.tintRaw = food.displayTint.rawValue
        self.imageData = food.imageData
        self.imageURLString = food.imageURL?.absoluteString
        self.foodID = food.id
        self.brand = food.brand
        self.barcode = food.barcode
        self.sourceRaw = food.source.rawValue
        self.unitRaw = food.unit.rawValue
        self.per = food.per
        self.amount = amount
        self.kcal = food.nutrients.kcal
        self.protein = food.nutrients.protein
        self.carbs = food.nutrients.carbs
        self.fat = food.nutrients.fat
        self.sugar = food.nutrients.sugar
        self.fiber = food.nutrients.fiber
        self.saturatedFat = food.nutrients.saturatedFat
        self.salt = food.nutrients.salt
        self.nutriScore = food.nutriScore
        self.novaGroup = food.novaGroup
        self.portionsData = try? JSONEncoder().encode(food.portions)
    }
}

extension SavedFood {
    var tint: FoodTint {
        get { FoodTint(rawValue: tintRaw) ?? .sand }
        set { tintRaw = newValue.rawValue }
    }

    var meal: Meal? {
        get { mealRaw.flatMap { Meal(rawValue: $0) } }
        set { mealRaw = newValue?.rawValue }
    }

    var hasPhoto: Bool { imageData != nil || imageURLString != nil }

    /// The saved food as a `Food`, with your name and picture in place of the original's.
    var food: Food {
        let showsEmoji = emoji != nil || !hasPhoto
        return Food(
            id: foodID,
            name: name,
            brand: brand,
            barcode: barcode,
            imageURL: showsEmoji ? nil : imageURLString.flatMap { URL(string: $0) },
            emoji: showsEmoji ? (emoji ?? "🍽️") : nil,
            source: FoodSource(rawValue: sourceRaw) ?? .manual,
            unit: FoodUnit(rawValue: unitRaw) ?? .gram,
            per: per,
            nutrients: Nutrients(
                kcal: kcal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                sugar: sugar,
                fiber: fiber,
                saturatedFat: saturatedFat,
                salt: salt
            ),
            portions: portionsData.flatMap { try? JSONDecoder().decode([Portion].self, from: $0) } ?? [],
            nutriScore: nutriScore,
            novaGroup: novaGroup,
            tint: tint,
            imageData: showsEmoji ? nil : imageData
        )
    }

    /// What one tap adds to the day.
    var totals: Nutrients {
        Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat).scaled(by: per > 0 ? amount / per : 0)
    }
}
