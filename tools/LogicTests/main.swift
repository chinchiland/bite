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
check(firstMatch("bananna") == "Banana", "a doubled letter: \(firstMatch("bananna") ?? "nil")")
check(firstMatch("brocolli") == "Broccoli", "a doubled l: \(firstMatch("brocolli") ?? "nil")")
check(firstMatch("tomatoe") == "Tomato", "an extra letter at the end")
check(firstMatch("chiken")?.hasPrefix("Chicken") == true, "chiken: \(firstMatch("chiken") ?? "nil")")
check(firstMatch("yougurt")?.contains("yogurt") == true, "an extra letter: \(firstMatch("yougurt") ?? "nil")")
check(firstMatch("avocaod") == "Avocado", "two letters swapped")
check(BasicFoods.search("chiken brest", in: basics).first?.name == "Chicken breast, cooked", "a slip in each word")
check(!BasicFoods.search("beer", in: basics).contains { $0.name.hasPrefix("Beef") || $0.name.hasPrefix("Ground beef") }, "a word found as typed never pulls in near ones")
check(BasicFoods.search("vhicken", in: basics).isEmpty, "the first letter has to be right")
check(BasicFoods.search("rix", in: basics).isEmpty, "three letters stay exact")
check(firstMatch("rice") == "Rice, cooked" && firstMatch("milk") == "Milk, whole", "the list's own order settles a tie: \(firstMatch("rice") ?? "nil"), \(firstMatch("milk") ?? "nil")")
check(firstMatch("chicken") == "Chicken breast, cooked", "breast before thigh")
check(BasicFoods.search("rixe", in: basics).first?.name == "Rice, cooked", "rixe finds rice: \(BasicFoods.search("rixe", in: basics).first?.name ?? "nil")")
check(SearchText.withinOneEdit(Array("abcd"), Array("abdc")) && SearchText.withinOneEdit(Array("abc"), Array("abc")), "swap and same")
check(!SearchText.withinOneEdit(Array("abcd"), Array("badc")) && !SearchText.withinOneEdit(Array("ab"), Array("abcd")), "two edits are too many")
check(SearchText.withinOneEdit(Array(""), Array("a")) && SearchText.withinOneEdit(Array("abc"), Array("xbc")), "edges")
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

// Your usual meal: the same foods at the same meal on three days of the last two weeks,
// offered from an hour before its time to two hours after, while that meal is still empty.
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
    func on(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(byAdding: DateComponents(day: -daysAgo, hour: hour, minute: minute), to: today)!
    }
    func dinner(_ daysAgo: Int, _ foods: [String], at hour: Int = 19, _ minute: Int = 40) -> [UsualMeal.Logged] {
        foods.map { UsualMeal.Logged(date: on(daysAgo, hour, minute), meal: .dinner, foodID: $0) }
    }
    let pasta = ["pasta", "sauce", "parmesan"]
    var log = dinner(1, pasta) + dinner(4, pasta) + dinner(7, pasta, at: 20, 10) + dinner(2, ["pizza"]) + dinner(5, ["pizza"])
    let found = UsualMeal.find(in: log, now: on(0, 19, 0), calendar: calendar)
    check(found?.meal == .dinner && found?.days == 3, "pasta three times is the usual dinner: \(String(describing: found))")
    check(found?.lastDay == on(1, 0, 0), "it copies yesterday's")
    check(found?.minute == 19 * 60 + 40, "the middle of its times: \(found?.minute ?? -1)")
    check(found?.time(on: today, calendar: calendar) == on(0, 19, 40), "its time today")
    check(UsualMeal.find(in: log, now: on(0, 18, 30), calendar: calendar) == nil, "not more than an hour early")
    check(UsualMeal.find(in: log, now: on(0, 21, 45), calendar: calendar) == nil, "not more than two hours late")
    check(UsualMeal.find(in: log + dinner(0, ["soup"], at: 18, 50), now: on(0, 19, 0), calendar: calendar) == nil, "not once dinner is logged")
    check(UsualMeal.find(in: dinner(1, pasta) + dinner(4, pasta), now: on(0, 19, 0), calendar: calendar) == nil, "twice is not a habit")
    check(UsualMeal.find(in: dinner(1, pasta) + dinner(4, pasta) + dinner(16, pasta), now: on(0, 19, 0), calendar: calendar) == nil, "only the last two weeks count")
    check(UsualMeal.find(in: dinner(1, pasta) + dinner(4, ["pasta", "sauce"]) + dinner(7, pasta), now: on(0, 19, 0), calendar: calendar) == nil, "the same foods, not nearly")
    log += dinner(10, ["pizza"]) + dinner(13, ["pizza"])
    check(UsualMeal.find(in: log, now: on(0, 19, 0), calendar: calendar)?.days == 4, "the most often wins: pizza four times")
    let eggs = (1...3).map { UsualMeal.Logged(date: on($0, 8, 5), meal: .breakfast, foodID: "eggs") }
    check(UsualMeal.find(in: eggs, now: on(0, 7, 30), calendar: calendar)?.meal == .breakfast, "breakfast at breakfast time")
    check(UsualMeal.find(in: eggs, now: on(0, 13, 0), calendar: calendar) == nil, "not at lunch")
    check(found?.dismissalKey(on: on(0, 19, 0), calendar: calendar) == found?.dismissalKey(on: on(0, 21, 0), calendar: calendar), "Not today lasts the day")
    check(found?.dismissalKey(on: on(0, 19, 0), calendar: calendar) != found?.dismissalKey(on: on(-1, 19, 0), calendar: calendar), "and only the day")

    // Day two: yesterday's breakfast waits at its hour until a usual is learned.
    let dayOne = [UsualMeal.Logged(date: on(1, 8, 10), meal: .breakfast, foodID: "croissant"),
                  UsualMeal.Logged(date: on(1, 8, 12), meal: .breakfast, foodID: "coffee"),
                  UsualMeal.Logged(date: on(1, 12, 40), meal: .lunch, foodID: "shawarma")]
    let again = UsualMeal.yesterday(in: dayOne, now: on(0, 8, 30), calendar: calendar)
    check(again?.meal == .breakfast && again?.kind == .yesterday && again?.minute == 8 * 60 + 10, "yesterday's breakfast at 8:10: \(String(describing: again))")
    check(again?.question == "Same as yesterday?", "asked as the same as yesterday")
    check(UsualMeal.yesterday(in: dayOne, now: on(0, 12, 0), calendar: calendar)?.meal == .lunch, "at noon, yesterday's lunch")
    check(UsualMeal.yesterday(in: dayOne, now: on(0, 16, 0), calendar: calendar) == nil, "nothing between meals")
    check(UsualMeal.yesterday(in: dayOne + [.init(date: on(0, 7, 50), meal: .breakfast, foodID: "skyr")], now: on(0, 8, 30), calendar: calendar) == nil,
          "not once breakfast is in")
    let week = (1...7).map { UsualMeal.Logged(date: on($0, 8, 10), meal: .breakfast, foodID: "food\($0)") }
    check(UsualMeal.yesterday(in: week, now: on(0, 8, 30), calendar: calendar) == nil, "after a week of log, only a learned usual is offered")
}

// What your body really burns, from your weighings and your meals.
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 19))!
    let today = calendar.startOfDay(for: now)
    func day(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: today)! }
    // Losing 0.04 kg a day while eating 2,000: the body burns 2,000 + 0.04 x 7,700 = 2,308.
    let weighings = stride(from: 21, through: 0, by: -3).map {
        LearnedMaintenance.Weighing(date: calendar.date(byAdding: .hour, value: 7, to: day($0))!, kilograms: 80 - 0.04 * Double(21 - $0))
    }
    var kcals: [Date: Double] = [:]
    for daysAgo in 1...21 { kcals[day(daysAgo)] = 2000 }
    let learned = LearnedMaintenance.learn(weighings: weighings, dayKcals: kcals, now: now, calendar: calendar)
    check(learned.map { near($0.kcal, 2308, 1) } == true && learned?.days == 21, "2,000 eaten, 0.28 kg a week down: \(String(describing: learned))")
    check(learned?.goal(for: .lose, sex: .male) == 1810 && learned?.goal(for: .maintain, sex: .male) == 2310, "goals from it")
    check(LearnedMaintenance(kcal: 1500, days: 14).goal(for: .lose, sex: .female) == 1200, "never under the floor")
    var noisy = weighings
    noisy[3] = LearnedMaintenance.Weighing(date: noisy[3].date, kilograms: noisy[3].kilograms + 1.2)
    let calm = LearnedMaintenance.learn(weighings: noisy, dayKcals: kcals, now: now, calendar: calendar)
    check(calm.map { abs($0.kcal - 2308) < 150 } == true, "one heavy morning moves it little: \(calm?.kcal ?? 0)")
    check(LearnedMaintenance.learn(weighings: Array(weighings.suffix(4)), dayKcals: kcals, now: now, calendar: calendar) == nil, "too few weighings")
    var halfLogged: [Date: Double] = [:]
    for daysAgo in stride(from: 1, through: 21, by: 3) { halfLogged[day(daysAgo)] = 2000 }
    check(LearnedMaintenance.learn(weighings: weighings, dayKcals: halfLogged, now: now, calendar: calendar) == nil, "most days have to be logged")
    var light = kcals
    for daysAgo in 1...21 where daysAgo % 2 == 0 { light[day(daysAgo)] = 400 }
    check(LearnedMaintenance.learn(weighings: weighings, dayKcals: light, now: now, calendar: calendar) == nil, "forgotten days do not count as eaten")
    var recentOnly: [Date: Double] = [:]
    for daysAgo in 1...10 { recentOnly[day(daysAgo)] = 2000 }
    check(LearnedMaintenance.learn(weighings: weighings, dayKcals: recentOnly, now: now, calendar: calendar) == nil, "ten days of meals are not two weeks")
}

// Your log as a spreadsheet: oldest first, points for decimals, quoted when it has to be.
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let lunch = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12, minute: 30))!
    let breakfast = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8, minute: 5))!
    let rows = [
        LogExport.Row(date: lunch, meal: .lunch, name: "Shawarma, \"big\"", brand: nil, amount: 1, unit: .serving,
                      kcal: 612.44, protein: 38.06, carbs: 52, fat: 26.5, fiber: nil, sugar: 4.25, place: "El Beirout"),
        LogExport.Row(date: breakfast, meal: .breakfast, name: "=cmd", brand: "Migros", amount: 150, unit: .gram,
                      kcal: 99, protein: 15, carbs: 6, fat: 0.3, fiber: 0, sugar: 6, place: nil),
    ]
    let lines = LogExport.csv(rows, calendar: calendar).components(separatedBy: "\r\n")
    check(lines.count == 4 && lines[3].isEmpty, "header, two rows, a closing line break: \(lines.count)")
    check(lines[1].hasPrefix("2026-10-12,08:05,") && lines[2].hasPrefix("2026-10-12,12:30,"), "oldest first: \(lines[1])")
    check(lines[2].contains(",\"Shawarma, \"\"big\"\"\",,1,") , "quotes doubled, commas quoted: \(lines[2])")
    check(lines[2].contains(",612.4,38.1,52,26.5,,4.3,El Beirout"), "one decimal with a point, empty when unknown: \(lines[2])")
    check(lines[1].contains(",'=cmd,Migros,150,g,99,15,6,0.3,0,6,"), "a formula is shown, not run: \(lines[1])")
    check(LogExport.file(rows, calendar: calendar).prefix(3) == Data([0xEF, 0xBB, 0xBF]), "a byte order mark first")
    check(LogExport.number(2000) == "2000" && LogExport.number(0.04) == "0" && LogExport.number(7.96) == "8", "numbers")
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
check((2149.0).roughKcalText == (2150.0).kcalText && (237.0).roughKcalText == (240.0).kcalText && Double.nan.roughKcalText == "0", "estimates round to 10")

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
    // The doubt: a question whose answers set one ingredient, kept on its item when an
    // impossible item before it is dropped.
    let data = try Data(contentsOf: fixtures.appendingPathComponent("claude_meal_doubt.json"))
    let estimate = try ClaudeVision.parse(data)
    check(estimate.items.count == 2 && estimate.doubt?.item == 1, "the doubt follows its item: \(String(describing: estimate.doubt))")
    check(estimate.doubt?.answers.map(\.label) == ["Un peu", "Une cuillère", "Beaucoup"], "answers decode")
    check(estimate.doubt?.chosen(in: estimate.items) == 1, "the likeliest answer starts chosen")
    let more = estimate.setting(item: 1, grams: 25, from: estimate)
    check(near(more.totals.kcal, 314 + 220) && more.doubt?.chosen(in: more.items) == 2, "a lot of oil: \(more.totals.kcal)")
    let none = more.setting(item: 1, grams: 0, from: estimate)
    check(near(none.totals.kcal, 314) && none.doubt?.chosen(in: none.items) == nil, "no oil, and no answer matches 0 here")
    let back = none.setting(item: 1, grams: 10, from: estimate)
    check(near(back.totals.kcal, 402), "an item set to nothing comes back from the original: \(back.totals.kcal)")

    // An impossible fiber on the doubted item becomes unknown, and the doubt stays on it.
    let oily = String(decoding: data, as: UTF8.self).replacingOccurrences(
        of: #"\"carbs\":0,\"fat\":10}"#, with: #"\"carbs\":0,\"fat\":10,\"fiber\":40,\"sugar\":0}"#)
    let cleaned = try ClaudeVision.parse(Data(oily.utf8))
    check(cleaned.doubt?.item == 1, "cleaning the oil's fiber keeps its question: \(String(describing: cleaned.doubt))")
    check(cleaned.items.last?.fiber == nil && cleaned.items.last?.sugar == 0, "40 g of fiber in oil is unknown; its sugar stays")

    let older = try ClaudeVision.parse(Data(contentsOf: fixtures.appendingPathComponent("claude_meal.json")))
    check(older.doubt == nil, "an answer without a doubt still reads")
    let item = MealEstimate.Item(name: "Oil", emoji: "🫒", grams: 10, kcal: 88, protein: 0, carbs: 0, fat: 10)
    let answers: [MealEstimate.Doubt.Answer] = [.init(label: "A little", grams: 5), .init(label: "A lot", grams: 25)]
    check(MealEstimate.Doubt(question: "How much oil?", item: 0, answers: answers).isAskable(about: item), "askable")
    check(!MealEstimate.Doubt(question: " ", item: 0, answers: answers).isAskable(about: item), "no question, nothing to ask")
    check(!MealEstimate.Doubt(question: "How much oil?", item: 0, answers: [answers[0]]).isAskable(about: item), "one answer is no choice")
    check(!MealEstimate.Doubt(question: "How much oil?", item: 0, answers: answers).isAskable(about: item.with(grams: 0)), "an item with no grams cannot scale")
    let schema = MealEstimate.schema["properties"] as? [String: Any]
    check((MealEstimate.schema["required"] as? [String])?.contains("doubt") == true && schema?["doubt"] != nil, "the schema asks for the doubt")
    check(ClaudeVision.prompt(language: "fr").contains("never 0"), "the prompt keeps the likeliest answer above zero")

    // Bite's server answers with the estimate itself, not wrapped in a message: the same cleaning.
    let wrapped = try JSONSerialization.jsonObject(with: Data(oily.utf8)) as? [String: Any]
    let text = ((wrapped?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
    let bare = try JSONDecoder().decode(MealEstimate.self, from: Data(text.utf8)).cleaned()
    check(bare == cleaned, "the server's answer is cleaned the same way as Claude's")

    // The server asks Gemini in the app's own words: every line of the prompt is in meal.ts.
    let server = (try? String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1] + "/server/supabase/functions/estimate/meal.ts"), encoding: .utf8)) ?? ""
    for isLabel in [false, true] {
        let lines = ClaudeVision.prompt(language: "§", isLabel: isLabel).split(separator: "\n").map(String.init).filter { !$0.contains("§") }
        let missing = lines.filter { !server.contains($0) }
        check(!lines.isEmpty && missing.isEmpty, "the server's prompt matches the app's (label \(isLabel)): \(missing)")
    }
} catch {
    failures += 1
    print("FAIL: doubt fixture threw \(error)")
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

// Anthropic's own words when it refuses a request: no credit, no access.
check(ClaudeVision.errorMessage(in: Data(#"{"type":"error","error":{"type":"billing_error","message":"Your credit balance is too low."}}"#.utf8)) == "Your credit balance is too low.", "API error message")
check(ClaudeVision.errorMessage(in: Data("<html>Bad gateway</html>".utf8)) == nil, "no message in an HTML page")
check(ClaudeVision.Failure.refused("No credit.").errorDescription == "Anthropic says: No credit.", "refusal text")

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

// MARK: Fiber

do {
    check(FiberTarget.grams(forGoal: 1500) == 25, "a 1,500 kcal cut still aims for 25 g")
    check(FiberTarget.grams(forGoal: 1800) == 25, "1,800 kcal: 25 g")
    check(FiberTarget.grams(forGoal: 2000) == 28, "2,000 kcal: 28 g")
    check(FiberTarget.grams(forGoal: 2500) == 35, "2,500 kcal: 35 g")
    check(FiberTarget.grams(forGoal: 3500) == 38, "3,500 kcal stops at 38 g")

    // Pasta with its fiber and an egg with none on record: the egg leaves no gap.
    let clear = FiberDay.make([.init(fiber: 4, carbs: 68), .init(fiber: nil, carbs: 0.4)])
    check(clear.known == 1 && clear.counted == 1, "an egg without fiber is not counted: \(clear)")
    check(clear.isShown && !clear.isPartial, "a day it can see whole shows, without small print")
    check(near(clear.grams, 4), "fiber adds up: \(clear.grams)")

    // Granola from a label without fiber carries a quarter of the carbs: shown, with small print.
    let partial = FiberDay.make([.init(fiber: nil, carbs: 29), .init(fiber: 3, carbs: 27), .init(fiber: 4, carbs: 68)])
    check(partial.known == 2 && partial.counted == 3, "two of three foods: \(partial)")
    check(partial.isShown && partial.isPartial, "a quarter unknown shows the small print")

    // Most of the carbs from a product without fiber: hidden, rather than a total far too low.
    let blind = FiberDay.make([.init(fiber: nil, carbs: 60), .init(fiber: 4.4, carbs: 25)])
    check(!blind.isShown, "under half the carbs known hides the line: \(blind.knownCarbShare)")
    check(!FiberDay.make([]).isShown, "an empty day has no fiber line")
    check(FiberDay.make([.init(fiber: 0, carbs: 0)]).isShown, "a known zero is a real zero")

    // A photo estimate's item scales its fiber with its grams.
    let rice = MealEstimate.Item(name: "Rice", emoji: "🍚", grams: 150, kcal: 195, protein: 4, carbs: 42, fat: 0.4, fiber: 0.6, sugar: 0.1)
    check(near(rice.with(grams: 300).fiber ?? -1, 1.2), "fiber doubles with the rice")
    check(near(rice.nutrients.fiber ?? -1, 0.6), "an item's nutrients carry its fiber")
}

// MARK: Apple Health

do {
    let lunch = Date(timeIntervalSince1970: 1_760_000_000)
    let id = UUID()
    let shawarma = HealthMeal(id: id, date: lunch, name: "Chicken shawarma",
                              nutrients: Nutrients(kcal: 597, protein: 38, carbs: 55, fat: 24, fiber: nil, salt: 1.25))
    check(HealthMeal.sodiumMilligrams(fromSaltGrams: 1.25) == 500, "1.25 g of salt is 500 mg of sodium")
    check(shawarma.samples.contains { $0.nutrient == .sodium && $0.value == 500 }, "sodium is written in milligrams")
    check(!shawarma.samples.contains { $0.nutrient == .fiber }, "no fiber on record writes no fiber")
    let coffee = HealthMeal(id: UUID(), date: lunch, name: "Coffee", nutrients: Nutrients(kcal: 2, protein: 0.3, carbs: 0, fat: 0))
    check(coffee.samples.map(\.nutrient) == [.energy, .protein], "a black coffee is not six zeros: \(coffee.samples.map(\.nutrient))")

    // New: written at version 1.
    let first = HealthPlan.make(desired: [shawarma], written: [])
    check(first.saves == [.init(meal: shawarma, version: 1)] && first.deletes.isEmpty, "a new meal is saved at version 1")
    // Unchanged: nothing to do, however often it runs.
    let same = HealthPlan.make(desired: [shawarma], written: [HealthWritten(syncID: shawarma.syncID, version: 1, signature: shawarma.signature)])
    check(same.isEmpty, "running again changes nothing")
    // An edit bumps the version so Health replaces its copy.
    let bigger = HealthMeal(id: id, date: lunch, name: "Chicken shawarma", nutrients: Nutrients(kcal: 790, protein: 50, carbs: 70, fat: 32))
    let edit = HealthPlan.make(desired: [bigger], written: [HealthWritten(syncID: shawarma.syncID, version: 3, signature: shawarma.signature)])
    check(edit.saves == [.init(meal: bigger, version: 4)], "an edit is written one version up")
    // A move in time is an edit too.
    let later = HealthMeal(id: id, date: lunch.addingTimeInterval(1800), name: "Chicken shawarma", nutrients: shawarma.nutrients)
    check(HealthPlan.make(desired: [later], written: [HealthWritten(syncID: shawarma.syncID, version: 1, signature: shawarma.signature)]).saves.count == 1,
          "moving a meal rewrites it")
    // Deleted from the log: deleted from Health. Undo brings the same id back, so nothing changes.
    let gone = HealthPlan.make(desired: [], written: [HealthWritten(syncID: shawarma.syncID, version: 2, signature: shawarma.signature)])
    check(gone.deletes == [shawarma.syncID] && gone.saves.isEmpty, "a deleted meal leaves Health")
    // Two copies of the same meal in Health: the newest version counts.
    let doubled = HealthPlan.make(desired: [shawarma], written: [
        HealthWritten(syncID: shawarma.syncID, version: 1, signature: "old"),
        HealthWritten(syncID: shawarma.syncID, version: 2, signature: shawarma.signature),
    ])
    check(doubled.isEmpty, "the newest copy is the one compared")
}

// MARK: Mealtime nudge

do {
    var zurich = Calendar(identifier: .gregorian)
    zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let day = zurich.date(from: DateComponents(year: 2026, month: 10, day: 13))!
    func at(_ hour: Int, _ minute: Int = 0, plus days: Int = 0) -> Date {
        zurich.date(byAdding: DateComponents(day: days, hour: hour, minute: minute), to: day)!
    }
    let reminder = MealReminder(firstLog: at(8, 10), meal: .breakfast, calendar: zurich)
    check(reminder.meal == .breakfast && reminder.minute == 8 * 60 + 10, "breakfast at 8:10")
    check(MealReminder(firstLog: at(16, 30), meal: .snack, calendar: zurich).meal == .breakfast, "a snack first never gets a snack nudge")
    check(MealReminder(firstLog: at(19, 40), meal: .snack, calendar: zurich).meal == .dinner, "a snack at dinner time is dinner")
    check(MealReminder.shouldOffer(entries: 2, answered: false) && !MealReminder.shouldOffer(entries: 1, answered: false), "after the second log")
    check(!MealReminder.shouldOffer(entries: 9, answered: true), "never again after an answer")
    let early = reminder.fireDates(now: at(7), loggedToday: false, calendar: zurich)
    check(early == [at(8, 10), at(8, 10, plus: 1), at(8, 10, plus: 2)], "today too while it is ahead: \(early)")
    check(reminder.fireDates(now: at(7), loggedToday: true, calendar: zurich) == [at(8, 10, plus: 1), at(8, 10, plus: 2)], "not today once breakfast is in")
    check(reminder.fireDates(now: at(9), loggedToday: false, calendar: zurich).first == at(8, 10, plus: 1), "past its time, from tomorrow")
}

// MARK: Community server

do {
    let json = """
    [{"id":"7a1c","name":"Chicken shawarma","emoji":"🌯","photo_path":null,"rating_sum":119,"rating_count":26,"my_rating":4,
      "place":{"id":"p1","name":"El Beirout","area":"Parc de Milan","category":"restaurant","latitude":46.51492,"longitude":6.62268},
      "estimates":[{"id":"e1","author_id":"u1","author":"Tom R.","source":"ai","kcal":590,"protein":38,"carbs":55,"fat":24,
                    "agrees":23,"agreed_by_me":true,"is_mine":false}]}]
    """
    let dishes = try CommunityRemote.dishes(from: Data(json.utf8))
    check(dishes.count == 1 && dishes[0].place.name == "El Beirout" && dishes[0].myRating == 4, "a dish near you decodes")
    check(dishes[0].estimates.first?.authorId == "u1" && dishes[0].estimates.first?.agreedByMe == true, "snake case becomes camel case")
    let share = CommunityRemote.Share(
        pPlace: .init(id: "p1", mapkitId: nil, name: "El Beirout", area: "Parc de Milan", category: "restaurant", latitude: 46.5, longitude: 6.6),
        pDish: .init(id: "d1", name: "Chicken shawarma", emoji: "🌯"),
        pEstimate: .init(id: "e9", source: "ai", kcal: 590, protein: 38, carbs: 55, fat: 24)
    )
    let body = String(decoding: try CommunityRemote.encoder.encode(share), as: UTF8.self)
    check(body.contains("\"p_place\"") && body.contains("\"mapkit_id\"") == false && body.contains("\"p_estimate\""), "the share's arguments are named as the function's: \(body.prefix(80))")
    check(CommunityRemote.shortName(given: "Dylan", family: "Trigos") == "Dylan T.", "first name and initial")
    check(CommunityRemote.shortName(given: "Léa", family: nil) == "Léa", "no family name, no initial")
    check(CommunityRemote.shortName(given: nil, family: nil).isEmpty, "no name at all")
}

// MARK: Widgets

do {
    let day = Nutrients(kcal: 1033, protein: 62, carbs: 79, fat: 55)
    let today = WidgetSnapshot.make(day: day, goal: 2000, water: 3)
    check(today.headline == 967 && today.headlineKind == .left, "967 kcal left")
    check(today.targets == MacroTargets(kcal: 2000, split: .balanced), "the macros aim for the goal's split")
    let ring = today.ring
    check(near(ring.protein + ring.carbs + ring.fat, 1033.0 / 2000, 0.001) && ring.overflow == 0, "the ring fills to half: \(ring)")
    let over = WidgetSnapshot.make(day: Nutrients(kcal: 2450, protein: 152, carbs: 312, fat: 98), goal: 2000)
    check(over.headline == 450 && over.headlineKind == .over && near(over.ring.overflow, 0.225), "450 kcal over, the outer ring a quarter red")
    let burned = WidgetSnapshot.make(day: day, goal: 2000, burned: 412)
    check(burned.headline == 1379, "burned calories added to the goal leave more")
    let free = WidgetSnapshot.make(day: over.eaten, goal: 2000, noTarget: true)
    check(free.headline == 2450 && free.headlineKind == .eaten && free.ring.overflow == 0, "no target: what was eaten, never red")
    let empty = WidgetSnapshot.make(day: .zero, goal: 2000)
    check(empty.ring.protein == 0 && empty.headline == 2000 && empty.progress == 0, "an empty day: the whole goal left")
    check(WidgetSnapshot.make(day: day, goal: 2000, waterGoal: 0).waterGoal == 1, "a water goal of nothing is one glass")
}

// MARK: First run

do {
    var zurich = Calendar(identifier: .gregorian)
    zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let day = zurich.date(from: DateComponents(year: 2026, month: 10, day: 13))!
    func at(_ hour: Int) -> Date { zurich.date(byAdding: .hour, value: hour, to: day)! }
    check(HourFoods.moment(at: at(8), calendar: zurich) == .morning && HourFoods.moment(at: at(12), calendar: zurich) == .noon, "morning and noon")
    check(HourFoods.moment(at: at(16), calendar: zurich) == .afternoon && HourFoods.moment(at: at(20), calendar: zurich) == .evening, "afternoon and evening")
    check(HourFoods.moment(at: at(2), calendar: zurich) == .evening, "the small hours belong to the evening")
    let basics = BasicFoods.load(from: URL(fileURLWithPath: CommandLine.arguments[1] + "/Bite/Resources/basics.json"), language: "en")
    let known = Set(basics.map(\.food.id))
    for moment in [HourFoods.Moment.morning, .noon, .afternoon, .evening] {
        let ids = HourFoods.ids(for: moment).map { "usda:\($0)" }
        check(ids.count == 8 && Set(ids).count == 8, "eight different foods for \(moment)")
        check(ids.allSatisfy(known.contains), "every food for \(moment) is a basic: \(ids.filter { !known.contains($0) })")
    }
    check(HourFoods.foodIDs(at: at(8), calendar: zurich).first == "usda:171890", "coffee first in the morning")
    check(HourFoods.question(at: at(8), calendar: zurich) == "What did you have this morning?", "the morning question")
    check(HourFoods.isLate(at(22), calendar: zurich) && !HourFoods.isLate(at(20), calendar: zurich), "late is after nine")
    for moment in [HourFoods.Moment.morning, .noon, .afternoon, .evening] {
        let unlabeled = HourFoods.ids(for: moment).filter { HourFoods.label(for: "usda:\($0)") == nil }
        check(unlabeled.isEmpty, "every food for \(moment) has a tile label: \(unlabeled)")
    }
    check(HourFoods.label(for: "usda:171477") == "Chicken breast" && HourFoods.label(for: "off:123") == nil, "tile labels by id")
}

// MARK: Weekly check-in

do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_760_270_400) // a Sunday, 12:00 UTC
    let today = utc.startOfDay(for: now)
    func day(_ offset: Int) -> Date { utc.date(byAdding: .day, value: offset, to: today)! }
    var kcals: [Date: Double] = [:]
    for offset in -21...(-1) { kcals[day(offset)] = 2000 }
    // Down 0.05 kg a day while eating 2,000: about 2,385 burned.
    let weighings = stride(from: -20, through: -1, by: 3).map { offset in
        LearnedMaintenance.Weighing(date: day(offset).addingTimeInterval(7 * 3600), kilograms: 80 - 0.05 * Double(offset))
    }

    check(CheckIn.step(gap: 400) == 150 && CheckIn.step(gap: -400) == -150, "a big gap moves 150 a week")
    check(CheckIn.step(gap: 120) == 60 && CheckIn.step(gap: -60) == -50, "half the gap, at least 50")
    check(CheckIn.step(gap: 40) == 0, "under 50, nothing to offer")

    let up = CheckIn.make(now: now, dayKcals: kcals, weighings: weighings, currentGoal: 2000, weightGoal: .maintain, sex: .female, calendar: utc)
    check(up?.offeredGoal == 2150 && up?.delta == 150, "maintaining on 2,000 while burning 2,385: 150 up: \(String(describing: up))")
    check(up?.wholeDays == 7 && near(up?.averageEaten ?? 0, 2000), "the week's whole days")
    check(up.map { $0.burned > 2300 && $0.burned < 2450 } == true, "about 2,385 burned: \(up?.burned ?? 0)")
    check(up?.trendChange.map { $0 < -0.2 && $0 > -0.5 } == true, "the trend fell about 0.35 kg: \(String(describing: up?.trendChange))")

    let down = CheckIn.make(now: now, dayKcals: kcals, weighings: weighings, currentGoal: 2000, weightGoal: .lose, sex: .female, calendar: utc)
    check(down?.delta == -60, "losing: half of a 110 kcal gap: \(String(describing: down?.delta))")
    check(CheckIn.make(now: now, dayKcals: kcals, weighings: weighings, currentGoal: 2370, weightGoal: .maintain, sex: .female, calendar: utc) == nil,
          "a goal close to what you burn gets no check-in")

    var patchy = kcals
    for offset in -4...(-1) { patchy[day(offset)] = 300 }
    check(CheckIn.make(now: now, dayKcals: patchy, weighings: weighings, currentGoal: 2000, weightGoal: .maintain, sex: .female, calendar: utc) == nil,
          "three whole days this week are not enough")
    let old = weighings.filter { $0.date < day(-7) }
    check(CheckIn.make(now: now, dayKcals: kcals, weighings: old, currentGoal: 2000, weightGoal: .maintain, sex: .female, calendar: utc) == nil,
          "no weighing this week, no check-in")

    // When it shows.
    var history = CheckInHistory()
    check(!history.isDue(now: now, gap: 385, calendar: utc), "no check-in day yet")
    history.start(now: now, calendar: utc)
    check(history.isDue(now: now, gap: 385, calendar: utc), "the first day it has something to say is the check-in day")
    check(history.isDue(now: now.addingTimeInterval(2 * 86_400), gap: 385, calendar: utc), "still there two days later")
    check(!history.isDue(now: now.addingTimeInterval(3 * 86_400), gap: 385, calendar: utc), "gone after three days, without asking again")
    history.used(previousGoal: 2000, now: now, calendar: utc)
    check(!history.isDue(now: now.addingTimeInterval(3600), gap: 235, calendar: utc), "answered this week")
    check(history.canUndo(now: now.addingTimeInterval(3600), calendar: utc), "Undo stays for the week")
    check(history.isDue(now: now.addingTimeInterval(7 * 86_400), gap: 235, calendar: utc), "back next week")
    check(!history.canUndo(now: now.addingTimeInterval(7 * 86_400), calendar: utc), "Undo ends with the week")

    var keeper = CheckInHistory()
    keeper.start(now: now, calendar: utc)
    keeper.kept(gap: 385, now: now, calendar: utc)
    let week1 = now.addingTimeInterval(7 * 86_400)
    check(keeper.isDue(now: week1, gap: 385, calendar: utc), "one Keep: asks again next week")
    keeper.kept(gap: 385, now: week1, calendar: utc)
    check(!keeper.isDue(now: week1.addingTimeInterval(7 * 86_400), gap: 385, calendar: utc), "two Keeps: skips a week")
    let week3 = week1.addingTimeInterval(14 * 86_400)
    check(keeper.isDue(now: week3, gap: 385, calendar: utc), "two Keeps: asks every other week")
    keeper.kept(gap: 385, now: week3, calendar: utc)
    let week4 = week3.addingTimeInterval(7 * 86_400)
    check(!keeper.isDue(now: week4, gap: 400, calendar: utc), "three Keeps: waits for the gap to grow")
    check(keeper.isDue(now: week4, gap: 540, calendar: utc), "three Keeps: asks once it grew by 150")
}

// MARK: Your mirror

do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let start = Date(timeIntervalSince1970: 1_760_000_000)
    func later(_ days: Int) -> Date { start.addingTimeInterval(Double(days) * 86_400) }

    // The gap, in the unit people say it in.
    check(MirrorGap.between(start, start, calendar: utc) == .days(0), "the same day")
    check(MirrorGap.between(start, later(13), calendar: utc) == .days(13), "13 days stay days")
    check(MirrorGap.between(start, later(14), calendar: utc) == .weeks(2), "14 days are 2 weeks")
    check(MirrorGap.between(later(42), start, calendar: utc) == .weeks(6), "either order: 6 weeks")
    check(MirrorGap.between(start, later(59), calendar: utc) == .weeks(8), "59 days are 8 weeks")
    check(MirrorGap.between(start, later(60), calendar: utc) == .months(2), "60 days are 2 months")
    check(MirrorGap.between(start, later(400), calendar: utc) == .years(1), "400 days are a year")
    check(!MirrorGap.weeks(7).isLong && MirrorGap.weeks(8).isLong && MirrorGap.months(3).isLong, "eight weeks is long")

    // When Bite asks.
    var history = MirrorHistory()
    check(!history.asksFirst(now: later(1), firstDay: start, calendar: utc), "never on the first two days")
    check(history.asksFirst(now: later(2), firstDay: start, calendar: utc), "the third day asks for the first photo")
    check(history.asksFirst(now: later(2), firstDay: nil, calendar: utc), "an install from before the first run asks")
    check(!history.asksNext(now: later(27), newest: start, weighedToday: false, calendar: utc), "27 days: not yet")
    check(history.asksNext(now: later(28), newest: start, weighedToday: false, calendar: utc), "28 days: the next photo")
    check(history.asksNext(now: later(25), newest: start, weighedToday: true, calendar: utc), "a weighing this morning at 25 days")
    check(!history.asksNext(now: later(24), newest: start, weighedToday: true, calendar: utc), "but not at 24")
    history.notNow(now: later(28), calendar: utc)
    check(!history.asksNext(now: later(30), newest: start, weighedToday: true, calendar: utc), "Not now waits a week")
    check(history.asksNext(now: later(35), newest: start, weighedToday: false, calendar: utc), "back a week later")
    history.notNow(now: later(35), calendar: utc)
    history.notNow(now: later(42), calendar: utc)
    check(!history.asksNext(now: later(80), newest: start, weighedToday: true, calendar: utc), "three Not nows: never again")
    history.took()
    check(history.asksNext(now: later(80), newest: start, weighedToday: false, calendar: utc), "a photo taken from Settings starts over")

    // Lining two photos up.
    let older = MirrorPlacement(centerX: 0.45, shoulderY: 0.30, spanTorso: 0.20)
    let newer = MirrorPlacement(centerX: 0.55, shoulderY: 0.25, spanTorso: 0.25)
    let align = MirrorAlign.make(older: older, newer: newer)
    check(near(align.scale, 1.25), "the torsos match: \(align.scale)")
    let shoulders = align.place(x: 0.45, y: 0.30)
    check(near(shoulders.x, 0.55) && near(shoulders.y, 0.25), "the shoulders meet: \(shoulders)")
    let hips = align.place(x: 0.45, y: 0.50)
    check(near(hips.y, 0.50), "the hips meet too: \(hips)")
    check(!align.movesNewer, "the smaller body is the older one: it moves")
    check(MirrorAlign.make(older: older, newer: nil) == .none, "no body found: shown as it is")
    let shrunk = MirrorAlign.make(older: newer, newer: older)
    check(shrunk.movesNewer && shrunk.scale >= 1.25, "the newer body smaller: the newer photo grows instead: \(shrunk)")
    for moved in [align, shrunk, MirrorAlign.make(older: MirrorPlacement(centerX: 0.45, shoulderY: 0.25, spanTorso: 0.24), newer: MirrorPlacement(centerX: 0.55, shoulderY: 0.28, spanTorso: 0.25))] {
        let topLeft = moved.place(x: 0, y: 0)
        let bottomRight = moved.place(x: 1, y: 1)
        check(topLeft.x <= 0.0001 && topLeft.y <= 0.0001 && bottomRight.x >= 0.9999 && bottomRight.y >= 0.9999, "the moved photo still fills the frame: \(moved)")
    }
    check(MirrorAlign.make(older: MirrorPlacement(centerX: 0.5, shoulderY: 0.3, spanTorso: 0.1), newer: newer).scale == 1.4, "a wild zoom is capped")
    let wide = MirrorPlacement(centerX: 0.5, shoulderY: 0.3, spanTorso: 0.2).filling(photoAspect: 1, frameAspect: 0.75)
    check(near(wide.centerX, 0.5) && near(wide.spanTorso, 0.2), "a square photo in a 3:4 frame keeps its middle")
    let edge = MirrorPlacement(centerX: 0.25, shoulderY: 0.3, spanTorso: 0.2).filling(photoAspect: 1, frameAspect: 0.75)
    check(near(edge.centerX, 1.0 / 6.0), "and its sides are cut: \(edge.centerX)")
    let tall = MirrorPlacement(centerX: 0.5, shoulderY: 0.25, spanTorso: 0.2).filling(photoAspect: 0.5, frameAspect: 0.75)
    check(near(tall.shoulderY, 0.125) && near(tall.spanTorso, 0.3), "a tall photo: top and bottom cut: \(tall)")

    // Straightening.
    check(near(MirrorLevel.keptShare(width: 3, height: 4, degrees: 0), 1), "level keeps it all")
    check(near(MirrorLevel.keptShare(width: 3, height: 4, degrees: 2), 0.956, 0.002), "2 degrees keeps 96%")
    check(near(MirrorLevel.keptShare(width: 3, height: 4, degrees: -5), 0.899, 0.002), "5 degrees either way keeps 90%")

    // The guide. Ten frames a second; t is the time in seconds.
    func body(_ shoulder: Double, _ hip: Double, ankle: Double? = nil, x: Double = 0.5) -> MirrorReading {
        MirrorReading(body: MirrorBody(shoulderY: shoulder, hipY: hip, ankleY: ankle, centerX: x, top: max(shoulder - 0.1, 0.05)),
                      height: (ankle ?? hip) - shoulder + 0.15, luma: 0.5)
    }
    func run(_ guide: inout MirrorGuide, _ reading: MirrorReading, from: Double, to: Double, roll: Double = 0) -> [MirrorGuide.Output] {
        var outputs: [MirrorGuide.Output] = []
        var t = from
        while t < to - 0.0001 {
            outputs.append(guide.update(reading, roll: roll, now: t))
            t += 0.1
        }
        return outputs
    }

    var first = MirrorGuide(mode: .mirror, target: nil)
    check(run(&first, .nobody, from: 0, to: 1).last?.line == .fitIn, "nobody: fit yourself in")
    check(run(&first, MirrorReading(tooClose: true), from: 1, to: 2).last?.line == .stepBack, "too close: step back")
    // The first photo in a small bathroom: only the torso fits, and stepping back stops helping.
    var outs = run(&first, body(0.3, 0.7), from: 2, to: 5)
    check(outs.last?.line == .stepBack, "first photo: step back while it can still get smaller")
    outs = run(&first, body(0.3, 0.65), from: 5, to: 11)
    check(outs.contains { $0.line == .stepBack }, "smaller is better: still stepping back")
    outs = run(&first, body(0.3, 0.65), from: 11, to: 12.5)
    check(outs.contains { $0.line == .yourSpot }, "six seconds without getting smaller: this is your spot")
    outs = run(&first, body(0.3, 0.65), from: 12.5, to: 15)
    check(outs.contains { $0.fire }, "then it takes the photo by itself")
    check(outs.filter(\.fire).count == 1, "once")
    outs = run(&first, body(0.3, 0.65), from: 15, to: 30)
    check(!outs.contains { $0.fire }, "never again by itself after the photo")
    check(outs.last?.line == .kept, "Ready after the photo offers another: \(String(describing: outs.last?.line))")

    // The whole body in the frame: its spot straight away.
    var whole = MirrorGuide(mode: .mirror, target: nil)
    outs = run(&whole, body(0.2, 0.45, ankle: 0.9), from: 0, to: 4)
    check(outs.contains { $0.line == .yourSpot } && outs.contains { $0.fire }, "a whole body fits: its spot, then the photo")
    var tiny = MirrorGuide(mode: .mirror, target: nil)
    check(run(&tiny, body(0.4, 0.5, ankle: 0.7), from: 0, to: 2).last?.line == .stepCloser, "a whole body too small: step closer")

    // The second photo lines up with the first.
    let target = MirrorTarget(shoulderY: 0.25, hipY: 0.55, ankleY: nil, centerX: 0.5)
    var second = MirrorGuide(mode: .mirror, target: target)
    check(run(&second, body(0.25, 0.70), from: 0, to: 2).last?.line == .stepBack, "bigger than the first: step back")
    check(run(&second, body(0.30, 0.50), from: 2, to: 4).last?.line == .stepCloser, "smaller than the first: step closer")
    outs = run(&second, body(0.25, 0.56), from: 4, to: 6)
    check(outs.last?.marks.shoulders == true && outs.last?.marks.hips == true && outs.last?.marks.center == true, "the marks go solid")
    outs += run(&second, body(0.25, 0.56), from: 6, to: 8)
    check(outs.contains { $0.fire }, "lined up and still: the photo, within about two seconds")
    var shaky = MirrorGuide(mode: .mirror, target: target)
    var wobble: [MirrorGuide.Output] = []
    for step in 0..<60 {
        // The phone bobbing up and down in the hand, once a second.
        let shift = 0.04 * sin(Double(step) * 0.1 * 2 * .pi)
        wobble.append(shaky.update(body(0.25 + shift, 0.56 + shift), roll: 0, now: Double(step) * 0.1))
    }
    check(wobble.last?.line == .holdStill && !wobble.contains { $0.fire }, "moving: hold still, and no photo")
    var tilted = MirrorGuide(mode: .mirror, target: target)
    outs = run(&tilted, body(0.25, 0.56), from: 0, to: 3, roll: 9)
    check(outs.last?.line == .level && outs.last?.level == false, "tilted past six degrees: level the phone")
    var slight = MirrorGuide(mode: .mirror, target: target)
    outs = run(&slight, body(0.25, 0.56), from: 0, to: 3, roll: 4)
    check(outs.contains { $0.fire } && outs.last?.level == false, "four degrees: taken, straightened on save")

    // Propped on the sink: set up, step back, count down out loud.
    var propped = MirrorGuide(mode: .propped, target: nil)
    check(run(&propped, .nobody, from: 0, to: 2).last?.line == .setUp, "propped: stand it up and step back")
    check(run(&propped, body(0.05, 0.6, ankle: 0.98), from: 2, to: 3).last?.line == .setUp, "still too close to start")
    outs = run(&propped, body(0.2, 0.45, ankle: 0.8), from: 3, to: 6)
    check(outs.contains { $0.countdown == 3 }, "three, two, one")
    check(!outs.contains { $0.fire }, "not yet")
    outs = run(&propped, body(0.2, 0.45, ankle: 0.8), from: 6, to: 9)
    check(outs.filter { $0.fire }.count == 1, "then the photo, once")
    var dark = MirrorGuide(mode: .propped, target: nil)
    outs = run(&dark, .nobody, from: 0, to: 15.3)
    check(outs.last?.countdown == 10, "a room too dark to see in: a plain ten second countdown")
    outs = run(&dark, .nobody, from: 15.3, to: 25.6)
    check(outs.filter { $0.fire }.count == 1, "and the photo all the same")
    var stubborn = MirrorGuide(mode: .propped, target: MirrorTarget(shoulderY: 0.2, hipY: 0.45, ankleY: 0.9, centerX: 0.5))
    outs = run(&stubborn, body(0.3, 0.5, ankle: 0.8), from: 0, to: 26)
    check(outs.contains { $0.line == .stepCloser }, "too far for the first photo's distance: step closer")
    check(outs.contains { $0.line == .takingNow }, "25 seconds after the pose began: taking it now")
}

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
