import SwiftUI

/// Plan a fast: what eating once every few days would do, from your own numbers. Where your
/// weight goes and when it reaches your goal, your body now and then, every way of fasting
/// side by side, one turn of the cycle hour by hour, and what to know before you start. An
/// estimate, and it says so; Bite plans fasts of a week at most and never below a BMI of 20.
struct FastingPlanView: View {
    /// Your weight now: the trend of your weighings, else the goal calculator's.
    let currentKg: Double?
    /// What you burn, once your weighings and meals have taught Bite.
    let learnedKcal: Double?
    /// Your daily goal, to set beside the fasts; nil with No target.
    let dailyGoal: Int?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("fasting.days") private var fastDays = FastingCycle.onceAWeek.fastDays

    @State private var you: FastingBody
    @State private var goalKg: Double
    /// Nil: a day of what you burn, the meal the cycles are worked out with.
    @State private var mealKcal: Double?
    @State private var editing = false
    @State private var picked: Int?

    init(currentKg: Double?, learnedKcal: Double?, dailyGoal: Int?) {
        self.currentKg = currentKg
        self.learnedKcal = learnedKcal
        self.dailyGoal = dailyGoal
        let defaults = UserDefaults.standard
        var weight = currentKg ?? (defaults.object(forKey: "body.weight") != nil ? defaults.double(forKey: "body.weight") : 70)
        #if DEBUG
        // `-fasting.weight 113.4` plans for another body, for screenshots.
        if defaults.object(forKey: "fasting.weight") != nil { weight = defaults.double(forKey: "fasting.weight") }
        #endif
        let body = FastingBody(
            sex: Sex(rawValue: defaults.string(forKey: "body.sex") ?? "") ?? .female,
            age: defaults.object(forKey: "body.age") != nil ? defaults.integer(forKey: "body.age") : 30,
            heightCm: defaults.object(forKey: "body.height") != nil ? defaults.double(forKey: "body.height") : 170,
            weightKg: weight,
            activity: Activity(rawValue: defaults.string(forKey: "body.activity") ?? "") ?? .light,
            learnedKcal: learnedKcal
        )
        _you = State(initialValue: body)
        _goalKg = State(initialValue: FastingModel.suggestedGoal(for: body))
    }

    private var cycle: FastingCycle {
        FastingCycle.all.first { $0.fastDays == fastDays } ?? .onceAWeek
    }

    private var burn: Double { you.burn(atKg: you.weightKg) }
    private var meal: Double { mealKcal ?? burn.rounded() }

    /// The plan and what the screen shows of it.
    private struct Plan {
        let projection: FastingProjection
        /// The chart's days: to the goal and one more turn.
        let days: [FastingDay]
        let floorKg: Double
    }

    private var plan: Plan {
        let projection = FastingModel.project(body: you, intake: .cycle(cycle, mealKcal: meal), goalKg: goalKg, days: 26 * 7)
        let horizon = FastingModel.horizon(goalDay: projection.goalDay, cycle: cycle)
        return Plan(projection: projection, days: Array(projection.days.prefix(horizon)), floorKg: FastingModel.floorKg(for: you))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let refusal = FastingModel.refusal(for: you) {
                            youPane
                                .glassGroup()
                            refusalPane(refusal)
                                .glassGroup(after: 26)
                        } else {
                            let plan = self.plan
                            let shown = shownDay(plan)
                            resultPane(plan, shown: shown)
                                .glassGroup()
                            bodyPane(plan, shown: shown)
                                .glassGroup(after: 30)
                            methodsPane
                                .glassGroup(after: 30)
                                .id(Anchor.methods)
                            cyclePane(plan)
                                .glassGroup(after: 30)
                                .id(Anchor.cycle)
                            safetyPane
                                .glassGroup(after: 30)
                                .id(Anchor.safety)
                            smallPrint
                                .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .animation(Motion.settle, value: editing)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .roomBackground()
                .navigationTitle("Plan a fast")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onChange(of: fastDays) { _, _ in picked = nil }
                .onChange(of: goalKg) { _, _ in picked = nil }
                #if DEBUG
                .task {
                    // `-anchor methods|cycle|bottom` scrolls there, for screenshots.
                    guard let anchor = UserDefaults.standard.string(forKey: "anchor") else { return }
                    try? await Task.sleep(for: .seconds(1))
                    switch anchor {
                    case "methods": reader.scrollTo(Anchor.methods, anchor: .top)
                    case "cycle": reader.scrollTo(Anchor.cycle, anchor: .top)
                    case "bottom": reader.scrollTo(Anchor.safety, anchor: .top)
                    default: break
                    }
                }
                #endif
            }
        }
    }

    private enum Anchor: Hashable {
        case methods
        case cycle
        case safety
    }

    /// The day the chart and the figure show: the one you dragged to, else the goal's, else
    /// the chart's last.
    private func shownDay(_ plan: Plan) -> FastingDay {
        let fallback = plan.projection.goalDay ?? plan.days.count
        return plan.projection.day(min(picked ?? fallback, max(plan.days.count, 1)))
    }

    private func date(of day: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: day, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private func dayText(_ day: Int) -> String {
        date(of: day).formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: You

    private var youSummary: String {
        let kilos = you.weightKg.formatted(.number.precision(.fractionLength(0...1)))
        return [you.sex.title, "\(you.age) " + tr("years"), "\(Int(you.heightCm)) " + "cm", "\(kilos) " + "kg"].joined(separator: " · ")
    }

    private var youPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.respond) { editing.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your numbers")
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                        Text(verbatim: youSummary)
                            .font(.ui(14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(editing ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if editing {
                VStack(spacing: 0) {
                    Picker("Sex", selection: $you.sex) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 12)
                    stepRow("Age", value: Text(verbatim: "\(you.age) " + tr("years")), less: { you.age = max(you.age - 1, 10) }, more: { you.age = min(you.age + 1, 100) })
                    stepRow("Height", value: Text(verbatim: "\(Int(you.heightCm)) cm"), less: { you.heightCm = max(you.heightCm - 1, 120) }, more: { you.heightCm = min(you.heightCm + 1, 230) })
                    stepRow("Weight", value: Text(you.weightKg.weightText), less: { you.weightKg = max(you.weightKg - 0.5, 35) }, more: { you.weightKg = min(you.weightKg + 0.5, 300) })
                    HStack {
                        Text("Activity")
                            .font(.ui(16))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Picker("Activity", selection: $you.activity) {
                            ForEach(Activity.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.secondary)
                    }
                    .frame(minHeight: 48)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                }
                .transition(.opacity)
            }

            stepRow("Goal", value: Text(goalKg.weightText), less: { goalKg = max(goalKg - 0.5, 35) }, more: { goalKg = min(goalKg + 0.5, you.weightKg) })
                .padding(.top, 10)
        }
    }

    private func stepRow(_ title: LocalizedStringKey, value: Text, less: @escaping () -> Void, more: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.ui(16))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            value
                .font(.number(17))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            StepButton(systemImage: "minus", label: "Less") { withAnimation(Motion.respond) { less() } }
            StepButton(systemImage: "plus", label: "More") { withAnimation(Motion.respond) { more() } }
        }
        .frame(minHeight: 54)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: Where it takes you

    private func resultPane(_ plan: Plan, shown: FastingDay) -> some View {
        let projection = plan.projection
        let lost = projection.lost(by: shown.day)
        let perWeek = projection.perWeek.weightText
        return VStack(alignment: .leading, spacing: 14) {
            youPane
            Rectangle().fill(Theme.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shown.tissueKg.weightText)
                        .bigNumber(40)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: shown.tissueKg))
                    Text("by \(dayText(shown.day))")
                        .font(.ui(16))
                        .foregroundStyle(Theme.secondary)
                }
                Group {
                    if let goalDay = projection.goalDay {
                        Text("\(cycle.title), about \(perWeek) a week: your goal by \(dayText(goalDay)).")
                    } else if projection.stoppedAtFloor {
                        Text("\(cycle.title), about \(perWeek) a week. Bite stops at \(plan.floorKg.weightText), a BMI of 20.")
                    } else {
                        Text("\(cycle.title), about \(perWeek) a week.")
                    }
                }
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            }
            .animation(Motion.count, value: shown.day)

            FastingChart(
                start: projection.start,
                days: plan.days,
                goalKg: goalKg,
                floorKg: plan.floorKg,
                picked: shown.day,
                onPick: { picked = $0 }
            )
            .frame(height: 168)

            Text("\(lost.total.weightText) lost by \(dayText(shown.day)): \(lost.fat.weightText) fat, \(lost.lean.weightText) lean.")
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Your body

    private func bodyPane(_ plan: Plan, shown: FastingDay) -> some View {
        let start = plan.projection.start
        let thenBMI = you.bmi * shown.tissueKg / max(start.tissueKg, 1)
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Your body", symbol: "figure.stand")
            HStack(alignment: .bottom, spacing: 0) {
                figure(build: BodyFigure.build(bmi: you.bmi), filled: false, title: Text("Today"), kg: start.tissueKg, bmi: you.bmi)
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.bottom, 64)
                    .accessibilityHidden(true)
                figure(build: BodyFigure.build(bmi: thenBMI), filled: true, title: Text(verbatim: dayText(shown.day)), kg: shown.tissueKg, bmi: thenBMI)
            }
        }
    }

    private func figure(build: CGFloat, filled: Bool, title: Text, kg: Double, bmi: Double) -> some View {
        VStack(spacing: 8) {
            ZStack {
                if filled {
                    BodyFigureShape(build: build)
                        .fill(Theme.ink.opacity(0.2))
                }
                BodyFigureShape(build: build)
                    .stroke(filled ? Theme.ink : Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: filled ? [] : [3, 3]))
            }
            .frame(height: 190)
            .animation(Motion.respond, value: build)
            VStack(spacing: 1) {
                title
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                Text(kg.weightText)
                    .font(.number(17))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: kg))
                Text("BMI \(bmi.formatted(.number.precision(.fractionLength(1))))")
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: How you fast

    private struct Method: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let lostKg: Double
        let share: Double?
        let cycle: FastingCycle?
    }

    private var methods: [Method] {
        var rows: [Method] = FastingCycle.all.map { cycle in
            let projection = FastingModel.project(body: you, intake: .cycle(cycle, mealKcal: meal), goalKg: 0, days: 28)
            return Method(id: cycle.fastDays, title: cycle.title, detail: cycle.detail, lostKg: projection.lost(by: 28).total, share: cycle.shareOfNonstop, cycle: cycle)
        }
        if let dailyGoal, Double(dailyGoal) < burn {
            let projection = FastingModel.project(body: you, intake: .daily(kcal: Double(dailyGoal)), goalKg: 0, days: 28)
            rows.insert(Method(id: 0, title: tr("Your daily goal"), detail: tr("%@ kcal every day", Double(dailyGoal).kcalText), lostKg: projection.lost(by: 28).total, share: nil, cycle: nil), at: 0)
        }
        return rows
    }

    private var methodsPane: some View {
        let rows = methods
        let most = max(rows.map(\.lostKg).max() ?? 1, 0.1)
        let weekLong = FastingCycle(fastDays: FastingCycle.longest).shareOfNonstop
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "How you fast", detail: "In 4 weeks", symbol: "timer")
                .padding(.bottom, 6)
            ForEach(rows) { row in
                methodRow(row, fraction: row.lostKg / most)
            }
            Text("Past a week, each extra day adds little and the risks grow: week-long fasts already keep \(weekLong.formatted(.percent.precision(.fractionLength(0)))) of what a fast that never ends would do.")
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func methodRow(_ row: Method, fraction: Double) -> some View {
        let isOn = row.cycle?.fastDays == fastDays
        return Button {
            guard let cycle = row.cycle else { return }
            withAnimation(Motion.settle) { fastDays = cycle.fastDays }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                        Text(verbatim: row.detail)
                            .font(.ui(13))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: "−" + row.lostKg.weightText)
                        .font(.number(17))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(isOn ? Theme.ink : row.cycle == nil ? Theme.tertiary : Theme.secondary)
                            .frame(width: max(proxy.size.width * fraction, 4))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .selectedFill(isOn, in: RoundedRectangle(cornerRadius: 18, style: .continuous), off: .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(row.cycle == nil)
        .sensoryFeedback(Feel.tick, trigger: isOn) { _, on in on }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .padding(.horizontal, -12)
    }

    // MARK: The cycle

    private func cyclePane(_ plan: Plan) -> some View {
        let water = plan.projection.days.prefix(cycle.length).map { $0.tissueKg - $0.scaleKg }.max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "The cycle", symbol: "arrow.triangle.2.circlepath")
            HStack(spacing: 6) {
                ForEach(1...cycle.fastDays, id: \.self) { day in
                    Text(verbatim: "\(day)")
                        .font(.ui(13, .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: 38)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Theme.track, in: Circle())
                }
                Image(systemName: "fork.knife")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.selectedInk)
                    .frame(maxWidth: 38)
                    .aspectRatio(1, contentMode: .fit)
                    .selectedFill(true, in: Circle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Text(verbatim: cycle.detail)
                .font(.ui(15))
                .foregroundStyle(Theme.ink)

            stepRow("Your meal", value: Text("\(meal.kcalText) kcal"), less: { mealKcal = max(meal - 100, 500) }, more: { mealKcal = min(meal + 100, 5000) })

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(FastingStage.through(fastDays: cycle.fastDays).enumerated()), id: \.offset) { index, stage in
                    HStack(alignment: .top, spacing: 14) {
                        Text(verbatim: "\(stage.hour) h")
                            .font(.ui(13, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: stage.title)
                                .font(.ui(15, .medium))
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: stage.detail)
                                .font(.ui(14))
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 58)
                        }
                    }
                }
            }

            if water > 0.3 {
                Text("On the scale: about \(water.weightText) of water goes in the first days and comes back with the meal. The trend line is what counts.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Before you start

    private var safetyPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Before you start", symbol: "heart.text.square")
            safetyRow("stethoscope", "Ask your doctor first, above all before fasting 3 days or more.")
            safetyRow("drop", "Drink water all the way through. For longer fasts, ask about salt, potassium and magnesium.")
            safetyRow("exclamationmark.triangle", "Stop and eat if you feel faint or dizzy, can't think straight, or your heart races.")
            safetyRow("hand.raised", "Not for you if you're pregnant or breastfeeding, take medicine for diabetes, or have had an eating disorder.")
            safetyRow("fork.knife", "End a long fast with a small meal, and go slowly for a day.")
        }
    }

    private func safetyRow(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(systemImage: symbol, color: Theme.ink, glyph: Theme.ink, size: 30)
            Text(text)
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private var smallPrint: some View {
        let dip = FastingModel.maxDip.formatted(.percent.precision(.fractionLength(0)))
        return Group {
            if learnedKcal != nil {
                Text("An estimate, and every body differs. What you burn is learned from your weighings and falls up to \(dip) deep into a fast; body fat comes from your BMI, and the split between fat and lean from Forbes. Bite plans down to a BMI of 20, and fasts of a week at most.")
            } else {
                Text("An estimate, and every body differs. What you burn is worked out from your body and falls up to \(dip) deep into a fast; body fat comes from your BMI, and the split between fat and lean from Forbes. Bite plans down to a BMI of 20, and fasts of a week at most.")
            }
        }
        .font(.ui(13))
        .foregroundStyle(Theme.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: When Bite won't plan

    private func refusalPane(_ refusal: FastingRefusal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch refusal {
            case .underAge:
                Text("Fasting plans are for adults.")
                    .font(.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
            case .lowBMI:
                Text("At a BMI under 20, Bite doesn't plan a fast.")
                    .font(.ui(17, .medium))
                    .foregroundStyle(Theme.ink)
                Text("Your BMI: \(you.bmi.formatted(.number.precision(.fractionLength(1))))")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The plan as a chart: what the scale says each day, falling through each fast and bouncing
/// after each meal, the trend under it, the goal as a dashed line, the meals as dots along the
/// bottom. Drag along it to see any day.
private struct FastingChart: View {
    let start: FastingDay
    let days: [FastingDay]
    let goalKg: Double
    let floorKg: Double
    let picked: Int
    let onPick: (Int) -> Void

    @State private var dragged = 0

    var body: some View {
        let all = [start] + days
        let low = min(all.map(\.scaleKg).min() ?? goalKg, goalKg) - 0.6
        let high = start.scaleKg + 0.8
        let count = max(days.count, 1)
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let plot = CGRect(x: 4, y: 6, width: proxy.size.width - 8, height: proxy.size.height - 20)
                Canvas { context, _ in
                    func point(_ day: Int, _ kg: Double) -> CGPoint {
                        CGPoint(
                            x: plot.minX + plot.width * CGFloat(day) / CGFloat(count),
                            y: plot.minY + plot.height * CGFloat(1 - (kg - low) / max(high - low, 0.1))
                        )
                    }
                    // The goal, dashed, and the floor when it is in view.
                    for (kg, color) in [(goalKg, Theme.onTarget), (floorKg, Theme.over)] where kg > low && kg < high {
                        var line = Path()
                        line.move(to: point(0, kg))
                        line.addLine(to: point(count, kg))
                        context.stroke(line, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                    }
                    // The scale, day by day.
                    var scale = Path()
                    scale.addLines(all.map { point($0.day, $0.scaleKg) })
                    context.stroke(scale, with: .color(Theme.ink.opacity(0.35)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    // The trend under it.
                    var trend = Path()
                    trend.addLines(all.map { point($0.day, $0.tissueKg) })
                    context.stroke(trend, with: .color(Theme.onTarget), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    // The meals, along the bottom.
                    for day in days where day.ate {
                        let x = point(day.day, low).x
                        context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: plot.maxY + 7, width: 5, height: 5)), with: .color(Theme.secondary))
                    }
                    // The day you look at.
                    let shown = days.indices.contains(picked - 1) ? days[picked - 1] : start
                    let dot = point(shown.day, shown.tissueKg)
                    var mark = Path()
                    mark.move(to: CGPoint(x: dot.x, y: plot.minY))
                    mark.addLine(to: CGPoint(x: dot.x, y: plot.maxY))
                    context.stroke(mark, with: .color(Theme.hairline), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)), with: .color(Theme.page))
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)), with: .color(Theme.ink))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        let share = (value.location.x - plot.minX) / max(plot.width, 1)
                        let day = min(max(Int((share * CGFloat(count)).rounded()), 1), count)
                        if day != dragged {
                            dragged = day
                            onPick(day)
                        }
                    }
                )
            }
            HStack {
                Text("Today")
                Spacer()
                Text(verbatim: (Calendar.current.date(byAdding: .day, value: count, to: .now) ?? .now).formatted(.dateTime.day().month(.abbreviated)))
            }
            .font(.ui(12))
            .foregroundStyle(Theme.secondary)
        }
        // A tick for each week you move through, never for each day.
        .sensoryFeedback(Feel.tick, trigger: dragged / 7)
        .accessibilityElement()
        .accessibilityLabel("Your weight through the plan")
        .accessibilityValue(Text(verbatim: (days.indices.contains(picked - 1) ? days[picked - 1] : start).tissueKg.weightText))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onPick(min(picked + 7, count))
            case .decrement: onPick(max(picked - 7, 1))
            @unknown default: break
            }
        }
    }
}
