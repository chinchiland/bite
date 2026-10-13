import SwiftUI
import SwiftData
import UIKit

/// Where a food goes when it is not a barcode: what you had recently, basics, and search.
enum FoodRoute: Hashable {
    case food(Food, amount: Double?)
    case quickAdd
}

/// Search and add. Empty, it shows your saved foods and what you logged recently, both one tap
/// from today. Typing searches the bundled basics instantly and Open Food Facts as you pause.
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
                switch route {
                case .food(let food, let amount):
                    FoodDetailView(food: food, amount: amount, day: day, meal: meal) { dismiss() }
                case .quickAdd:
                    QuickAddView(day: day, meal: meal) { dismiss() }
                }
            }
        }
        .onAppear {
            recents = RecentFood.list(from: history)
            #if DEBUG
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
