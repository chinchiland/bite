#if DEBUG || BITE_DEMO
import Foundation
import SwiftData
import UIKit

/// A believable two weeks of logs for previews, screenshots and Bite Demo. Launch a Debug build
/// with `-demo`, or open Bite Demo, to use it; it lives in memory and never touches your real
/// log. The plate photos are from Unsplash, the two shawarmas are public domain (CC0), and they
/// ship in Debug builds and Bite Demo only. Today is a lunch at El Beirout by the Parc de Milan
/// in Lausanne, where people have counted a few dishes.
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
        title: tr("Salmon salad bowl"),
        emoji: "🥗",
        confidence: .medium,
        note: tr("The dressing could add 50 kcal if it was poured generously."),
        items: [
            MealEstimate.Item(name: tr("Salmon"), emoji: "🐟", grams: 120, kcal: 250, protein: 25.2, carbs: 0, fat: 16.2),
            MealEstimate.Item(name: tr("Egg"), emoji: "🥚", grams: 50, kcal: 72, protein: 6.3, carbs: 0.4, fat: 4.8),
            MealEstimate.Item(name: tr("Sweet corn"), emoji: "🌽", grams: 60, kcal: 52, protein: 1.6, carbs: 11.2, fat: 0.7),
            MealEstimate.Item(name: tr("Edamame"), emoji: "🫛", grams: 50, kcal: 61, protein: 5.5, carbs: 4.5, fat: 2.6),
            MealEstimate.Item(name: tr("Greens"), emoji: "🥬", grams: 150, kcal: 38, protein: 2, carbs: 7.2, fat: 0.3),
            MealEstimate.Item(name: tr("Sesame dressing"), emoji: "🫙", grams: 20, kcal: 90, protein: 0.6, carbs: 3, fat: 8.4),
        ],
        doubt: MealEstimate.Doubt(
            question: tr("How much dressing was on it?"),
            item: 5,
            answers: [
                .init(label: tr("No dressing"), grams: 0),
                .init(label: tr("A drizzle"), grams: 20),
                .init(label: tr("Poured on"), grams: 45),
            ]
        )
    )

    /// A bundled plate photo, as JPEG data.
    static func photo(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: "demo-\(name)", withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The salmon bowl as a camera would hand it over, for the photo estimate screenshots.
    static func plateImage() -> UIImage {
        photo("salmon-bowl").flatMap(UIImage.init(data:)) ?? platePhoto()
    }

    /// The salmon bowl, decoded once: the photo behind every demo estimate, so the demo never
    /// shows your plate under the bowl's numbers.
    static let estimatePhoto = plateImage()

    /// A stand-in plate photo drawn in code, for when the bundled photos are missing.
    static func platePhoto(size: CGSize = CGSize(width: 900, height: 900)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.84, green: 0.80, blue: 0.74, alpha: 1).setFill()
            context.fill(rect)
            let plate = rect.insetBy(dx: size.width * 0.08, dy: size.height * 0.08)
            UIColor(white: 0.97, alpha: 1).setFill()
            UIBezierPath(ovalIn: plate).fill()
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
        let container = try! ModelContainer(
            for: FoodEntry.self, SavedFood.self, WaterDay.self, CommunityDish.self, DishEstimate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        MainActor.assumeIsolated { seed(container.mainContext) }
        return container
    }

    /// Thirty days of weighings, a slow drift down, for the week strip.
    static func weights() -> [WeightPoint] {
        let values: [Double] = [73.4, 73.3, 73.5, 73.2, 73.1, 73.2, 73.0, 72.9, 73.0, 72.8, 72.9, 72.7, 72.8, 72.6, 72.6]
        return values.enumerated().compactMap { index, kilograms in
            Calendar.current.date(byAdding: .day, value: -(28 - index * 2), to: .now).map {
                WeightPoint(date: $0, kilograms: kilograms)
            }
        }
    }

    /// Dishes at El Beirout with the estimates people made: Claude reading their plate or
    /// typed by hand, and how many agree. Returns the chicken shawarma.
    @discardableResult
    @MainActor static func seedCommunity(_ context: ModelContext) -> CommunityDish? {
        let place = MealPlace(name: "El Beirout", area: "Parc de Milan", latitude: 46.51492, longitude: 6.62268, category: .restaurant)
        typealias Count = (author: String, source: EstimateSource, nutrients: Nutrients, agrees: Int, tint: FoodTint)

        @discardableResult
        func dish(_ name: String, emoji: String, photo key: String?, stars: Double, ratings: Int, _ counts: [Count]) -> CommunityDish {
            let item = CommunityDish(name: name, emoji: emoji, photo: key.flatMap { photo($0) }, place: place)
            item.ratingSum = stars * Double(ratings)
            item.ratingCount = ratings
            context.insert(item)
            for count in counts {
                let estimate = DishEstimate(author: count.author, source: count.source, nutrients: count.nutrients, agrees: count.agrees, tint: count.tint)
                context.insert(estimate)
                item.estimates.append(estimate)
            }
            return item
        }

        let shawarma = dish(tr("Chicken shawarma"), emoji: "🌯", photo: "shawarma", stars: 4.6, ratings: 26, [
            ("Tom R.", .ai, Nutrients(kcal: 590, protein: 37, carbs: 54, fat: 24), 23, .sky),
            ("Léa M.", .entered, Nutrients(kcal: 640, protein: 40, carbs: 58, fat: 26), 4, .peach),
            ("Sara K.", .ai, Nutrients(kcal: 570, protein: 35, carbs: 52, fat: 23), 1, .mint),
        ])
        dish(tr("Shawarma plate, fries"), emoji: "🍟", photo: "shawarma-fries", stars: 4.4, ratings: 12, [
            ("Tom R.", .ai, Nutrients(kcal: 1240, protein: 52, carbs: 120, fat: 62), 3, .sky),
            ("Léa M.", .entered, Nutrients(kcal: 1180, protein: 50, carbs: 112, fat: 60), 1, .peach),
        ])
        dish(tr("Falafel wrap"), emoji: "🧆", photo: nil, stars: 4.5, ratings: 9, [
            ("Sara K.", .entered, Nutrients(kcal: 520, protein: 16, carbs: 62, fat: 22), 6, .mint),
            ("Marc D.", .ai, Nutrients(kcal: 545, protein: 17, carbs: 64, fat: 24), 2, .butter),
        ])
        dish(tr("Hummus plate"), emoji: "🫓", photo: nil, stars: 4.2, ratings: 5, [
            ("Tom R.", .ai, Nutrients(kcal: 430, protein: 14, carbs: 38, fat: 24), 0, .sky),
        ])
        return shawarma
    }

    /// A plate Claude estimated, with its photo: one serving.
    private static func plate(_ key: String, _ name: String, emoji: String, kcal: Double, protein: Double, carbs: Double, fat: Double) -> Food {
        Food(
            id: "demo:\(key)",
            name: name,
            emoji: emoji,
            source: .ai,
            unit: .serving,
            per: 1,
            nutrients: Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: (carbs * 1.2).rounded() / 10),
            imageData: photo(key)
        )
    }

    @MainActor static func seed(_ context: ModelContext) {
        // A body for the goal and the weight forecast: someone losing a little, training a few
        // times a week.
        let defaults = UserDefaults.standard
        defaults.set(Sex.male.rawValue, forKey: "body.sex")
        defaults.set(32, forKey: "body.age")
        defaults.set(180, forKey: "body.height")
        defaults.set(72.6, forKey: "body.weight")
        defaults.set(Activity.moderate.rawValue, forKey: "body.activity")
        defaults.set(WeightGoal.lose.rawValue, forKey: "body.goal")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func basic(_ name: String) -> Food? {
            BasicFoods.index.first { $0.key == name }?.food
        }

        func log(_ food: Food?, _ amount: Double, _ meal: Meal, daysAgo: Int, at hour: Int, _ minute: Int, place: MealPlace? = nil) {
            guard let food,
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return }
            context.insert(FoodEntry(food: food, amount: amount, meal: meal, date: date, place: place))
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

        let saladBowl = estimate.food(imageData: photo("salmon-bowl") ?? ImageTools.jpeg(platePhoto(), maxSide: 600))
        let buddha = plate("buddha-bowl", tr("Buddha bowl"), emoji: "🥗", kcal: 620, protein: 22, carbs: 70, fat: 26)
        let steak = plate("steak", tr("Steak and greens"), emoji: "🥩", kcal: 690, protein: 45, carbs: 30, fat: 40)
        let salmonPlate = plate("salmon-plate", tr("Salmon with vegetables"), emoji: "🐟", kcal: 640, protein: 38, carbs: 28, fat: 38)
        let eggBowl = plate("egg-bowl", tr("Eggs and greens"), emoji: "🍳", kcal: 420, protein: 24, carbs: 18, fat: 27)
        let pizza = plate("pizza", tr("Pizza"), emoji: "🍕", kcal: 780, protein: 30, carbs: 92, fat: 30)
        let lunchOut = quick(tr("Lunch out"), kcal: 780, protein: 38, carbs: 85, fat: 30)

        // The dishes people counted at El Beirout; today's lunch is the first of them.
        let shawarma = seedCommunity(context)

        // Today, mid afternoon: eggs at home, a shawarma at El Beirout (the cover, with the
        // breakfast photo behind it), a skyr and almonds.
        log(eggBowl, 1, .breakfast, daysAgo: 0, at: 8, 10)
        log(basic("Coffee, black"), 240, .breakfast, daysAgo: 0, at: 8, 10)
        log(shawarma?.food, 1, .lunch, daysAgo: 0, at: 12, 40, place: shawarma?.place)
        log(skyr, 120, .snack, daysAgo: 0, at: 16, 10)
        log(basic("Almonds"), 28, .snack, daysAgo: 0, at: 16, 10)
        context.insert(WaterDay(day: today, glasses: 5))

        // Two weeks before today, each day landing where `scale` puts it: yesterday and the day
        // before on target (a streak), the week before eating a little more, so Week shows moves.
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
            let target = 370 * scale.breakfast + 780 * scale.lunch + 445 * scale.dinner + 120

            let breakfast: [(Food?, Double)] = switch index % 4 {
            case 0: [(basic("Oats"), 60 * scale.breakfast), (basic("Milk, semi-skimmed"), 200), (basic("Blueberries"), 80)]
            case 1: [(skyr, 150), (basic("Banana"), 118), (basic("Granola"), 30 * scale.breakfast)]
            case 2: [(eggBowl, scale.breakfast * 0.9)]
            default: [(basic("Croissant"), 60), (basic("Coffee, black"), 240), (basic("Orange juice"), 200 * scale.breakfast)]
            }
            let lunch: [(Food?, Double)] = switch index % 5 {
            case 0: [(buddha, 1)]
            case 1: [(steak, 1)]
            case 2: [(lunchOut, 1)]
            case 3: [(saladBowl, 1)]
            default: [(salmonPlate, 1)]
            }
            let dinner: [(Food?, Double)] = switch index % 3 {
            case 0: [(basic("Pasta, cooked"), 220), (basic("Tomato sauce"), 132), (basic("Parmesan"), 15)]
            case 1: [(pizza, 1)]
            default: [(basic("Chicken breast, cooked"), 150), (basic("Rice, cooked"), 180), (basic("Broccoli"), 120)]
            }
            let snack: [(Food?, Double)] = index % 2 == 0 ? [(basic("Dark chocolate"), 20)] : [(basic("Almonds"), 28)]

            // Lunch and dinner stretch or shrink so the day lands on its target.
            func kcal(_ items: [(Food?, Double)]) -> Double {
                items.reduce(0) { $0 + ($1.0?.nutrients(for: $1.1).kcal ?? 0) }
            }
            let fixed = kcal(breakfast) + kcal(snack)
            let flexible = kcal(lunch) + kcal(dinner)
            let factor = flexible > 0 ? min(max((target - fixed) / flexible, 0.5), 2) : 1

            for item in breakfast { log(item.0, item.1, .breakfast, daysAgo: daysAgo, at: 8, 5) }
            for item in lunch { log(item.0, item.1 * factor, .lunch, daysAgo: daysAgo, at: 12, 50) }
            for item in dinner { log(item.0, item.1 * factor, .dinner, daysAgo: daysAgo, at: 19, 40) }
            for item in snack { log(item.0, item.1, .snack, daysAgo: daysAgo, at: 21, 15) }
        }

        // A shelf of foods you eat often, each looking the way you chose.
        let shake = Food(
            id: "saved:protein-shake",
            name: tr("Protein shake"),
            emoji: "🥤",
            source: .manual,
            unit: .serving,
            per: 1,
            nutrients: Nutrients(kcal: 160, protein: 30, carbs: 6, fat: 2),
            tint: .sky
        )
        let shelf: [(Food?, Double, Meal?, String?)] = [
            (skyr, 120, .breakfast, tr("with honey")),
            (basic("Banana"), 118, nil, nil),
            (shake, 1, .snack, tr("after the gym")),
            (buddha, 1, .lunch, nil),
            (basic("Coffee, black"), 240, .breakfast, nil),
            (basic("Almonds"), 28, .snack, nil),
        ]
        for (index, item) in shelf.enumerated() {
            guard let food = item.0 else { continue }
            let saved = SavedFood(food: food, amount: item.1, sortIndex: index)
            saved.meal = item.2
            saved.subtitle = item.3
            if food.id == skyr.id { saved.name = tr("Morning skyr") }
            context.insert(saved)
        }
        try? context.save()
        #if BITE_DEMO
        seededDay = today
        #endif
    }

    #if BITE_DEMO
    /// The day Bite Demo's story was written around.
    @MainActor private static var seededDay: Date?

    /// Back on a new day, the same story moved to it: every meal and glass of water shifts by
    /// the days that passed, so nothing a screen still shows is deleted under it.
    @MainActor static func moveToToday(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let seededDay, let days = calendar.dateComponents([.day], from: seededDay, to: today).day, days > 0 else { return }
        for entry in (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [] {
            entry.date = calendar.date(byAdding: .day, value: days, to: entry.date) ?? entry.date
        }
        for water in (try? context.fetch(FetchDescriptor<WaterDay>())) ?? [] {
            water.day = calendar.date(byAdding: .day, value: days, to: water.day) ?? water.day
        }
        try? context.save()
        self.seededDay = today
    }
    #endif
}
#endif
