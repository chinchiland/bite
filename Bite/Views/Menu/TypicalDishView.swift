import SwiftUI
import SwiftData

/// A dish as it is usually served, made yours in two taps: how rich it was, how big it was.
/// Words typed in search get their estimate on the way in (or at once, when the same words were
/// asked before); a dish on one of your menus already has one.
struct TypicalDishView: View {
    enum Origin: Hashable {
        /// Words typed in search.
        case typed(String)
        /// A dish on one of your menus.
        case menu(UUID, MenuScan.Dish)
    }

    let origin: Origin
    let day: Date
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @Query(sort: \SavedFood.sortIndex) private var saved: [SavedFood]
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.split") private var splitRaw = MacroSplit.balanced.rawValue

    @State private var phase: Phase
    @State private var dish: TypicalDish?
    @State private var richness: TypicalDish.Richness = .regular
    @State private var size: TypicalDish.Size = .regular
    @State private var meal: Meal
    @State private var time: Date
    @State private var place: MealPlace?
    @State private var heroGone = false
    @State private var attempt = 0
    @State private var saves = 0

    enum Phase: Equatable {
        case working
        case ready
        case notFood
        case trouble(EstimateTrouble)
    }

    init(origin: Origin, day: Date, meal: Meal? = nil, onDone: @escaping () -> Void) {
        self.origin = origin
        self.day = day
        self.onDone = onDone
        _meal = State(initialValue: meal ?? Meal.likely())
        _time = State(initialValue: FoodDetailView.logDate(for: day))
        switch origin {
        case .typed(let words):
            let remembered = DishMemory.dish(for: words, language: PhotoEstimator.language)
            _dish = State(initialValue: remembered)
            _phase = State(initialValue: remembered == nil ? .working : .ready)
        case .menu(let id, let item):
            _dish = State(initialValue: item.dish)
            _phase = State(initialValue: .ready)
            _place = State(initialValue: MenuShelf.shared.menu(id)?.place)
        }
    }

    private var targets: MacroTargets {
        MacroTargets(kcal: Double(goalKcal), split: MacroSplit(rawValue: splitRaw) ?? .balanced)
    }

    /// The food it logs as: the dish at the richness you picked.
    private func asFood(_ dish: TypicalDish) -> Food {
        switch origin {
        case .typed:
            return dish.food(richness, id: TypicalDish.typedID(dish.title))
        case .menu(let id, let item):
            guard let menu = MenuShelf.shared.menu(id) else { return dish.food(richness, id: TypicalDish.typedID(dish.title)) }
            return menu.food(item, richness)
        }
    }

    /// What it reads as before the estimate is in: the words, as typed.
    private var placeholderTitle: String {
        switch origin {
        case .typed(let words):
            let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        case .menu(_, let item):
            return item.name
        }
    }

    private var heroFood: Food {
        if let dish { return asFood(dish) }
        return Food(id: "typical:pending", name: placeholderTitle, emoji: "🍽️", source: .typical, nutrients: .zero)
    }

    private var isSaved: Bool {
        guard let dish else { return false }
        let id = asFood(dish).id
        return saved.contains { $0.foodID == id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FoodHero(food: heroFood, height: 280)
                    .opacity(phase == .working ? 0.55 : 1)
                    .overlay {
                        if phase == .working { ScanBand() }
                    }
                    .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 120 } action: { heroGone = $0 }
                sheet
                    .padding(.top, -32)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.card.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .ready, dish != nil { actionBar }
        }
        .modifier(HeroBar(heroGone: heroGone, title: dish?.title ?? placeholderTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if phase == .ready, dish != nil {
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
        }
        .sensoryFeedback(Feel.tick, trigger: richness)
        .sensoryFeedback(Feel.tick, trigger: size)
        .sensoryFeedback(trigger: phase) { _, new in
            if new == .ready { return Feel.reached }
            if case .trouble(.failed(_)) = new { return Feel.failed }
            return nil
        }
        .task(id: attempt) { await estimate() }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch phase {
            case .working:
                working
            case .notFood:
                notFood
            case .trouble(let trouble):
                EstimateGate(trouble: trouble, retry: { attempt += 1 }, close: { dismiss() })
            case .ready:
                if let dish {
                    ready(dish)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .background(
            Theme.card,
            in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
        )
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(placeholderTitle)
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ProgressView()
                Text("Estimating a typical portion")
                    .font(.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
            }
            ForEach([220, 170, 250], id: \.self) { width in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.track)
                    .frame(width: CGFloat(width), height: 14)
            }
            Text("Usually a few seconds.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var notFood: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("That doesn't sound like a dish")
                .font(.ui(22, .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Try other words, or pick a product from the results.")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Back") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.top, 4)
        }
    }

    @ViewBuilder private func ready(_ dish: TypicalDish) -> some View {
        let food = asFood(dish)
        let grams = dish.grams(size)
        let totals = food.nutrients(for: grams)
        VStack(alignment: .leading, spacing: 0) {
            Text(dish.title)
                .font(.ui(27, .medium))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
                .padding(.top, 2)

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

            Text("How rich was it?")
                .font(.ui(17, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 24)
            HStack(spacing: 8) {
                ForEach(TypicalDish.Richness.allCases, id: \.self) { option in
                    ChoiceTile(title: option.title, isSelected: richness == option) {
                        withAnimation(Motion.respond) { richness = option }
                    } glyph: { color in
                        HStack(spacing: 1) {
                            ForEach(0..<option.drops, id: \.self) { _ in
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundStyle(color)
                    }
                }
            }
            .padding(.top, 10)
            Text(richness.hint)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)
                .contentTransition(.opacity)

            Text("How big was it?")
                .font(.ui(17, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
            HStack(spacing: 8) {
                ForEach(TypicalDish.Size.allCases, id: \.self) { option in
                    ChoiceTile(title: option.title, isSelected: size == option) {
                        withAnimation(Motion.respond) { size = option }
                    } glyph: { color in
                        Circle()
                            .fill(color)
                            .frame(width: 13 * option.factor, height: 13 * option.factor)
                    }
                }
            }
            .padding(.top, 10)
            Text("About \(grams.kcalText) g")
                .font(.ui(13))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .padding(.top, 8)

            HStack {
                Text("Time")
                    .font(.ui(17))
                    .foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.vertical, 4)
            .padding(.top, 20)
            PlaceRow(place: $place)
                .padding(.top, 2)

            Text(note)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
        }
    }

    /// Where it is from: the menu's house and price, or what it is.
    private var subtitle: String {
        switch origin {
        case .typed:
            return tr("A typical portion")
        case .menu(let id, let item):
            let house = MenuShelf.shared.menu(id)?.title ?? ""
            return [house, item.price].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private var note: LocalizedStringKey {
        switch origin {
        case .typed: "Estimated from its name, as it is usually served."
        case .menu: "Estimated from the menu, for the portion a place like this usually serves."
        }
    }

    private var addTitle: LocalizedStringKey {
        Calendar.current.isDateInToday(day) ? "Add to today" : "Add"
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                MealMenuLabel(title: meal.title)
            }
            .accessibilityLabel("Meal: \(meal.title)")

            Button(action: add) {
                Text(addTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.card.ignoresSafeArea())
    }

    // MARK: Actions

    private func estimate() async {
        guard case .typed(let words) = origin, dish == nil else { return }
        phase = .working
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(Motion.settle) {
                dish = DemoData.typicalDish(for: words)
                phase = .ready
            }
            return
        }
        #endif
        do {
            let answer = try await PhotoEstimator.dish(named: words, language: PhotoEstimator.language)
            DishMemory.remember(answer, for: words, language: PhotoEstimator.language)
            withAnimation(Motion.settle) {
                dish = answer
                phase = .ready
            }
        } catch TypicalDish.Failure.notFood {
            withAnimation(Motion.settle) { phase = .notFood }
        } catch {
            withAnimation(Motion.settle) { phase = .trouble(EstimateTrouble(error)) }
        }
    }

    private func add() {
        guard let dish else { return }
        let entry = FoodEntry(food: asFood(dish), amount: dish.grams(size), meal: meal, date: time, place: place)
        context.insert(entry)
        try? context.save()
        events.added(entry)
        Feel.play(.land)
        onDone()
    }

    /// Bookmark keeps this richness at this size on your shelf; tapping again takes it off.
    private func toggleSaved() {
        guard let dish else { return }
        let food = asFood(dish)
        if let existing = saved.first(where: { $0.foodID == food.id }) {
            context.delete(existing)
        } else {
            let next = (saved.map(\.sortIndex).max() ?? 0) + 1
            context.insert(SavedFood(food: food, amount: dish.grams(size), sortIndex: next))
        }
        try? context.save()
        saves += 1
    }
}

/// One answer among a few, as equal tiles: a small picture over a word, ink when chosen.
private struct ChoiceTile<Glyph: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let glyph: (Color) -> Glyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                glyph(isSelected ? Theme.page : Theme.ink)
                    .frame(height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.ui(14, .medium))
                    .foregroundStyle(isSelected ? Theme.page : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(isSelected ? Theme.ink : Theme.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension TypicalDish.Richness {
    /// One drop of oil for lean, three for rich.
    var drops: Int {
        switch self {
        case .lean: 1
        case .regular: 2
        case .rich: 3
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .lean: "Light on oil and sauce"
        case .regular: "Made the usual way"
        case .rich: "Extra oil, sauce or cheese"
        }
    }
}
