import SwiftUI

/// One meal: its name and total, then each food on its own soft tint.
struct MealCard: View {
    let meal: Meal
    let entries: [FoodEntry]
    let onSelect: (FoodEntry) -> Void
    let onSave: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void
    let onAddHere: () -> Void
    let onSaveMeal: () -> Void

    private var total: Double { entries.reduce(0) { $0 + $1.totals.kcal } }

    var body: some View {
        Card(padding: 12) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(meal.title)
                            .font(.ui(20, .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(total.kcalText) kcal")
                            .font(.ui(15))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Add food here", systemImage: "plus", action: onAddHere)
                        Button("Save meal to shelf", systemImage: "bookmark", action: onSaveMeal)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                            .background(Theme.fill, in: Circle())
                    }
                    .accessibilityLabel("\(meal.title) options")
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 2)

                ForEach(entries) { entry in
                    Button { onSelect(entry) } label: {
                        LogRow(entry: entry)
                    }
                    .buttonStyle(PressableStyle(scale: 0.98))
                    .contextMenu {
                        Button("Edit amount", systemImage: "slider.horizontal.3") { onSelect(entry) }
                        Button("Save to shelf", systemImage: "bookmark") { onSave(entry) }
                        Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                    }
                }
            }
        }
    }
}

/// A logged food on its own soft tint: picture, name and amount, calories, macros.
struct LogRow: View {
    let entry: FoodEntry

    var body: some View {
        let food = entry.food
        let totals = entry.totals
        HStack(spacing: 12) {
            FoodThumb(food: food, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.name)
                        .font(.ui(17, .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(food.unit.format(entry.amount))
                        .font(.ui(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .layoutPriority(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(totals.kcal.kcalText)
                        .font(.number(17))
                        .foregroundStyle(Theme.ink)
                    Text("kcal")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 8)
                    MacroMinis(nutrients: totals)
                }
            }
        }
        .padding(10)
        .background(Theme.tint(food.displayTint).opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(food.unit.format(entry.amount)), \(totals.kcal.kcalText) calories")
    }
}
