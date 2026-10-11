import SwiftUI

/// "Your day": each meal at the time you ate it, its calories, and its foods as tiles. Tap a
/// tile to change it; press and hold for more.
struct DayTimeline: View {
    let entries: [FoodEntry]
    let onSelect: (FoodEntry) -> Void
    let onSave: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void
    let onAddHere: (Meal) -> Void
    let onSaveMeal: (Meal, [FoodEntry]) -> Void

    /// Meals in the order you ate them.
    private var meals: [(meal: Meal, entries: [FoodEntry])] {
        Meal.allCases
            .compactMap { meal -> (meal: Meal, entries: [FoodEntry])? in
                let items = entries.filter { $0.meal == meal }.sorted { $0.date < $1.date }
                return items.isEmpty ? nil : (meal: meal, entries: items)
            }
            .sorted { ($0.entries.first?.date ?? .distantPast) < ($1.entries.first?.date ?? .distantPast) }
    }

    var body: some View {
        let meals = meals
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(meals.enumerated()), id: \.element.meal) { index, item in
                MealMoment(
                    meal: item.meal,
                    entries: item.entries,
                    isLast: index == meals.count - 1,
                    onSelect: onSelect,
                    onSave: onSave,
                    onDelete: onDelete,
                    onAddHere: { onAddHere(item.meal) },
                    onSaveMeal: { onSaveMeal(item.meal, item.entries) }
                )
                .padding(.top, index == 0 ? 0 : 14)
            }
        }
    }
}

/// One meal on the timeline: the time on the left, the name and calories, then the tiles.
private struct MealMoment: View {
    let meal: Meal
    let entries: [FoodEntry]
    let isLast: Bool
    let onSelect: (FoodEntry) -> Void
    let onSave: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void
    let onAddHere: () -> Void
    let onSaveMeal: () -> Void

    private var total: Double { entries.reduce(0) { $0 + $1.totals.kcal } }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // The time the way the phone writes it: "8:10 AM", "16:10".
            Text(entries.first?.date.formatted(date: .omitted, time: .shortened) ?? "")
                .font(.ui(13))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 54, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.title)
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text("\(total.kcalText) kcal")
                        .font(.ui(14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Add food here", systemImage: "plus", action: onAddHere)
                    Button("Save meal to shelf", systemImage: "bookmark", action: onSaveMeal)
                }
                .accessibilityElement(children: .combine)

                FlowLayout(spacing: 6) {
                    ForEach(entries) { entry in
                        Button { onSelect(entry) } label: {
                            FoodThumb(food: entry.food, size: 76)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                        .contextMenu {
                            Button("Edit amount", systemImage: "slider.horizontal.3") { onSelect(entry) }
                            Button("Save to shelf", systemImage: "bookmark") { onSave(entry) }
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                        }
                        .accessibilityLabel("\(entry.name), \(entry.food.unit.format(entry.amount)), \(entry.totals.kcal.kcalText) calories")
                    }
                }
            }
            .padding(.bottom, 14)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                }
            }
        }
    }
}
