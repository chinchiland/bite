import SwiftUI
import SwiftData
import TipKit
import UIKit

/// One food, before you log it or while you edit it. Its picture as the hero, then on a white
/// sheet: the name, a few quality facts, the macros and the ring for your amount, the amount,
/// and the full label on demand.
struct FoodDetailView: View {
    let food: Food
    let entry: FoodEntry?
    let day: Date
    let onDone: () -> Void
    let onDelete: (FoodEntry) -> Void

    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query private var savedFoods: [SavedFood]
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue
    @State private var amount: Double
    /// The photo has scrolled up under the bar: the bar gets its background back.
    @State private var heroGone = false
    @State private var amountText: String
    @State private var meal: Meal
    /// When you ate it: now, or the time on the entry. Logging late? Move it back.
    @State private var time: Date
    /// Where you ate it: picked from the places around you, or none.
    @State private var place: MealPlace?
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
        _time = State(initialValue: entry?.date ?? Self.logDate(for: day))
        _place = State(initialValue: entry?.place)
    }

    private var totals: Nutrients { food.nutrients(for: amount) }
    private var isSaved: Bool { savedFoods.contains { $0.foodID == food.id } }
    private var targets: MacroTargets {
        MacroTargets(kcal: Double(goalKcal), split: MacroSplit(rawValue: splitRaw) ?? .balanced)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FoodHero(food: food, height: 330)
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 120 } action: { heroGone = $0 }
                sheet
                    .padding(.top, -32)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(edges: .top)
        .background(Theme.card.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .modifier(HeroBar(heroGone: heroGone))
        .navigationBarTitleDisplayMode(.inline)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleSaved) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: saves)
                }
                .sensoryFeedback(trigger: saves) { _, _ in isSaved ? Feel.click : nil }
                .accessibilityLabel(isSaved ? "Saved to your shelf" : "Save to your shelf")
            }
        }
        .onChange(of: amountText) { _, text in
            amount = Self.parse(text) ?? 0
        }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(food.name)
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            brand
                .padding(.top, 2)
            quality
                .padding(.top, 14)
            MacroBlock(
                nutrients: totals,
                targets: targets,
                ring: DottedRing.food(totals),
                number: totals.kcal,
                unit: "kcal",
                showsTarget: false,
                surface: Theme.card
            )
            .padding(.top, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(totals.kcal.kcalText) calories. Protein \(totals.protein.gramsText) grams, carbs \(totals.carbs.gramsText) grams, fat \(totals.fat.gramsText) grams."
            )
            amountPicker
                .padding(.top, 22)
            timeRow
                .padding(.top, 12)
            PlaceRow(place: $place)
                .padding(.top, 2)
            facts
                .padding(.top, 22)
            sourceLink
                .padding(.top, 16)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.card,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
    }

    @ViewBuilder private var brand: some View {
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
                    .foregroundStyle(Theme.link)
                }
            } else {
                Text(brand)
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder private var quality: some View {
        let highlights = food.highlights
        let processing = food.processingLabel
        if food.nutriScore != nil || processing != nil || !highlights.isEmpty {
            FlowLayout(spacing: 7) {
                if let grade = food.nutriScore {
                    NutriScoreChip(grade: grade)
                }
                if let processing {
                    let style = processing.kind?.chipStyle ?? .neutral
                    TintChip(title: processing.title, style: style, systemImage: processing.kind?.chipSymbol)
                }
                ForEach(highlights) { highlight in
                    TintChip(title: highlight.title, style: highlight.kind.chipStyle, systemImage: highlight.kind.chipSymbol)
                }
            }
        }
    }

    private var amountPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !food.portions.isEmpty {
                Rail(spacing: 8, alignment: .center) {
                    ForEach(food.portions, id: \.self) { portion in
                        Button { set(portion.amount) } label: {
                            Text(chipTitle(portion))
                        }
                        .buttonStyle(ChipButtonStyle(isSelected: abs(amount - portion.amount) < 0.01))
                    }
                }
            }
            HStack {
                StepButton(systemImage: "minus", label: "Less", value: amount) { step(-food.unit.step) }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .multilineTextAlignment(.trailing)
                        .font(.number(32))
                        .foregroundStyle(Theme.ink)
                        .fixedSize()
                        .accessibilityLabel("Amount")
                    Text(unitLabel)
                        .font(.ui(17))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                StepButton(systemImage: "plus", label: "More", value: amount) { step(food.unit.step) }
            }
            .padding(10)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.insetRadius, style: .continuous))
        }
    }

    /// The time, set to now on its own; a tap on it opens Apple's compact time picker.
    private var timeRow: some View {
        HStack {
            Text("Time")
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var facts: some View {
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
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }

            if showFacts {
                NutritionTable(food: food, amount: amount)
                    .padding(.top, 4)
                if !food.allergens.isEmpty {
                    Text("Contains \(food.allergens.joined(separator: ", ").lowercased()).")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 14)
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
        } else if food.source == .community {
            Text("Calories from the estimates people shared.")
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

            Button(action: save) {
                Text(actionTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(amount <= 0)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.card.ignoresSafeArea())
    }

    private var actionTitle: LocalizedStringKey {
        if entry != nil { return "Save" }
        return Calendar.current.isDateInToday(day) ? "Add to today" : "Add"
    }

    // MARK: Amount

    private var unitLabel: String {
        food.unit == .serving ? (amount == 1 ? tr("serving") : tr("servings")) : food.unit.symbol
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
            if abs(entry.date.timeIntervalSince(time)) >= 600 { MealTimeTip.movedTheLongWay = true }
            entry.amount = amount
            entry.meal = meal
            entry.date = time
            entry.place = place
            try? context.save()
            Feel.play(.click)
        } else {
            if loggedRecently { FoodTileTip.relogged = true }
            let added = FoodEntry(food: food, amount: amount, meal: meal, date: time, place: place)
            context.insert(added)
            try? context.save()
            events.added(added)
            Feel.play(.land)
        }
        onDone()
    }

    /// This food is already in your last two weeks: logged again by search or scan.
    private var loggedRecently: Bool {
        let id = food.id
        guard let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) else { return false }
        var descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.foodID == id && $0.date >= since })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
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

/// The bar over a hero photo: clear while the photo is under it, then the system's edge effect
/// (iOS 26) or the white sheet's own color (before), so the buttons never sit on words.
struct HeroBar: ViewModifier {
    let heroGone: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .toolbarBackground(.hidden, for: .navigationBar)
                .scrollEdgeEffectHidden(!heroGone, for: .top)
        } else {
            legacy(content)
        }
        #else
        legacy(content)
        #endif
    }

    private func legacy(_ content: Content) -> some View {
        content
            .toolbarBackground(Theme.card, for: .navigationBar)
            .toolbarBackground(heroGone ? .visible : .hidden, for: .navigationBar)
    }
}

/// A food's hero: your photo filling the top, or the product standing on a soft light in its
/// tint, or its emoji, big. Pulling down stretches it.
struct FoodHero: View {
    let food: Food
    let height: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { content }
            .clipped()
            .visualEffect { content, proxy in
                let pull = max(proxy.frame(in: .scrollView).minY, 0)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let data = food.imageData, let photo = ImageTools.thumbnail(data, points: 440) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                }
        } else {
            ZStack {
                Theme.heroGradient(food.displayTint)
                if let url = food.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            if colorScheme == .dark {
                                // Multiplying onto a dark light would muddy the pack, so at
                                // night it stands on its own white card.
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(22)
                                    .blendMode(.multiply)
                                    .background(Theme.photoTile)
                                    .compositingGroup()
                                    .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                            } else {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .blendMode(.multiply)
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 220, height: 220)
                    .padding(.top, 34)
                } else {
                    Text(food.emoji ?? "🍽️")
                        .font(.system(size: 110))
                        .padding(.top, 34)
                }
            }
            .compositingGroup()
        }
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
