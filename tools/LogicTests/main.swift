// Logic tests for Bite's data layer. They run on Linux (no Xcode needed):
//     bash tools/check.sh
// They decode real Open Food Facts responses saved in fixtures/, load the bundled USDA basics,
// and check the math the screens rely on.
import Foundation

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtures = root.appendingPathComponent("tools/LogicTests/fixtures")

func product(_ code: String) throws -> OFFProductResponse {
    let data = try Data(contentsOf: fixtures.appendingPathComponent("product_\(code).json"))
    return try JSONDecoder().decode(OFFProductResponse.self, from: data)
}

// MARK: Open Food Facts products

do {
    let skyr = try product("3329770077003").product?.food(languages: ["fr", "en"])
    check(skyr != nil, "skyr decodes")
    if let skyr {
        check(skyr.name == "Skyr nature 0%", "skyr name is \(skyr.name)")
        check(skyr.brand == "Yoplait", "skyr brand is \(skyr.brand ?? "nil")")
        check(near(skyr.nutrients.kcal, 57), "skyr kcal \(skyr.nutrients.kcal)")
        check(near(skyr.nutrients.protein, 9.5), "skyr protein")
        check(skyr.nutriScore == "a", "skyr grade \(skyr.nutriScore ?? "nil")")
        check(skyr.novaGroup == 1, "skyr nova")
        check(skyr.unit == .gram, "skyr unit")
        check(skyr.portions.map(\.label) == ["100 g", "Whole pack"], "skyr portions \(skyr.portions)")
        check(skyr.defaultAmount == 100, "skyr default amount")
        check(skyr.highlights.map(\.title).contains("High protein"), "skyr is high protein: \(skyr.highlights)")
        check(skyr.imageURL?.absoluteString.hasPrefix("https://images.openfoodfacts.org/") == true, "skyr image")
        check(skyr.sourceURL?.absoluteString == "https://world.openfoodfacts.org/product/3329770077003", "skyr source url")
        check(near(skyr.nutrients(for: 150).kcal, 85.5), "150 g of skyr is 85.5 kcal")
    }

    let nutella = try product("3017620422003").product?.food(languages: ["en"])
    check(nutella != nil, "nutella decodes")
    if let nutella {
        check(nutella.brand == "Nutella", "nutella first brand is \(nutella.brand ?? "nil")")
        check(nutella.nutriScore == "e", "nutella grade \(nutella.nutriScore ?? "nil")")
        check(nutella.novaGroup == 4, "nutella nova")
        check(nutella.processingLabel?.title == "Ultra-processed", "nutella processing label")
        let titles = nutella.highlights.map(\.title)
        check(titles.contains("High sugar") && titles.contains("High saturated fat"), "nutella highlights \(titles)")
        check(nutella.allergens.contains("Milk") && nutella.allergens.contains("Nuts"), "nutella allergens \(nutella.allergens)")
        check(near(nutella.nutrients.kcal, 539), "nutella kcal")
    }

    let cola = try product("5449000000996").product?.food(languages: ["en"])
    check(cola != nil, "coca-cola decodes")
    if let cola {
        check(cola.unit == .milliliter, "cola is measured in ml")
        check(cola.portions.first == Portion(label: "1 portion", amount: 330), "cola serving \(cola.portions)")
        check(!cola.portions.contains { $0.label == "Whole pack" }, "a pack equal to the serving is not repeated")
        check(near(cola.nutrients(for: cola.defaultAmount).kcal, 139.92, 0.1), "one can of cola")
        check(cola.portionText(for: 330) == "1 portion · 330 ml", "cola portion text \(cola.portionText(for: 330))")
    }

    let ovo = try product("7612100018477").product?.food(languages: ["fr", "en"])
    check(ovo?.portions.map(\.label) == ["100 g", "Whole pack"], "ovomaltine portions \(ovo?.portions ?? [])")
    check(ovo?.portions.last?.amount == 360, "ovomaltine pack is 360 g")

    let danone = try product("3033491704642").product?.food(languages: ["fr", "en"])
    check(danone?.portions.first == Portion(label: "1 serving", amount: 120), "danone skyr serving \(danone?.portions ?? [])")
    check(danone?.portionText(for: 120) == "1 serving · 120 g", "danone portion text")

    let toblerone = try product("7614500010013").product?.food(languages: ["en"])
    check(toblerone?.allergens == ["Eggs", "Milk", "Nuts", "Soybeans"], "only canonical allergens: \(toblerone?.allergens ?? [])")
    check(toblerone?.portions.map(\.label) == ["1 serving", "100 g"], "a 100 g pack is not repeated: \(toblerone?.portions ?? [])")

    let missing = try product("0000000000017")
    check(missing.status != 1, "unknown barcode is not found")
} catch {
    failures += 1
    print("FAIL: product fixtures threw \(error)")
}

// MARK: Open Food Facts search

do {
    func hits(_ file: String) throws -> [OFFProduct] {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(file))
        return try JSONDecoder().decode(OFFSearchResponse.self, from: data).hits
    }

    let skyrHits = try hits("search_skyr.json")
    check(skyrHits.count == 50, "search returns 50 hits, got \(skyrHits.count)")
    check(skyrHits.contains { $0.uniqueScans != nil }, "scan counts decode")
    let skyr = OpenFoodFacts.rank(skyrHits, for: "skyr", languages: ["fr", "en"])
    check(skyr.count == 25, "ranked list is capped at 25, got \(skyr.count)")
    check(skyr.first?.brand == "Yoplait", "the most scanned skyr leads, got \(skyr.first.map { "\($0.name) by \($0.brand ?? "?")" } ?? "nil")")
    check(skyr.allSatisfy { $0.hasNutrition && $0.barcode != nil && !$0.name.isEmpty }, "every result has nutrition, a barcode and a name")

    let chocolate = OpenFoodFacts.rank(try hits("search_chocolat_noir.json"), for: "chocolat noir", languages: ["fr", "en"])
    let topChocolate = chocolate.prefix(5).map { "\($0.name) (\($0.brand ?? "?"))" }
    check(chocolate.prefix(5).allSatisfy { SearchText.matches(["chocolat", "noir"], in: SearchText.words(in: $0.name + " " + ($0.brand ?? ""))) }, "dark chocolate first, not Nutella: \(topChocolate)")
    check(chocolate.first?.brand == "Lindt", "most scanned dark chocolate leads: \(topChocolate)")
} catch {
    failures += 1
    print("FAIL: search fixture threw \(error)")
}

// MARK: Lenient decoding

do {
    let json = #"{"code": 761234, "product_name": " Biscuits ", "brands": ["Migros", "M-Classic"], "nova_group": "3", "serving_quantity": "12,5", "serving_size": "1 biscuit (12.5 g)", "nutriments": {"energy-kj_100g": "2092", "proteins_100g": 6, "fat_100g": null, "carbohydrates_100g": "70.1", "energy-kj_unit": "kJ"}}"#
    let raw = try JSONDecoder().decode(OFFProduct.self, from: Data(json.utf8))
    let food = raw.food(languages: ["fr"])
    check(food?.barcode == "761234", "numeric barcode becomes text")
    check(food?.name == "Biscuits", "names are trimmed")
    check(food?.brand == "Migros", "first brand of a list")
    check(food?.novaGroup == 3, "nova as string")
    check(near(food?.nutrients.kcal ?? 0, 500, 0.1), "kJ converts to kcal: \(food?.nutrients.kcal ?? 0)")
    check(near(food?.nutrients.carbs ?? 0, 70.1), "numeric strings decode")
    check(food?.portions.first == Portion(label: "1 biscuit", amount: 12.5), "comma decimal serving: \(food?.portions ?? [])")
    check(food?.hasNutrition == true, "kJ only still counts as nutrition")

    let empty = try JSONDecoder().decode(OFFProduct.self, from: Data(#"{"code": "123", "product_name": "Mystery"}"#.utf8))
    check(empty.food()?.hasNutrition == false, "a product without energy is flagged")
} catch {
    failures += 1
    print("FAIL: lenient decoding threw \(error)")
}

check(OFFProduct.servingLabel("30 g") == "1 serving", "bare quantity")
check(OFFProduct.servingLabel("100 gram") == "1 serving", "bare quantity in words")
check(OFFProduct.servingLabel(nil) == "1 serving", "no serving text")
check(OFFProduct.servingLabel("2 tranches (40 g)") == "2 tranches", "named serving")
check(OFFProduct.allergenName("en:soybeans") == "Soybeans", "allergen tag")
check(OpenFoodFacts.variants(of: "012345678905") == ["012345678905", "0012345678905"], "UPC-A gets its EAN-13 form")
check(OpenFoodFacts.variants(of: "0012345678905") == ["0012345678905", "012345678905"], "EAN-13 with a leading zero")

// MARK: Basics

let basicsURL = root.appendingPathComponent("Bite/Resources/basics.json")
let basics = BasicFoods.load(from: basicsURL, language: "en")
check(basics.count == 105, "105 basics, got \(basics.count)")
check(basics.allSatisfy { !$0.food.portions.isEmpty && $0.food.emoji != nil }, "every basic has a portion and an emoji")
check(Set(basics.map { $0.food.id }).count == basics.count, "basic ids are unique")

func firstMatch(_ query: String) -> String? { BasicFoods.search(query, in: basics).first?.name }
check(firstMatch("banana") == "Banana", "banana")
check(firstMatch("banane") == "Banana", "French: banane")
check(firstMatch("oeuf") == "Egg", "French: oeuf, got \(firstMatch("oeuf") ?? "nil")")
check(firstMatch("Œuf") == "Egg", "French: Œuf with ligature")
check(firstMatch("pâtes") == "Pasta, cooked", "French: pâtes, got \(firstMatch("pâtes") ?? "nil")")
check(firstMatch("riz") == "Rice, cooked", "French: riz finds cooked rice first, got \(firstMatch("riz") ?? "nil")")
check(firstMatch("lait") == "Milk, whole", "French: lait, got \(firstMatch("lait") ?? "nil")")
check(firstMatch("gruyere") == "Gruyère", "accent folding")
check(firstMatch("chick") == "Chickpeas, cooked" || firstMatch("chick")?.hasPrefix("Chicken") == true, "prefix search")
check(BasicFoods.search("chicken breast", in: basics).first?.name == "Chicken breast, cooked", "two words")
check(BasicFoods.search("zzz", in: basics).isEmpty, "no match")
check(BasicFoods.search("  ", in: basics).isEmpty, "blank query")

if let banana = basics.first(where: { $0.food.name == "Banana" })?.food {
    check(banana.portionText(for: 118) == "1 medium · 118 g", "banana portion text: \(banana.portionText(for: 118))")
    check(banana.portionText(for: 100) == "100 g", "unnamed amount")
    check(near(banana.nutrients(for: 118).kcal, 105.02), "one banana is 105 kcal")
    check(banana.sourceURL?.absoluteString == "https://fdc.nal.usda.gov/food-details/173944/nutrients", "usda link")
}
if let broccoli = basics.first(where: { $0.food.name == "Broccoli" })?.food {
    check(broccoli.highlights.map(\.title).contains("Low calorie"), "broccoli is low calorie: \(broccoli.highlights)")
    check(!broccoli.highlights.map(\.title).contains("High protein"), "broccoli is not sold as high protein")
}
if let chicken = basics.first(where: { $0.food.name == "Chicken breast, cooked" })?.food {
    check(chicken.highlights.first?.title == "High protein", "chicken is high protein")
}
if let milk = basics.first(where: { $0.food.name == "Milk, whole" })?.food {
    check(milk.unit == .milliliter, "milk is in ml")
    check(milk.portionText(for: 250) == "1 glass · 250 ml", "milk glass")
}

// The same basics in French and Spanish: their own names and portions, found in any language.
let basicsFR = BasicFoods.load(from: basicsURL, language: "fr")
let basicsES = BasicFoods.load(from: basicsURL, language: "es")
check(basicsFR.map(\.key) == basics.map(\.key) && basicsES.map(\.key) == basics.map(\.key), "the English key is the same in every language")
check(basics.allSatisfy { $0.key == $0.food.name }, "in English the name is the key")
check(basicsFR.first { $0.key == "Banana" }?.food.name == "Banane", "French name")
check(basicsFR.first { $0.key == "Banana" }?.food.portions.first?.label == "1 moyenne", "French portion agrees with banane")
check(basicsFR.first { $0.key == "Egg" }?.food.portions.first?.label == "1 gros", "French portion agrees with œuf")
check(basicsES.first { $0.key == "Coffee, black" }?.food.name == "Café solo", "Spanish name")
check(basicsES.first { $0.key == "Ham" }?.food.portions.first?.label == "1 loncha", "Spanish slice of ham")
check(basicsFR.allSatisfy { $0.food.portions.allSatisfy { !$0.label.isEmpty } }, "every French portion has a label")
check(BasicFoods.search("platano", in: basicsES).first?.name == "Plátano", "Spanish search folds accents")
check(BasicFoods.search("banana", in: basicsES).first?.name == "Plátano", "English still finds it in Spanish")
check(BasicFoods.search("zumo", in: basicsES).first?.name == "Zumo de naranja", "Spanish juice")
check(BasicFoods.search("banane", in: basicsFR).first?.name == "Banane", "French search")
check(tr("%@ kcal over", "300") == "300 kcal over", "tr fills its value; Linux has no catalog, so English comes back")

// MARK: Units, meals, goals

check(FoodUnit.gram.format(150) == "150 g", "grams")
check(FoodUnit.gram.format(8.1) == "8.1 g", "one decimal")
check(FoodUnit.serving.format(1) == "1 serving", "one serving")
check(FoodUnit.serving.format(1.5) == "1.5 servings", "servings")

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: hour, minute: minute))!
}
check(Meal.likely(at: at(8), calendar: calendar) == .breakfast, "8:00 is breakfast")
check(Meal.likely(at: at(12, 30), calendar: calendar) == .lunch, "12:30 is lunch")
check(Meal.likely(at: at(16, 30), calendar: calendar) == .snack, "16:30 is a snack")
check(Meal.likely(at: at(19), calendar: calendar) == .dinner, "19:00 is dinner")
check(Meal.likely(at: at(23), calendar: calendar) == .snack, "23:00 is a snack")

let kcal = GoalCalculator.dailyCalories(sex: .female, age: 30, heightCm: 170, weightKg: 70, activity: .light, goal: .maintain)
check(kcal == 2000, "Mifflin-St Jeor example gives 2000, got \(kcal)")
let cut = GoalCalculator.dailyCalories(sex: .male, age: 35, heightCm: 180, weightKg: 82, activity: .moderate, goal: .lose)
check(cut == 2250, "male cut example gives 2250, got \(cut)")
let floor = GoalCalculator.dailyCalories(sex: .female, age: 80, heightCm: 145, weightKg: 40, activity: .sedentary, goal: .lose)
check(floor == 1200, "never below the safe floor, got \(floor)")

let targets = MacroTargets(kcal: 2000, split: .balanced)
check(targets == MacroTargets(kcal: 2000, split: .balanced) && targets.protein == 125 && targets.carbs == 225 && targets.fat == 67, "balanced 2000 kcal: \(targets)")

let day = Nutrients(kcal: 100, protein: 10, carbs: 5, fat: 2, sugar: 1) + Nutrients(kcal: 50, protein: 1, carbs: 10, fat: 0)
check(day.kcal == 150 && day.protein == 11 && day.sugar == 1 && day.fiber == nil, "adding nutrients keeps unknowns unknown")
let split = Nutrients(kcal: 0, protein: 10, carbs: 10, fat: 0).energySplit
check(near(split.protein, 0.5) && near(split.carbs, 0.5) && split.fat == 0, "energy split")

// MARK: Insights: verdicts, scores, streaks, ranks

let goal = 2000.0
func summary(_ daysAgo: Int, kcal: Double, protein: Double = 100, entries: Int = 4, quality: Double? = nil) -> DaySummary {
    let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: at(12)))!
    return DaySummary(day: date, kcal: kcal, protein: protein, entries: entries, quality: quality)
}
check(DayVerdict(kcal: 0, entries: 0, goal: goal) == .empty, "nothing logged is empty")
check(DayVerdict(kcal: 1700, entries: 3, goal: goal) == .light, "under 90% is a light day")
check(DayVerdict(kcal: 1900, entries: 3, goal: goal) == .onTarget, "90% is on target")
check(DayVerdict(kcal: 2100, entries: 3, goal: goal) == .onTarget, "105% is still on target")
check(DayVerdict(kcal: 2300, entries: 3, goal: goal) == .over(kcal: 300), "over by 300")
check(DayVerdict.over(kcal: 300).label == "300 kcal over", "plain over label: \(DayVerdict.over(kcal: 300).label ?? "nil")")
check(DayVerdict.onTarget.label == "On target" && DayVerdict.light.label == "Light day" && DayVerdict.empty.label == nil, "verdict labels carry no emoji")

check(Insights.score(summary(0, kcal: 2000, protein: 125, quality: 1), goal: goal, proteinTarget: 125) == 100, "perfect day is 100")
check(Insights.score(summary(0, kcal: 2400, protein: 125, quality: 1), goal: goal, proteinTarget: 125) == 70, "20% over costs half the calorie points")
check(Insights.score(summary(0, kcal: 2000, protein: 62.5), goal: goal, proteinTarget: 125) == 82, "60 + 12.5 + 9 = 81.5 rounds to 82")
check(Insights.score(summary(0, kcal: 0, entries: 0), goal: goal, proteinTarget: 125) == 0, "empty day scores 0")
check(Insights.qualityPoints(grade: "A") == 1 && Insights.qualityPoints(grade: "e") == 0.1 && Insights.qualityPoints(grade: nil) == nil, "Nutri-Score points")

let week = [summary(0, kcal: 900), summary(1, kcal: 2000), summary(2, kcal: 1950), summary(3, kcal: 2050), summary(4, kcal: 1500), summary(5, kcal: 2000)]
check(Insights.streak(week, goal: goal, today: at(12), calendar: calendar) == 6, "light and over days keep a streak going")
check(Insights.streak(Array(week.dropFirst()), goal: goal, today: at(12), calendar: calendar) == 5, "nothing logged yet today does not break it")
check(Insights.streak([summary(0, kcal: 2000), summary(1, kcal: 2400), summary(3, kcal: 2000)], goal: goal, today: at(12), calendar: calendar) == 2, "a day with nothing logged ends it")
let best = Insights.bestDays(week, goal: goal, proteinTarget: 125)
check(best.count == 3 && best[0].day.kcal == 2000 && best[0].day.day > best[1].day.day, "best days: highest score, newest first on ties")

let thisWeek = Insights.period(week, goal: goal)
check(thisWeek.loggedDays == 6 && thisWeek.daysOnTarget == 4, "period counts: \(thisWeek)")
check(near(thisWeek.averageKcal, 1733.33, 0.01), "period average kcal")
check(near(Insights.change(from: 2000, to: 1800) ?? 0, -0.1), "change is a fraction")
check(Insights.change(from: 0, to: 1800) == nil, "no change without a baseline")

let topFoods = Insights.topFoods([
    (foodID: "a", name: "Skyr", kcal: 68), (foodID: "b", name: "Banana", kcal: 105),
    (foodID: "a", name: "Skyr", kcal: 68), (foodID: "c", name: "Coffee", kcal: 2), (foodID: "b", name: "Banana", kcal: 105),
    (foodID: "a", name: "Skyr", kcal: 68),
])
check(topFoods.map(\.name) == ["Skyr", "Banana", "Coffee"] && topFoods[0].times == 3, "most eaten first: \(topFoods)")

// MARK: Tints and safe numbers

check(FoodTint.suggested(for: "🍌") == .peach && FoodTint.suggested(for: "🥦") == .mint && FoodTint.suggested(for: "🍫") == .lilac, "tints follow the food")
check(FoodTint.suggested(for: nil) == .sand && FoodTint.suggested(for: "🚗") == .sand, "unknown emoji gets sand")
let untinted = basics.filter { FoodTint.suggested(for: $0.food.emoji) == .sand }.compactMap { $0.food.emoji }
check(Set(untinted).isSubset(of: ["🌰", "🥜", "🌱", "🫘"]), "only nuts, seeds and beans stay sand: \(Set(untinted))")
check(Double.nan.safeInt == 0 && Double.infinity.safeInt == 0 && (1e300).safeInt == 0 && (12.6).safeInt == 13, "safeInt never traps")
check(Double.nan.kcalText == "0", "NaN shows as 0")

// MARK: Claude photo estimate

do {
    let data = try Data(contentsOf: fixtures.appendingPathComponent("claude_meal.json"))
    let estimate = try ClaudeVision.parse(data)
    check(estimate.title == "Poulet riz brocoli" && estimate.confidence == .medium, "estimate header decodes")
    check(estimate.items.count == 3, "impossible items are dropped, got \(estimate.items.count)")
    check(near(estimate.totals.kcal, 509) && near(estimate.totals.protein, 53.6), "totals add up: \(estimate.totals)")
    let more = estimate.items[1].with(grams: 270)
    check(near(more.kcal, 351) && near(more.carbs, 76.05), "changing grams scales nutrition")
    let plate = estimate.food(imageData: Data([1, 2, 3]))
    check(plate.source == .ai && plate.unit == .serving && near(plate.nutrients.kcal, 509) && plate.imageData == Data([1, 2, 3]), "the plate becomes one food")
} catch {
    failures += 1
    print("FAIL: estimate fixture threw \(error)")
}

do {
    let data = try Data(contentsOf: fixtures.appendingPathComponent("claude_refusal.json"))
    _ = try ClaudeVision.parse(data)
    check(false, "a refusal should throw")
} catch let failure as ClaudeVision.Failure {
    check(failure == .declined, "refusal maps to declined")
} catch {
    check(false, "unexpected error \(error)")
}

do {
    let request = try ClaudeVision.request(jpeg: Data([0xFF, 0xD8, 0xFF]), language: "fr", apiKey: "test-key")
    check(request.value(forHTTPHeaderField: "x-api-key") == "test-key", "api key header")
    check(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01", "version header")
    check(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01", "fallback beta header")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
    check(body["model"] as? String == "claude-opus-5-5", "model")
    check(body["fallbacks"] as? String == "default", "fallbacks default")
    let config = body["output_config"] as? [String: Any]
    let format = config?["format"] as? [String: Any]
    check(format?["type"] as? String == "json_schema" && config?["effort"] as? String == "medium", "structured output and effort")
    let messages = body["messages"] as? [[String: Any]]
    let content = messages?.first?["content"] as? [[String: Any]]
    let source = content?.first?["source"] as? [String: Any]
    check(source?["data"] as? String == "/9j/", "photo travels as base64 JPEG")
    check((content?.last?["text"] as? String)?.contains("language: fr") == true, "prompt carries the language")
    let schema = format?["schema"] as? [String: Any]
    check(schema?["additionalProperties"] as? Bool == false, "schema closes objects")
} catch {
    failures += 1
    print("FAIL: request threw \(error)")
}

// MARK: Community estimates

do {
    // El Beirout's chicken shawarma: three close counts, one that 23 people agree with.
    let shawarma = Consensus([
        .init(kcal: 590, protein: 37, carbs: 54, fat: 24, agrees: 23),
        .init(kcal: 640, protein: 40, carbs: 58, fat: 26, agrees: 4),
        .init(kcal: 570, protein: 35, carbs: 52, fat: 23, agrees: 1),
    ])
    check(near(shawarma.nutrients.kcal, 596.77, 0.05), "agreed counts weigh more: \(shawarma.nutrients.kcal)")
    check(shawarma.accuracy == 97, "three close counts and 28 agreements are 97, got \(shawarma.accuracy)")
    check(shawarma.tier == .veryAccurate, "97 is very accurate")
    check(shawarma.spreadPercent == 2, "within 2%, got \(shawarma.spreadPercent)")
    check(shawarma.estimates == 3 && shawarma.agrees == 28, "counts and agreements")
    check(near(shawarma.nutrients.protein, 37.32, 0.05), "protein is weighted too: \(shawarma.nutrients.protein)")

    // Two close counts but few people behind them: roughly right.
    let plate = Consensus([
        .init(kcal: 1240, protein: 52, carbs: 120, fat: 62, agrees: 3),
        .init(kcal: 1180, protein: 50, carbs: 112, fat: 60, agrees: 1),
    ])
    check(near(plate.nutrients.kcal, 1220), "plate average \(plate.nutrients.kcal)")
    check(plate.accuracy == 62 && plate.tier == .rough, "few people behind two counts: \(plate.accuracy)")

    // One count alone is never sure, however exact it may be.
    let lone = Consensus([.init(kcal: 430, protein: 14, carbs: 38, fat: 24, agrees: 0)])
    check(lone.accuracy == 15 && lone.tier == .needsMore, "one count is 15, got \(lone.accuracy)")
    check(lone.spreadPercent == 1, "a single count reads within 1%")

    let none = Consensus([])
    check(none.accuracy == 0 && none.nutrients == .zero && none.estimates == 0, "no counts, no numbers")

    // Far apart counts stay rough even with many agreements.
    let apart = Consensus([
        .init(kcal: 400, protein: 0, carbs: 0, fat: 0, agrees: 10),
        .init(kcal: 800, protein: 0, carbs: 0, fat: 0, agrees: 10),
    ])
    check(apart.accuracy < 70, "a 2x disagreement is not accurate: \(apart.accuracy)")
}

// MARK: Places

do {
    let beirout = MealPlace(name: "El Beirout", area: "Parc de Milan", latitude: 46.51492, longitude: 6.62268, category: .restaurant)
    check(beirout.line == "El Beirout · Parc de Milan", "place line \(beirout.line)")
    check(MealPlace(name: "Home").line == "Home", "a place without an area")
    check(MealPlace(name: "Café", area: "Café").line == "Café", "an area that repeats the name is dropped")
    check(beirout.key == MealPlace(name: "el beirout", area: "PARC DE MILAN").key, "same place whatever the case")
    let walk = beirout.distance(fromLatitude: 46.51475, longitude: 6.62230) ?? -1
    check(walk > 30 && walk < 40, "a few steps from the park: \(walk) m")
    let geneva = MealPlace.meters(fromLatitude: 46.5197, longitude: 6.6323, toLatitude: 46.2044, longitude: 6.1432)
    check(geneva > 49_000 && geneva < 53_000, "Lausanne to Geneva is about 51 km: \(geneva)")
    check(MealPlace(name: "Somewhere").distance(fromLatitude: 0, longitude: 0) == nil, "no coordinates, no distance")
    let coded = try? JSONEncoder().encode(beirout)
    check(coded.flatMap { try? JSONDecoder().decode(MealPlace.self, from: $0) } == beirout, "a place survives coding")
}

// MARK: Weight forecast

do {
    // 32, 180 cm, 72.6 kg, training 3 to 5 days: about 2,630 kcal a day.
    let burn = GoalCalculator.maintenance(sex: .male, age: 32, heightCm: 180, weightKg: 72.6, activity: .moderate)
    check(near(burn, 2628.8, 0.1), "maintenance \(burn)")
    // The calculator's daily goal is the same body minus 500 for losing, rounded.
    let goal = GoalCalculator.dailyCalories(sex: .male, age: 32, heightCm: 180, weightKg: 72.6, activity: .moderate, goal: .lose)
    check(abs(Double(goal) - (burn - 500)) <= 5, "goal is maintenance minus 500: \(goal)")

    let week: [Double] = [1954, 2038, 2242, 1681, 1789, 1522, 2160]
    let forecast = WeightForecast.make(currentKg: 72.6, maintenance: burn, dayKcals: week)
    check(forecast != nil, "a week of whole days makes a forecast")
    if let forecast {
        check(forecast.days == 7, "seven days count")
        check(near(forecast.dailyBalance, 1912.29 - burn, 0.1), "balance \(forecast.dailyBalance)")
        check(forecast.direction == .losing, "a deficit is losing")
        check(near(forecast.perWeek, -0.6515, 0.001), "about 0.65 kg a week, got \(forecast.perWeek)")
        check(near(forecast.weight(afterDays: 28), 72.6 - 2.606, 0.01), "four weeks on: \(forecast.weight(afterDays: 28))")
    }

    // Forgotten days (a coffee and nothing else) never pull the average down.
    let patchy = WeightForecast.make(currentKg: 70, maintenance: 2000, dayKcals: [2000, 150, 2000, 0, 2000])
    check(patchy?.days == 3 && near(patchy?.dailyBalance ?? -1, 0), "only whole days count")
    check(patchy?.direction == .holding, "eating what you burn holds")
    check(WeightForecast.make(currentKg: 70, maintenance: 2000, dayKcals: [2100, 1900]) == nil, "two days are not enough")
    check(WeightForecast.make(currentKg: 70, maintenance: 2000, dayKcals: [2300, 2300, 2300])?.direction == .gaining, "a surplus is gaining")
    let smooth = WeightForecast.trend([73.0, 74.2, 73.0, 72.8])
    check(near(smooth[1], 73.3) && smooth.count == 4, "one heavy morning moves the trend a quarter: \(smooth)")
    check(smooth.last! > 72.8 && smooth.last! < 73.3, "the trend sits between the noise: \(smooth.last!)")
    check(WeightForecast.trend([]).isEmpty && WeightForecast.trend([70]) == [70], "trend of nothing and of one")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
