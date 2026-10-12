import SwiftUI
import TipKit

/// "Your day": each meal at the time you ate it, its calories, and its foods as tiles. Tap a
/// tile to change it, tap the time to move the meal; press and hold for more.
struct DayTimeline: View {
    let entries: [FoodEntry]
    /// Past days offer "Add to today" where today offers "Add again".
    let isToday: Bool
    let onSelect: (FoodEntry) -> Void
    let onSave: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void
    let onAddHere: (Meal) -> Void
    let onSaveMeal: (Meal, [FoodEntry]) -> Void
    let onAddToToday: ([FoodEntry]) -> Void
    let onMoveTime: ([FoodEntry], Date) -> Void

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
                    isToday: isToday,
                    showsTip: index == 0,
                    onSelect: onSelect,
                    onSave: onSave,
                    onDelete: onDelete,
                    onAddHere: { onAddHere(item.meal) },
                    onSaveMeal: { onSaveMeal(item.meal, item.entries) },
                    onAddToToday: onAddToToday,
                    onMoveTime: { onMoveTime(item.entries, $0) }
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
    let isToday: Bool
    let showsTip: Bool
    let onSelect: (FoodEntry) -> Void
    let onSave: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void
    let onAddHere: () -> Void
    let onSaveMeal: () -> Void
    let onAddToToday: ([FoodEntry]) -> Void
    let onMoveTime: (Date) -> Void

    @State private var editingTime = false
    @State private var time = Date.now
    /// The time the wheel opened on, so closing it unturned moves nothing.
    @State private var opened = Date.now

    private var total: Double { entries.reduce(0) { $0 + $1.totals.kcal } }
    /// The time the way the phone writes it: "8:10 AM", "16:10".
    private var timeText: String { entries.first?.date.formatted(date: .omitted, time: .shortened) ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                openTimeEditor()
            } label: {
                Text(timeText)
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 54, alignment: .trailing)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $editingTime, arrowEdge: .top) {
                timeEditor
            }
            .accessibilityLabel(Text(verbatim: timeText))
            .accessibilityHint("Change when you ate this meal")

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
                    if !isToday {
                        Button("Add to today", systemImage: "arrow.uturn.forward") { onAddToToday(entries) }
                    }
                    Button("Add food here", systemImage: "plus", action: onAddHere)
                    Button("Change the time", systemImage: "clock") {
                        openTimeEditor()
                    }
                    Button("Save meal to shelf", systemImage: "bookmark", action: onSaveMeal)
                }
                .accessibilityElement(children: .combine)

                FlowLayout(spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if showsTip && index == 0 {
                            tile(entry)
                                .popoverTip(FoodTileTip(), arrowEdge: .bottom)
                        } else {
                            tile(entry)
                        }
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

    private func tile(_ entry: FoodEntry) -> some View {
        Button {
            FoodTileTip().invalidate(reason: .actionPerformed)
            onSelect(entry)
        } label: {
            FoodThumb(food: entry.food, size: 76)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .contextMenu {
            Button(isToday ? LocalizedStringKey("Add again") : LocalizedStringKey("Add to today"), systemImage: "arrow.uturn.forward") {
                onAddToToday([entry])
            }
            Button("Edit amount", systemImage: "slider.horizontal.3") { onSelect(entry) }
            Button("Save to shelf", systemImage: "bookmark") { onSave(entry) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
        }
        .accessibilityLabel("\(entry.name), \(entry.food.unit.format(entry.amount)), \(entry.totals.kcal.kcalText) calories")
    }

    /// A wheel in a small popover beside the time: spin it and the meal moves when it closes.
    private var timeEditor: some View {
        VStack(spacing: 12) {
            Text("When you ate")
                .font(.ui(15, .semibold))
                .foregroundStyle(Theme.ink)
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            Button("Done") { editingTime = false }
                .buttonStyle(PrimaryButtonStyle(height: 44))
        }
        .padding(16)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
        .onDisappear {
            let calendar = Calendar.current
            if calendar.dateComponents([.hour, .minute], from: time) != calendar.dateComponents([.hour, .minute], from: opened) {
                onMoveTime(time)
            }
        }
    }

    private func openTimeEditor() {
        time = entries.first?.date ?? .now
        opened = time
        editingTime = true
    }
}
