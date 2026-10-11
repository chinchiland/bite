import SwiftUI

/// A daily goal from your body and your week, with the Mifflin-St Jeor equation.
/// Also the first screen of the app.
struct GoalCalculatorView: View {
    var isWelcome = false
    var onUse: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("body.sex") private var sexRaw = Sex.female.rawValue
    @AppStorage("body.age") private var age = 30
    @AppStorage("body.height") private var height = 170
    @AppStorage("body.weight") private var weight = 70.0
    @AppStorage("body.activity") private var activityRaw = Activity.light.rawValue
    @AppStorage("body.goal") private var goalRaw = WeightGoal.maintain.rawValue
    @State private var ageText = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @FocusState private var editing: Bool

    private var result: Int {
        GoalCalculator.dailyCalories(
            sex: Sex(rawValue: sexRaw) ?? .female,
            age: age,
            heightCm: Double(height),
            weightKg: weight,
            activity: Activity(rawValue: activityRaw) ?? .light,
            goal: WeightGoal(rawValue: goalRaw) ?? .maintain
        )
    }

    var body: some View {
        List {
            if isWelcome {
                Section {
                    Text("Let's find your daily goal")
                        .font(.ui(30, .bold))
                        .foregroundStyle(Theme.ink)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
                }
            }

            Section {
                Picker("Sex", selection: $sexRaw) {
                    ForEach(Sex.allCases) { sex in
                        Text(sex.title).tag(sex.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                numberRow("Age", unit: "years") {
                    TextField("Age", text: $ageText)
                }
                numberRow("Height", unit: "cm") {
                    TextField("Height", text: $heightText)
                }
                numberRow("Weight", unit: "kg") {
                    TextField("Weight", text: $weightText)
                }
            } header: {
                SectionTitle(text: "You")
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Activity", selection: $activityRaw) {
                    ForEach(Activity.allCases) { activity in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.title)
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                            Text(activity.detail)
                                .font(.ui(15))
                                .foregroundStyle(Theme.secondary)
                        }
                        .tag(activity.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SectionTitle(text: "Your week")
            }
            .listRowBackground(Theme.card)

            Section {
                Picker("Goal", selection: $goalRaw) {
                    ForEach(WeightGoal.allCases) { goal in
                        Text(goal.title).tag(goal.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                SectionTitle(text: "Your goal")
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.page.ignoresSafeArea())
        .navigationTitle(isWelcome ? "" : "Work it out")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { resultBar }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editing = false }
            }
        }
        .onAppear {
            ageText = String(age)
            heightText = String(height)
            weightText = FoodDetailView.format(weight)
        }
        .onChange(of: ageText) { _, text in
            if let value = FoodDetailView.parse(text), (10...110).contains(value) { age = value.safeInt }
        }
        .onChange(of: heightText) { _, text in
            if let value = FoodDetailView.parse(text), (100...250).contains(value) { height = value.safeInt }
        }
        .onChange(of: weightText) { _, text in
            if let value = FoodDetailView.parse(text), (25...400).contains(value) { weight = value }
        }
    }

    private func numberRow(_ title: String, unit: String, @ViewBuilder field: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            field()
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.number(17))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: 90)
                .focused($editing)
            Text(unit)
                .font(.ui(17))
                .foregroundStyle(Theme.secondary)
                .frame(width: 48, alignment: .leading)
        }
    }

    private var resultBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.formatted())
                    .font(.number(40))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: Double(result)))
                Text("kcal a day")
                    .font(.ui(17))
                    .foregroundStyle(Theme.secondary)
            }
            .animation(.snappy, value: result)

            Button(isWelcome ? "Start tracking" : "Use this goal") {
                editing = false
                onUse(result)
                if !isWelcome { dismiss() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.page.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GoalCalculatorView(isWelcome: true) { _ in }
    }
}
#endif
