import SwiftUI
import SwiftData
import UIKit

/// What a quick add starts from, for example a scanned barcode the database does not know.
struct QuickAddDraft: Identifiable {
    let id = UUID()
    var name = ""
    var barcode: String? = nil
}

/// For food with no label: type the calories, and the macros if you know them.
struct QuickAddView: View {
    var draft = QuickAddDraft()
    var day: Date = .now
    /// The meal to add to, when you came from a meal's menu.
    var meal: Meal? = nil
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(LogEvents.self) private var events
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var selectedMeal = Meal.likely()
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name, kcal, protein, carbs, fat
    }

    private var kcalValue: Double? { Self.number(kcal) }

    var body: some View {
        List {
            Section {
                TextField("What was it?", text: $name)
                    .font(.ui(17))
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .kcal }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0", text: $kcal)
                        .keyboardType(.numberPad)
                        .font(.number(40))
                        .focused($focus, equals: .kcal)
                    Text("kcal")
                        .font(.ui(17))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .listRowBackground(Theme.card)

            Section {
                macroField(.protein, text: $protein, field: .protein)
                macroField(.carbs, text: $carbs, field: .carbs)
                macroField(.fat, text: $fat, field: .fat)
            } header: {
                SectionTitle(text: "Macros, if you know them")
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.page.ignoresSafeArea())
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear {
            if name.isEmpty { name = draft.name }
            if let meal { selectedMeal = meal }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .kcal }
        }
    }

    private func macroField(_ macro: Macro, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 10) {
            MacroIcon(macro: macro, size: 28)
            Text(macro.title)
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.number(17))
                .frame(maxWidth: 90)
                .focused($focus, equals: field)
            Text("g")
                .font(.ui(17))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Meal", selection: $selectedMeal) {
                    ForEach(Meal.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                MealMenuLabel(title: selectedMeal.title)
            }
            .accessibilityLabel("Meal: \(selectedMeal.title)")

            Button("Add", action: save)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(kcalValue == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.page.ignoresSafeArea())
    }

    private func save() {
        guard let kcalValue else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = Food(
            id: "manual:\(UUID().uuidString)",
            name: trimmed.isEmpty ? String(localized: "Quick add") : trimmed,
            barcode: draft.barcode,
            emoji: "🍽️",
            source: .manual,
            unit: .serving,
            per: 1,
            nutrients: Nutrients(
                kcal: kcalValue,
                protein: Self.number(protein) ?? 0,
                carbs: Self.number(carbs) ?? 0,
                fat: Self.number(fat) ?? 0
            )
        )
        context.insert(FoodEntry(food: food, amount: 1, meal: selectedMeal, date: FoodDetailView.logDate(for: day)))
        try? context.save()
        events.added(food, amount: 1, meal: selectedMeal)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone()
    }

    private static func number(_ text: String) -> Double? {
        FoodDetailView.parse(text)
    }
}
