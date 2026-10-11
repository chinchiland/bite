#if DEBUG
import Foundation
import SwiftData
import UIKit

/// A believable week of logs for previews and screenshots. Launch with `-demo` to use it;
/// it lives in memory and never touches your real log.
enum DemoData {
    /// Real Open Food Facts data for Danone's skyr, so the demo shows what a scan returns.
    static let skyr = Food(
        id: "off:3033491704642",
        name: "Skyr nature 0%",
        brand: "Danone",
        barcode: "3033491704642",
        imageURL: URL(string: "https://images.openfoodfacts.org/images/products/303/349/170/4642/front_en.84.200.jpg"),
        source: .openFoodFacts,
        nutrients: Nutrients(kcal: 57, protein: 10, carbs: 3.9, fat: 0.2, sugar: 3.9, saturatedFat: 0.1, salt: 0.09),
        portions: [
            Portion(label: "1 serving", amount: 120),
            Portion(label: "100 g", amount: 100),
            Portion(label: "Whole pack", amount: 825),
        ],
        nutriScore: "a",
        novaGroup: 1,
        allergens: ["Milk"]
    )

    static let toblerone = Food(
        id: "off:7614500010013",
        name: "Milk Chocolate Almond Nougat",
        brand: "Toblerone",
        barcode: "7614500010013",
        imageURL: URL(string: "https://images.openfoodfacts.org/images/products/761/450/001/0013/front_en.362.200.jpg"),
        source: .openFoodFacts,
        nutrients: Nutrients(kcal: 529, protein: 5.6, carbs: 61, fat: 28, sugar: 60, fiber: 2.4, saturatedFat: 17, salt: 0.12),
        portions: [Portion(label: "1 serving", amount: 25), Portion(label: "100 g", amount: 100)],
        nutriScore: "e",
        novaGroup: 4,
        allergens: ["Eggs", "Milk", "Nuts", "Soybeans"]
    )

    /// What Claude returns for a salmon bowl (same shape as the API answer).
    static let estimate = MealEstimate(
        title: "Salmon salad bowl",
        emoji: "🥗",
        confidence: .medium,
        note: "The dressing could add 50 kcal if it was poured generously.",
        items: [
            MealEstimate.Item(name: "Salmon", emoji: "🐟", grams: 120, kcal: 250, protein: 25.2, carbs: 0, fat: 16.2),
            MealEstimate.Item(name: "Egg", emoji: "🥚", grams: 50, kcal: 72, protein: 6.3, carbs: 0.4, fat: 4.8),
            MealEstimate.Item(name: "Sweet corn", emoji: "🌽", grams: 60, kcal: 52, protein: 1.6, carbs: 11.2, fat: 0.7),
            MealEstimate.Item(name: "Edamame", emoji: "🫛", grams: 50, kcal: 61, protein: 5.5, carbs: 4.5, fat: 2.6),
            MealEstimate.Item(name: "Greens", emoji: "🥬", grams: 150, kcal: 38, protein: 2, carbs: 7.2, fat: 0.3),
            MealEstimate.Item(name: "Sesame dressing", emoji: "🫙", grams: 20, kcal: 90, protein: 0.6, carbs: 3, fat: 8.4),
        ]
    )

    /// A stand-in plate photo for screenshots, drawn so it needs no file or camera.
    static func platePhoto(size: CGSize = CGSize(width: 900, height: 900)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1).setFill()
            context.fill(rect)
            let plate = rect.insetBy(dx: size.width * 0.08, dy: size.height * 0.08)
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(ovalIn: plate).fill()
            UIColor(white: 0.9, alpha: 1).setStroke()
            let rim = UIBezierPath(ovalIn: plate.insetBy(dx: size.width * 0.07, dy: size.height * 0.07))
            rim.lineWidth = 6
            rim.stroke()
            let foods: [(String, CGFloat, CGFloat, CGFloat)] = [
                ("🥬", 0.34, 0.40, 0.28), ("🐟", 0.62, 0.38, 0.28), ("🥚", 0.40, 0.66, 0.22), ("🌽", 0.64, 0.64, 0.22),
            ]
            for (emoji, x, y, scale) in foods {
                let font = UIFont.systemFont(ofSize: size.width * scale)
                let text = NSAttributedString(string: emoji, attributes: [.font: font])
                let bounds = text.size()
                text.draw(at: CGPoint(x: size.width * x - bounds.width / 2, y: size.height * y - bounds.height / 2))
            }
        }
    }

    /// Steps and burned calories for screenshots, without asking Apple Health.
    static func activity(on day: Date) -> DayActivity {
        let daysAgo = Calendar.current.dateComponents([.day], from: day, to: .now).day ?? 0
        let steps: [Double] = [8432, 11250, 6120, 9874, 4310, 12480, 7650]
        let burned: [Double] = [412, 538, 296, 471, 205, 602, 377]
        let index = min(max(daysAgo, 0), steps.count - 1)
        return DayActivity(steps: steps[index], activeKcal: burned[index])
    }

    static func container() -> ModelContainer {
        let container = try! ModelContainer(for: FoodEntry.self, SavedFood.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        MainActor.assumeIsolated { seed(container.mainContext) }
        return container
    }

    @MainActor static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func basic(_ name: String) -> Food? {
            BasicFoods.all.first { $0.name == name }
        }

        func log(_ food: Food?, _ amount: Double, _ meal: Meal, daysAgo: Int, at hour: Int) {
            guard let food,
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let date = calendar.date(bySettingHour: hour, minute: 10, second: 0, of: day) else { return }
            context.insert(FoodEntry(food: food, amount: amount, meal: meal, date: date))
        }

        func quick(_ name: String, kcal: Double, protein: Double, carbs: Double, fat: Double) -> Food {
            Food(
                id: "manual:\(name)",
                name: name,
                source: .manual,
                unit: .serving,
                per: 1,
                nutrients: Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
            )
        }

        // Today, early afternoon: breakfast, lunch and a snack.
        log(skyr, 120, .breakfast, daysAgo: 0, at: 8)
        log(basic("Banana"), 118, .breakfast, daysAgo: 0, at: 8)
        log(basic("Coffee, black"), 240, .breakfast, daysAgo: 0, at: 8)
        log(estimate.food(imageData: ImageTools.jpeg(platePhoto(), maxSide: 600)), 1, .lunch, daysAgo: 0, at: 12)
        log(basic("Almonds"), 28, .snack, daysAgo: 0, at: 16)
        log(toblerone, 25, .snack, daysAgo: 0, at: 16)

        // Two weeks before today: yesterday and the day before on target (a streak), the
        // week before eating a little more, so Week shows moves.
        let days: [(breakfast: Double, lunch: Double, dinner: Double)] = [
            (breakfast: 1.0, lunch: 1.25, dinner: 1.1),
            (breakfast: 1.0, lunch: 1.3, dinner: 1.2),
            (breakfast: 1.1, lunch: 1.4, dinner: 1.4),
            (breakfast: 1.0, lunch: 0.9, dinner: 1.1),
            (breakfast: 1.2, lunch: 1.0, dinner: 1.0),
            (breakfast: 0.9, lunch: 0.8, dinner: 1.0),
            (breakfast: 1.0, lunch: 1.4, dinner: 1.3),
            (breakfast: 1.1, lunch: 1.3, dinner: 1.2),
            (breakfast: 1.0, lunch: 1.5, dinner: 1.3),
            (breakfast: 1.2, lunch: 1.2, dinner: 1.2),
            (breakfast: 1.0, lunch: 1.0, dinner: 1.1),
            (breakfast: 0.9, lunch: 1.3, dinner: 1.2),
            (breakfast: 1.0, lunch: 1.1, dinner: 1.0),
            (breakfast: 1.1, lunch: 1.2, dinner: 1.3),
        ]
        for (index, scale) in days.enumerated() {
            let daysAgo = index + 1
            log(basic("Oats"), 60 * scale.breakfast, .breakfast, daysAgo: daysAgo, at: 8)
            log(basic("Milk, semi-skimmed"), 200, .breakfast, daysAgo: daysAgo, at: 8)
            log(basic("Blueberries"), 80, .breakfast, daysAgo: daysAgo, at: 8)
            log(quick("Lunch out", kcal: 780 * scale.lunch, protein: 38, carbs: 85, fat: 30), 1, .lunch, daysAgo: daysAgo, at: 12)
            log(basic("Pasta, cooked"), 220 * scale.dinner, .dinner, daysAgo: daysAgo, at: 19)
            log(basic("Tomato sauce"), 132, .dinner, daysAgo: daysAgo, at: 19)
            log(basic("Parmesan"), 15, .dinner, daysAgo: daysAgo, at: 19)
            log(basic("Dark chocolate"), 20, .snack, daysAgo: daysAgo, at: 21)
        }
        // A shelf of foods you eat often, each looking the way you chose.
        let shake = Food(
            id: "saved:protein-shake",
            name: "Protein shake",
            emoji: "🥤",
            source: .manual,
            unit: .serving,
            per: 1,
            nutrients: Nutrients(kcal: 160, protein: 30, carbs: 6, fat: 2),
            tint: .sky
        )
        let shelf: [(Food?, Double, Meal?, String?)] = [
            (skyr, 120, .breakfast, "with honey"),
            (basic("Banana"), 118, nil, nil),
            (shake, 1, .snack, "after the gym"),
            (basic("Coffee, black"), 240, .breakfast, nil),
            (basic("Almonds"), 28, .snack, nil),
        ]
        for (index, item) in shelf.enumerated() {
            guard let food = item.0 else { continue }
            let saved = SavedFood(food: food, amount: item.1, sortIndex: index)
            saved.meal = item.2
            saved.subtitle = item.3
            if food.id == skyr.id { saved.name = "Morning skyr" }
            context.insert(saved)
        }
        try? context.save()
    }
}
#endif
