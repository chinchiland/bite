import SwiftUI
import SwiftData
import UIKit

/// Where a food goes when it is not a barcode: what you had recently, basics, and search.
enum FoodRoute: Hashable {
    case food(Food, amount: Double?)
    case quickAdd
    /// A typical portion of the words typed in search.
    case typical(String)
    /// One of the menus you photographed.
    case menu(UUID)
    /// A dish on one of them.
    case menuDish(UUID, MenuScan.Dish)
    /// All your menus.
    case menus
}

/// Each route's screen, for every stack that can push one: search, and a menu over the camera.
struct FoodRouteView: View {
    let route: FoodRoute
    let day: Date
    var meal: Meal? = nil
    let onDone: () -> Void

    var body: some View {
        switch route {
        case .food(let food, let amount):
            FoodDetailView(food: food, amount: amount, day: day, meal: meal, onDone: onDone)
        case .quickAdd:
            QuickAddView(day: day, meal: meal, onDone: onDone)
        case .typical(let words):
            TypicalDishView(origin: .typed(words), day: day, meal: meal, onDone: onDone)
        case .menu(let id):
            MenuView(source: .saved(id), day: day, onDone: onDone)
        case .menuDish(let id, let dish):
            TypicalDishView(origin: .menu(id, dish), day: day, meal: meal, onDone: onDone)
        case .menus:
            MenusView()
        }
    }
}

/// Search and add. Empty, it shows your saved foods, your menus and what you logged recently,
/// one tap from today. Typing offers a typical portion of what you typed first, then the dishes
/// on your menus, the bundled basics instantly and Open Food Facts as you pause.
struct AddFoodView: View {
    var day: Date = .now
    /// The meal to add to, when you came from a meal's menu.
    var meal: Meal? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query(AddFoodView.historyDescriptor) private var history: [FoodEntry]
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]

    @State private var path: [FoodRoute] = []
    @State private var query = ""
    @State private var searching = false
    @State private var products: [Food] = []
    @State private var isLoading = false
    @State private var resultsQuery = ""
    @State private var failed = false
    @State private var recents: [RecentFood] = []
    @State private var added: Set<String> = []
    /// Estimates can run for you: false under 18 without a key.
    @State private var canEstimate = false
    @State private var scanningMenu = false

    nonisolated static var historyDescriptor: FetchDescriptor<FoodEntry> {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 300
        return descriptor
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if trimmedQuery.isEmpty {
                    startSections
                } else {
                    resultSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.page.ignoresSafeArea())
            .navigationTitle(meal.map { String(localized: "Add to \($0.title)") } ?? String(localized: "Add food"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search food or brand")
            .autocorrectionDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task(id: trimmedQuery) { await searchProducts(trimmedQuery) }
            .navigationDestination(for: FoodRoute.self) { route in
                FoodRouteView(route: route, day: day, meal: meal) { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $scanningMenu) {
            ScannerView(day: day, startMode: .menu) { dismiss() }
        }
        .onAppear {
            recents = RecentFood.list(from: history)
            canEstimate = PhotoEstimator.isOpen
            #if DEBUG
            switch UserDefaults.standard.string(forKey: "screen") {
            case "typical": path = [.typical(UserDefaults.standard.string(forKey: "query") ?? "shawarma")]
            case "menus": if let first = MenuShelf.shared.menus.first { path = [.menu(first.id)] }
            case "menus.all": path = [.menus]
            default: break
            }
            if let demoQuery = UserDefaults.standard.string(forKey: "query") {
                query = demoQuery
                return
            }
            if UserDefaults.standard.string(forKey: "screen") != nil { return }
            #endif
            // You tapped search, so the keyboard is ready. The search field has to be on screen first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { searching = true }
        }
    }

    // MARK: Sections

    @ViewBuilder private var startSections: some View {
        Section {
            NavigationLink(value: FoodRoute.quickAdd) {
                HStack(spacing: 12) {
                    IconCircle(systemImage: "plus", size: 44)
                    Text("Quick add calories")
                        .font(.ui(17))
                        .foregroundStyle(Theme.ink)
                }
            }
            .listRowBackground(Theme.card)
            if canEstimate {
                Button { scanningMenu = true } label: {
                    HStack(spacing: 12) {
                        IconCircle(systemImage: "menucard", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan a menu")
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                            Text("Every dish with its calories")
                                .font(.ui(15))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
            }
        }

        if !saved.isEmpty {
            Section {
                ForEach(saved) { item in
                    OneTapRow(
                        food: item.food,
                        amount: item.amount,
                        subtitle: item.subtitle,
                        isAdded: added.contains("saved:\(item.foodID)"),
                        open: { path.append(.food(item.food, amount: item.amount)) },
                        add: { log(item.food, amount: item.amount, key: "saved:\(item.foodID)", preferred: item.meal) }
                    )
                    .listRowBackground(Theme.card)
                }
            } header: {
                SectionTitle(text: "Saved")
            }
        }

        let menus = MenuShelf.shared.menus
        if !menus.isEmpty {
            Section {
                ForEach(menus.prefix(2)) { menu in
                    NavigationLink(value: FoodRoute.menu(menu.id)) {
                        MenuRow(menu: menu)
                    }
                    .listRowBackground(Theme.card)
                }
                if menus.count > 2 {
                    NavigationLink(value: FoodRoute.menus) {
                        HStack {
                            Text("All menus")
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(verbatim: "\(menus.count)")
                                .font(.number(17))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            } header: {
                SectionTitle(text: "Your menus")
            }
        }

        if !recents.isEmpty {
            Section {
                ForEach(recents) { recent in
                    OneTapRow(
                        food: recent.food,
                        amount: recent.amount,
                        subtitle: nil,
                        isAdded: added.contains(recent.id),
                        open: { path.append(.food(recent.food, amount: recent.amount)) },
                        add: { log(recent.food, amount: recent.amount, key: recent.id, preferred: nil) }
                    )
                    .listRowBackground(Theme.card)
                }
            } header: {
                SectionTitle(text: "Recent")
            }
        }
    }

    @ViewBuilder private var resultSections: some View {
        if canEstimate, trimmedQuery.count >= 2, trimmedQuery.contains(where: \.isLetter) {
            Section {
                NavigationLink(value: FoodRoute.typical(trimmedQuery)) {
                    TypicalRow(words: trimmedQuery, remembered: DishMemory.dish(for: trimmedQuery, language: PhotoEstimator.language))
                }
                .listRowBackground(Theme.card)
            } header: {
                SectionTitle(text: "Typical portion")
            }
        }

        let fromMenus = MenuShelf.shared.dishes(matching: trimmedQuery)
        if !fromMenus.isEmpty {
            Section {
                ForEach(fromMenus) { found in
                    NavigationLink(value: FoodRoute.menuDish(found.menu.id, found.dish)) {
                        FoodRow(food: found.menu.food(found.dish, .regular), subtitle: [found.menu.title, found.dish.price].filter { !$0.isEmpty }.joined(separator: " · "))
                    }
                    .listRowBackground(Theme.card)
                }
            } header: {
                SectionTitle(text: "From your menus")
            }
        }

        let basics = BasicFoods.search(trimmedQuery)
        if !basics.isEmpty {
            Section {
                ForEach(basics.prefix(6)) { food in
                    NavigationLink(value: FoodRoute.food(food, amount: nil)) {
                        FoodRow(food: food)
                    }
                    .listRowBackground(Theme.card)
                }
            } header: {
                SectionTitle(text: "Basics")
            }
        }

        Section {
            if products.isEmpty {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                        Text("Searching Open Food Facts")
                    } else if failed {
                        Text("Couldn't reach Open Food Facts.")
                    } else if trimmedQuery.count < 2 {
                        Text("Keep typing to search products.")
                    } else {
                        Text("No products found.")
                    }
                }
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .listRowBackground(Theme.card)
            } else {
                ForEach(products) { food in
                    NavigationLink(value: FoodRoute.food(food, amount: nil)) {
                        FoodRow(food: food)
                    }
                    .opacity(resultsQuery == trimmedQuery ? 1 : 0.4)
                    .listRowBackground(Theme.card)
                }
            }
        } header: {
            HStack(spacing: 8) {
                SectionTitle(text: "Products")
                if isLoading && !products.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: Actions

    @MainActor private func searchProducts(_ text: String) async {
        guard text.count >= 2 else {
            products = []
            isLoading = false
            failed = false
            return
        }
        isLoading = true
        // Wait for a pause in typing. Open Food Facts allows about ten searches a minute.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        do {
            let results = try await OpenFoodFacts.shared.search(text)
            guard !Task.isCancelled else { return }
            products = results
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            products = []
            failed = true
        }
        resultsQuery = text
        isLoading = false
    }

    private func log(_ food: Food, amount: Double, key: String, preferred: Meal?) {
        let target = meal ?? preferred ?? Meal.likely()
        let entry = FoodEntry(food: food, amount: amount, meal: target, date: FoodDetailView.logDate(for: day))
        context.insert(entry)
        try? context.save()
        events.added(entry)
        Feel.play(.land)
        withAnimation(.snappy) { _ = added.insert(key) }
    }
}

/// A food you logged before, with the amount you had last time.
struct RecentFood: Identifiable {
    let food: Food
    let amount: Double
    var id: String { food.id }

    static func list(from history: [FoodEntry], limit: Int = 20) -> [RecentFood] {
        var seen: Set<String> = []
        var result: [RecentFood] = []
        for entry in history where !seen.contains(entry.foodID) {
            seen.insert(entry.foodID)
            result.append(RecentFood(food: entry.food, amount: entry.amount))
            if result.count == limit { break }
        }
        return result
    }
}

/// The first answer to anything typed: a typical portion of it, made yours in two taps. Its
/// calories show once the same words were estimated before.
private struct TypicalRow: View {
    let words: String
    let remembered: TypicalDish?

    var body: some View {
        HStack(spacing: 12) {
            if let remembered {
                FoodThumb(emoji: remembered.emoji.isEmpty ? "🍽️" : remembered.emoji, tint: FoodTint.suggested(for: remembered.emoji), size: 44)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Theme.infoText)
                    .frame(width: 44, height: 44)
                    .background(Theme.infoFill, in: RoundedRectangle(cornerRadius: FoodThumb.radius(for: 44), style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(remembered?.title ?? (words.prefix(1).uppercased() + words.dropFirst()))
                    .font(.ui(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Group {
                    if let remembered {
                        Text("Usual · \(remembered.grams.kcalText) g")
                    } else {
                        Text("Lean or rich, small or huge")
                    }
                }
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let remembered {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(remembered.kcal.kcalText)
                        .font(.number(17))
                        .foregroundStyle(Theme.ink)
                    Text("kcal")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// A menu you photographed: its photo, its name, how many dishes and when.
struct MenuRow: View {
    let menu: MenuScan

    var body: some View {
        HStack(spacing: 12) {
            FoodThumb(imageData: MenuShelf.shared.photo(of: menu.id), emoji: "📜", tint: .sand, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(menu.title)
                    .font(.ui(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text("\(menu.dishes.count) dishes")
                    Text(verbatim: " · " + menu.takenAt.formatted(.dateTime.day().month(.abbreviated)))
                }
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A food row with a + that logs it right away, for saved and recent foods.
private struct OneTapRow: View {
    let food: Food
    let amount: Double
    let subtitle: String?
    let isAdded: Bool
    let open: () -> Void
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                FoodRow(food: food, amount: amount, subtitle: subtitle)
            }
            .buttonStyle(.plain)

            Button(action: add) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(isAdded ? Theme.goodText : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isAdded ? "Added" : "Add \(food.name)")
        }
    }
}

/// A food in a list: picture, name, brand or portion, calories for that portion.
struct FoodRow: View {
    let food: Food
    var amount: Double? = nil
    var subtitle: String? = nil

    private var shownAmount: Double { amount ?? food.defaultAmount }

    var body: some View {
        HStack(spacing: 12) {
            FoodThumb(food: food, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.ui(17))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(food.nutrients(for: shownAmount).kcal.kcalText)
                    .font(.number(17))
                    .foregroundStyle(Theme.ink)
                Text("kcal")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    /// "Danone · 120 g" for a product, "1 medium · 118 g" for a basic, your line for a saved food.
    private var detail: String {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        if let brand = food.brand, !brand.isEmpty { return "\(brand) · \(food.unit.format(shownAmount))" }
        return food.portionText(for: shownAmount)
    }
}

/// A list section header, the way iOS draws them: small, in capitals, secondary.
struct SectionTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.ui(13))
            .foregroundStyle(Theme.secondary)
            .textCase(.uppercase)
    }
}

#if DEBUG
#Preview {
    AddFoodView()
        .modelContainer(DemoData.container())
        .environment(LogEvents())
}
#endif
