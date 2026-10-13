import SwiftData
import SwiftUI

/// The first minute's sheet over the real Today, so the number and the ring stay in view: the
/// first bite at half height, then the goal at full height. A food for the hour is one tap and
/// one Add; scanning or searching closes the sheet and the goal comes once that food is in.
struct FirstRunSheet: View {
    enum Step {
        case firstBite
        case goal
    }

    let startAt: Step
    let day: Date
    /// Scan or Search was chosen: the sheet closes and Today opens it.
    let onScan: () -> Void
    let onSearch: () -> Void
    /// The sheet moved on to the goal.
    let onGoal: () -> Void
    /// The goal is set, or kept: the first run is over.
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @AppStorage("firstRun.startsOn") private var startsOn = 0.0
    @State private var step: Step
    @State private var detent: PresentationDetent

    init(
        startAt: Step,
        day: Date,
        onScan: @escaping () -> Void,
        onSearch: @escaping () -> Void,
        onGoal: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.startAt = startAt
        self.day = day
        self.onScan = onScan
        self.onSearch = onSearch
        self.onGoal = onGoal
        self.onFinished = onFinished
        // The sheet opens on its step at once, never on the first bite for a frame.
        _step = State(initialValue: startAt)
        _detent = State(initialValue: startAt == .goal ? .large : .medium)
    }

    var body: some View {
        Group {
            switch step {
            case .firstBite:
                FirstBiteStep(day: day, onAdd: add, onScan: onScan, onSearch: onSearch, onSkip: skip)
                    .transition(.opacity)
            case .goal:
                GoalStep(onDone: onFinished)
                    .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: step)
        .presentationDetents(step == .firstBite ? [.medium, .large] : [.large], selection: $detent)
        .presentationBackgroundInteraction(.disabled)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
    }

    /// The first food goes in like any other, with its toast and Undo, and the ring lights
    /// behind the sheet; then the sheet grows into the goal.
    private func add(_ food: Food, amount: Double) {
        let entry = FoodEntry(food: food, amount: amount, meal: Meal.likely(), date: FoodDetailView.logDate(for: day))
        withAnimation(Motion.settle) {
            context.insert(entry)
            try? context.save()
        }
        events.added(entry)
        Feel.play(.land)
        Task {
            // Long enough to see the ring light up behind the sheet.
            try? await Task.sleep(for: .milliseconds(900))
            goToGoal()
        }
    }

    /// "Nothing yet", or late in the evening "Start tomorrow".
    private func skip() {
        if HourFoods.isLate(.now) {
            let calendar = Calendar.current
            startsOn = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))?.timeIntervalSince1970 ?? 0
        }
        goToGoal()
    }

    private func goToGoal() {
        onGoal()
        withAnimation(Motion.settle) {
            step = .goal
            detent = .large
        }
    }
}

/// "What did you have this morning?": eight foods for the hour, then Scan and Search.
private struct FirstBiteStep: View {
    let day: Date
    let onAdd: (Food, Double) -> Void
    let onScan: () -> Void
    let onSearch: () -> Void
    let onSkip: () -> Void

    @State private var picked: Food?
    @State private var count = 1

    private var foods: [Food] {
        let ids = HourFoods.foodIDs(at: .now)
        let basics = Dictionary(BasicFoods.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { basics[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(HourFoods.question(at: .now))
                    .font(.ui(22, .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Tap it, scan it or search. You can change it later.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4), spacing: 14) {
                    ForEach(foods) { food in
                        FoodChoice(food: food, isPicked: picked?.id == food.id) {
                            withAnimation(Motion.respond) {
                                picked = picked?.id == food.id ? nil : food
                                count = 1
                            }
                        }
                    }
                }
                .padding(.top, 18)

                if let picked {
                    portion(picked)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else {
                    HStack(spacing: 10) {
                        Button(action: onScan) {
                            Label("Scan a barcode", systemImage: "barcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        Button(action: onSearch) {
                            Label("Search", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(SoftButtonStyle(height: 46))
                    .padding(.top, 20)
                    .transition(.opacity)

                    Button(HourFoods.isLate(.now) ? LocalizedStringKey("Start tomorrow") : LocalizedStringKey("Nothing yet"), action: onSkip)
                        .font(.ui(16))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The picked food at its usual portion, − and + by whole portions, then Add.
    private func portion(_ food: Food) -> some View {
        let step = food.defaultAmount
        let amount = step * Double(count)
        let kcal = food.nutrients(for: amount).kcal
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                FoodThumb(food: food, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                        .font(.ui(16, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("\(food.portionText(for: amount)) · \(kcal.kcalText) kcal")
                        .font(.ui(14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText(value: kcal))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StepButton(systemImage: "minus", label: "Less", value: Double(count)) {
                    withAnimation(Motion.respond) { count = max(count - 1, 1) }
                }
                .disabled(count <= 1)
                StepButton(systemImage: "plus", label: "More", value: Double(count)) {
                    withAnimation(Motion.respond) { count = min(count + 1, 9) }
                }
            }
            .padding(10)
            .background(Theme.page, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button("Add to \(Meal.likely().title)") {
                onAdd(food, amount)
            }
            .buttonStyle(PrimaryButtonStyle(height: 52))
        }
    }
}

/// One food for the hour: its tile, its name, its calories for the usual portion.
private struct FoodChoice: View {
    let food: Food
    let isPicked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                FoodThumb(food: food, size: 64)
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: FoodThumb.radius(for: 64) + 3, style: .continuous)
                            .strokeBorder(Theme.ink, lineWidth: isPicked ? 2 : 0)
                    }
                VStack(spacing: 1) {
                    Text(food.name)
                        .font(.ui(13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(food.nutrients(for: food.defaultAmount).kcal.kcalText) kcal")
                        .font(.ui(12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .sensoryFeedback(Feel.tick, trigger: isPicked) { _, new in new }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
