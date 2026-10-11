import SwiftUI
import SwiftData
import UIKit

/// One food, before you log it or while you edit it. The picture and name, the calories for
/// your amount with its macros, the amount, a few quality facts, and the full label on demand.
struct FoodDetailView: View {
    let food: Food
    let entry: FoodEntry?
    let day: Date
    let onDone: () -> Void
    let onDelete: (FoodEntry) -> Void

    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query private var savedFoods: [SavedFood]
    @State private var amount: Double
    @State private var amountText: String
    @State private var meal: Meal
    @State private var showFacts = false
    @State private var saves = 0
    @FocusState private var amountFocused: Bool

    init(
        food: Food,
        entry: FoodEntry? = nil,
        amount: Double? = nil,
        day: Date = .now,
        meal: Meal? = nil,
        onDone: @escaping () -> Void = {},
        onDelete: @escaping (FoodEntry) -> Void = { _ in }
    ) {
        self.food = food
        self.entry = entry
        self.day = day
        self.onDone = onDone
        self.onDelete = onDelete
        let start = entry?.amount ?? amount ?? food.defaultAmount
        _amount = State(initialValue: start)
        _amountText = State(initialValue: Self.format(start))
        _meal = State(initialValue: entry?.meal ?? meal ?? Meal.likely())
    }

    private var totals: Nutrients { food.nutrients(for: amount) }
    private var isSaved: Bool { savedFoods.contains { $0.foodID == food.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                numbers
                amountCard
                quality
                facts
                sourceLink
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.page.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
            if let entry {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { onDelete(entry) } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete from log")
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: amountText) { _, text in
            amount = Self.parse(text) ?? 0
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FoodThumb(food: food, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name)
                    .font(.ui(26, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = food.brand {
                    if let url = food.sourceURL {
                        // The brand links to the product's page in its database.
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Text(brand)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .font(.ui(15))
                        }
                    } else {
                        Text(brand)
                            .font(.ui(15))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }

    /// The calories for your amount as the headline, its three macros in a row under it.
    private var numbers: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.energy)
                Text(totals.kcal.kcalText)
                    .font(.number(50))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: totals.kcal.rounded()))
                Text("kcal")
                    .font(.ui(17))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                ForEach(Macro.allCases, id: \.self) { macro in
                    MacroPill(macro: macro, grams: macro.grams(in: totals))
                }
            }
            MacroSplitBar(nutrients: totals)
        }
        .animation(.snappy, value: totals.kcal.rounded())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(totals.kcal.kcalText) calories. Protein \(totals.protein.gramsText) grams, carbs \(totals.carbs.gramsText) grams, fat \(totals.fat.gramsText) grams."
        )
    }

    private var amountCard: some View {
        Card(padding: 16) {
            VStack(spacing: 14) {
                HStack {
                    StepButton(systemImage: "minus", label: "Less") { step(-food.unit.step) }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .multilineTextAlignment(.trailing)
                            .font(.number(36))
                            .foregroundStyle(Theme.ink)
                            .fixedSize()
                            .accessibilityLabel("Amount")
                        Text(unitLabel)
                            .font(.ui(17))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    StepButton(systemImage: "plus", label: "More") { step(food.unit.step) }
                }

                if !food.portions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(food.portions, id: \.self) { portion in
                                Button { set(portion.amount) } label: {
                                    Text(chipTitle(portion))
                                }
                                .buttonStyle(ChipButtonStyle(isSelected: abs(amount - portion.amount) < 0.01))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var quality: some View {
        let highlights = food.highlights
        let processing = food.processingLabel
        if food.nutriScore != nil || processing != nil || !highlights.isEmpty {
            FlowLayout(spacing: 8) {
                if let grade = food.nutriScore {
                    NutriScoreBadge(grade: grade)
                }
                if let processing {
                    TintChip(title: processing.title, style: processing.kind?.chipStyle ?? .neutral)
                }
                ForEach(highlights) { highlight in
                    TintChip(title: highlight.title, style: highlight.kind.chipStyle)
                }
            }
        }
    }

    private var facts: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.snappy) { showFacts.toggle() }
                } label: {
                    HStack {
                        Text("Nutrition facts")
                            .font(.ui(17, .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .rotationEffect(.degrees(showFacts ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showFacts {
                    NutritionTable(food: food, amount: amount)
                        .padding(.top, 16)
                    if !food.allergens.isEmpty {
                        Text("Contains \(food.allergens.joined(separator: ", ").lowercased()).")
                            .font(.ui(15))
                            .foregroundStyle(Theme.secondary)
                            .padding(.top, 14)
                    }
                }
            }
        }
    }

    @ViewBuilder private var sourceLink: some View {
        if let url = food.sourceURL {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text("Data from \(food.sourceName)")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
            }
        } else if food.source == .ai {
            Text("Estimated by Claude from your photo.")
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { meal in
                        Text(meal.title).tag(meal)
                    }
                }
            } label: {
                MealMenuLabel(title: meal.title)
            }
            .accessibilityLabel("Meal: \(meal.title)")

            Button(entry == nil ? "Add" : "Save", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(amount <= 0)

            BookmarkButton(isSaved: isSaved, action: toggleSaved)
                .sensoryFeedback(.success, trigger: saves)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.page.ignoresSafeArea())
    }

    // MARK: Amount

    private var unitLabel: String {
        food.unit == .serving ? (amount == 1 ? "serving" : "servings") : food.unit.symbol
    }

    private func chipTitle(_ portion: Portion) -> String {
        let measure = food.unit.format(portion.amount)
        return portion.label == measure ? measure : "\(portion.label) · \(measure)"
    }

    private func set(_ value: Double) {
        amount = value
        amountText = Self.format(value)
        amountFocused = false
    }

    private func step(_ delta: Double) {
        // Snap to the step grid, so 118 g goes to 120 g, then 130 g.
        let stepped = delta > 0
            ? (amount / delta).rounded(.down) * delta + delta
            : (amount / -delta).rounded(.up) * -delta + delta
        set(max(stepped, abs(delta)))
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// A typed or pasted amount, or nil when it is not a sane positive number.
    static func parse(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
              value.isFinite, value >= 0, value < 100_000 else { return nil }
        return value
    }

    // MARK: Saving

    private func save() {
        if let entry {
            entry.amount = amount
            entry.meal = meal
            try? context.save()
        } else {
            context.insert(FoodEntry(food: food, amount: amount, meal: meal, date: Self.logDate(for: day)))
            try? context.save()
            events.added(food, amount: amount, meal: meal)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone()
    }

    /// Bookmark keeps the food on your shelf with this amount; tapping again takes it off.
    private func toggleSaved() {
        if let existing = savedFoods.first(where: { $0.foodID == food.id }) {
            context.delete(existing)
        } else {
            let next = (savedFoods.map(\.sortIndex).max() ?? 0) + 1
            context.insert(SavedFood(food: food, amount: amount, sortIndex: next))
        }
        try? context.save()
        saves += 1
    }

    /// Now for today. For another day, the same time of day on that day.
    static func logDate(for day: Date, calendar: Calendar = .current) -> Date {
        if calendar.isDateInToday(day) { return .now }
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        FoodDetailView(food: DemoData.skyr)
    }
    .modelContainer(DemoData.container())
    .environment(LogEvents())
}
#endif
