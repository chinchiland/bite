import Foundation
import SwiftData

/// One thing you ate. It keeps its own copy of the food's data, so the log never changes
/// when a database entry does.
@Model
final class FoodEntry {
    var date: Date = Date.now
    var mealRaw: String = Meal.snack.rawValue
    var foodID: String = ""
    var name: String = ""
    var brand: String?
    var barcode: String?
    var imageURLString: String?
    var emoji: String?
    var sourceRaw: String = FoodSource.manual.rawValue
    var unitRaw: String = FoodUnit.gram.rawValue
    /// The amount the nutrient values below describe.
    var per: Double = 100
    /// How much you ate, in `unitRaw`.
    var amount: Double = 100
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
    var allergensText: String?
    var portionsData: Data?
    var tintRaw: String?
    /// The meal photo for an AI estimate, or a saved food's own picture.
    @Attribute(.externalStorage) var imageData: Data?
    /// Where you ate it, when you said so: a place picked from the ones around you.
    var placeName: String?
    var placeArea: String?
    var placeLatitude: Double?
    var placeLongitude: Double?
    var placeCategoryRaw: String?

    init(food: Food, amount: Double, meal: Meal, date: Date, place: MealPlace? = nil) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.foodID = food.id
        self.name = food.name
        self.brand = food.brand
        self.barcode = food.barcode
        self.imageURLString = food.imageURL?.absoluteString
        self.emoji = food.emoji
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
        self.allergensText = food.allergens.isEmpty ? nil : food.allergens.joined(separator: "|")
        self.portionsData = try? JSONEncoder().encode(food.portions)
        self.tintRaw = food.tint?.rawValue
        self.imageData = food.imageData
        self.place = place
    }
}

extension FoodEntry {
    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var place: MealPlace? {
        get {
            placeName.map {
                MealPlace(
                    name: $0,
                    area: placeArea,
                    latitude: placeLatitude,
                    longitude: placeLongitude,
                    category: placeCategoryRaw.flatMap(MealPlace.Category.init(rawValue:))
                )
            }
        }
        set {
            placeName = newValue?.name
            placeArea = newValue?.area
            placeLatitude = newValue?.latitude
            placeLongitude = newValue?.longitude
            placeCategoryRaw = newValue?.category?.rawValue
        }
    }

    var food: Food {
        Food(
            id: foodID,
            name: name,
            brand: brand,
            barcode: barcode,
            imageURL: imageURLString.flatMap { URL(string: $0) },
            emoji: emoji,
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
            allergens: allergensText?.components(separatedBy: "|") ?? [],
            tint: tintRaw.flatMap { FoodTint(rawValue: $0) },
            imageData: imageData
        )
    }

    /// What this entry adds to the day.
    var totals: Nutrients {
        Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat).scaled(by: per > 0 ? amount / per : 0)
    }

    /// "Danone · 120 g" for a product, "1 medium · 118 g" for a basic.
    var detailText: String {
        let food = self.food
        if let brand, !brand.isEmpty { return "\(brand) · \(food.unit.format(amount))" }
        return food.portionText(for: amount)
    }
}
