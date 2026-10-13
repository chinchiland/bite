import SwiftUI

/// "Is 2,000 kcal right for you?": the goal, asked once the page has a meal on it. Apple Health
/// fills you in with one tap and says why it asks; or you type four numbers. Then how your week
/// looks and what you want, and the live number to use. "No target" keeps counting without a
/// budget, for people who want to see what they eat.
struct GoalStep: View {
    let onDone: () -> Void

    @AppStorage("goal.kcal") private var goalKcal = 2000
    @AppStorage("goal.noTarget") private var noTarget = false
    @AppStorage("body.sex") private var sexRaw = Sex.female.rawValue
    @AppStorage("body.age") private var age = 30
    @AppStorage("body.height") private var height = 170
    @AppStorage("body.weight") private var weight = 70.0
    @AppStorage("body.activity") private var activityRaw = Activity.light.rawValue
    @AppStorage("body.goal") private var goalRaw = WeightGoal.maintain.rawValue
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.weightAsked") private var weightAsked = false
    @AppStorage("health.unavailable") private var healthUnavailable = false

    @State private var aim: Aim = .keep
    @State private var typing = false
    @State private var asking = false
    @State private var filledFromHealth = false
    @State private var taps = 0

    enum Aim: CaseIterable {
        case lose
        case keep
        case gain
        case none

        var title: String {
            switch self {
            case .lose: tr("Lose a little")
            case .keep: tr("Keep steady")
            case .gain: tr("Gain slowly")
            case .none: tr("No target")
            }
        }

        var weightGoal: WeightGoal {
            switch self {
            case .lose: .lose
            case .gain: .gain
            case .keep, .none: .maintain
            }
        }
    }

    private var sex: Sex { Sex(rawValue: sexRaw) ?? .female }
    private var activity: Activity { Activity(rawValue: activityRaw) ?? .light }

    private var result: Int {
        GoalCalculator.dailyCalories(sex: sex, age: age, heightCm: Double(height), weightKg: weight, activity: activity, goal: aim.weightGoal)
    }

    /// "Female · 30 years · 170 cm · 70 kg", each number with its unit.
    private var bodySummary: String {
        let kilos = weight.formatted(.number.precision(.fractionLength(0...1)))
        return [sex.title, "\(age) " + tr("years"), "\(height) " + "cm", "\(kilos) " + "kg"].joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Is \(Double(goalKcal).kcalText) kcal right for you?")
                        .font(.ui(26, .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Three answers make it yours.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 5)

                    label("About you")
                    aboutYou

                    label("Your week")
                    grid(Activity.allCases, selected: activity) { activityRaw = $0.rawValue } content: { option in
                        choice(option.title, detail: option.shortDetail, isOn: option == activity)
                    }

                    label("Your aim")
                    grid(Aim.allCases, selected: aim) { aim = $0 } content: { option in
                        choice(option.title, detail: nil, isOn: option == aim)
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.page)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDone()
        }
        .onAppear {
            if noTarget {
                aim = .none
            } else {
                switch WeightGoal(rawValue: goalRaw) ?? .maintain {
                case .lose: aim = .lose
                case .gain: aim = .gain
                case .maintain: aim = .keep
                }
            }
        }
        .sensoryFeedback(Feel.click, trigger: taps)
    }

    // MARK: About you

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 0) {
            if HealthActivity.isAvailable && !healthUnavailable {
                // Icon, title, reason: one left edge, the way the card reads best.
                Button(action: fillFromHealth) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            AppleHealthIcon(size: 40)
                            Text(filledFromHealth ? LocalizedStringKey("Filled in from Apple Health") : LocalizedStringKey("Fill in from Apple Health"))
                                .font(.ui(17, .medium))
                                .foregroundStyle(Theme.ink)
                                .padding(.top, 10)
                            Text("Your height, weight, age and sex, to work out the goal. Then your steps and what you burn.")
                                .font(.ui(14))
                                .foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if asking {
                            ProgressView()
                        } else {
                            Image(systemName: filledFromHealth ? "checkmark" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(filledFromHealth ? Theme.onTarget : Theme.tertiary)
                        }
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(asking)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }

            Button {
                withAnimation(Motion.respond) { typing.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(typing ? LocalizedStringKey("Your numbers") : LocalizedStringKey("Or type it in"))
                            .font(.ui(17, .medium))
                            .foregroundStyle(Theme.ink)
                        if !typing {
                            Text(verbatim: bodySummary)
                                .font(.ui(14))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(typing ? 180 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(typing ? LocalizedStringKey("Hides your numbers") : LocalizedStringKey("Shows your sex, age, height and weight"))

            if typing {
                VStack(spacing: 0) {
                    Picker("Sex", selection: $sexRaw) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 6)
                    numberRow("Age", unit: "years") {
                        TextField("30", value: $age, format: .number)
                    }
                    numberRow("Height", unit: "cm") {
                        TextField("170", value: $height, format: .number)
                    }
                    numberRow("Weight", unit: "kg") {
                        TextField("70", value: $weight, format: .number.precision(.fractionLength(0...1)))
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func numberRow<Field: View>(_ title: LocalizedStringKey, unit: LocalizedStringKey, @ViewBuilder field: () -> Field) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.ui(17))
                .foregroundStyle(Theme.ink)
            Spacer()
            field()
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.number(17))
                .frame(maxWidth: 90)
            Text(unit)
                .font(.ui(17))
                .foregroundStyle(Theme.secondary)
                .frame(width: 44, alignment: .leading)
        }
        .frame(minHeight: 46)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    /// Asks Health once for everything Bite reads, then fills in what it knows. What it does
    /// not know opens the four fields.
    private func fillFromHealth() {
        asking = true
        Task {
            let asked = await HealthActivity.shared.requestAccess()
            if asked {
                healthAsked = true
                weightAsked = true
            } else {
                healthUnavailable = true
            }
            let facts = await HealthActivity.shared.bodyFacts()
            withAnimation(Motion.settle) {
                if let sex = facts.sex { sexRaw = sex.rawValue }
                if let years = facts.age, (10...110).contains(years) { age = years }
                if let cm = facts.heightCm, (100...250).contains(cm) { height = Int(cm.rounded()) }
                if let kg = facts.weightKg, (25...400).contains(kg) { weight = (kg * 10).rounded() / 10 }
                filledFromHealth = !facts.isEmpty
                if facts.sex == nil || facts.age == nil || facts.heightCm == nil || facts.weightKg == nil { typing = true }
                asking = false
            }
        }
    }

    // MARK: Choices

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.ui(13))
            .textCase(.uppercase)
            .foregroundStyle(Theme.ink)
            .padding(.leading, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func grid<Item: Hashable, Content: View>(
        _ items: [Item],
        selected: Item,
        onPick: @escaping (Item) -> Void,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button {
                    withAnimation(Motion.respond) { onPick(item) }
                } label: {
                    content(item)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .sensoryFeedback(Feel.tick, trigger: selected == item) { _, new in new }
                .accessibilityAddTraits(selected == item ? .isSelected : [])
            }
        }
    }

    private func choice(_ title: String, detail: String?, isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.ui(15, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            if let detail {
                Text(detail)
                    .font(.ui(13))
                    .opacity(0.72)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .foregroundStyle(isOn ? Theme.page : Theme.ink)
        .frame(maxWidth: .infinity, minHeight: detail == nil ? 44 : 56, alignment: .leading)
        .padding(.horizontal, 14)
        .background(isOn ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: isOn ? 0 : 1)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if aim == .none {
                Text("No target. Bite counts, and shows you the pattern.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start my journal", action: use)
                    .buttonStyle(PrimaryButtonStyle(height: 52))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Double(result).kcalText)
                        .font(.number(40, .medium))
                        .numberTracking(40)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(result)))
                    Text("kcal a day")
                        .font(.ui(16))
                        .foregroundStyle(Theme.secondary)
                }
                .animation(Motion.count, value: result)
                let title: LocalizedStringKey = result == goalKcal
                    ? "Keep \(Double(result).kcalText) kcal"
                    : "Use \(Double(result).kcalText) kcal"
                Button(title, action: use)
                    .buttonStyle(PrimaryButtonStyle(height: 52))
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(Theme.page)
    }

    private func use() {
        taps += 1
        withAnimation(Motion.count) {
            goalRaw = aim.weightGoal.rawValue
            noTarget = aim == .none
            if aim != .none { goalKcal = result }
        }
        onDone()
    }
}

/// Apple's own Health app icon (Apple Design Resources), as provided: its shape is in the file,
/// and the words Apple Health sit beside it. A hairline keeps its white edge on a white card,
/// as iOS draws app icons in lists.
struct AppleHealthIcon: View {
    var size: CGFloat = 40

    var body: some View {
        Image("AppleHealth")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Theme.ink.opacity(0.12), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}
