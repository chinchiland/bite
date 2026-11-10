import SwiftUI

/// Plan a fast: what eating once every few days would do, from your own numbers. Each pane opens
/// on its picture or its number and the words come after: your body today beside your body on
/// the day you look at, with what goes around it in green, and the chart you drag to move that
/// day; what you burn, part by part, from your steps and your sport; every way of fasting side by
/// side; one turn of the cycle hour by hour; how much of the loss is fat and how to keep the
/// muscle; what to take on days without food; and what to know before you start. An estimate,
/// and it says so; Bite plans fasts of a week at most and never below a BMI of 20.
struct FastingPlanView: View {
    /// Your weight now: the trend of your weighings, else the goal calculator's.
    let currentKg: Double?
    /// What your weighings and meals say you burn, once they can: shown beside the calculator,
    /// so you can set your steps until the two agree.
    let learnedKcal: Double?
    /// Your daily goal, to set beside the fasts; nil with No target.
    let dailyGoal: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("fasting.days") private var fastDays = FastingCycle.onceAWeek.fastDays
    /// One fast, then eating as usual, instead of the fast over and over.
    @AppStorage("fasting.once") private var once = false
    /// Your steps and your sport, as `Moving.stored`.
    @AppStorage("fasting.moving") private var movingStored = ""

    @State private var you: FastingBody
    @State private var goalKg: Double
    /// Nil: a day of what you burn, the meal the cycles are worked out with.
    @State private var mealKcal: Double?
    @State private var editing = false
    @State private var picked: Int?
    /// You changed your weight here: what Today learns no longer moves it.
    @State private var weightTouched = false
    /// The sport whose minutes and days are open.
    @State private var openSport: Sport.ID?
    /// The day's body has grown from today's into its own: once, when the plan opens.
    @State private var revealed = false
    @State private var showsDoses = false

    init(currentKg: Double?, learnedKcal: Double?, dailyGoal: Int?) {
        self.currentKg = currentKg
        self.learnedKcal = learnedKcal
        self.dailyGoal = dailyGoal
        let defaults = UserDefaults.standard
        var weight = currentKg ?? (defaults.object(forKey: "body.weight") != nil ? defaults.double(forKey: "body.weight") : 70)
        var touched = false
        let activity = Activity(rawValue: defaults.string(forKey: "body.activity") ?? "") ?? .light
        var moving = Moving(stored: defaults.string(forKey: "fasting.moving") ?? "") ?? .usual(for: activity)
        var open: Sport.ID?
        #if DEBUG
        // `-fasting.weight 113.4` plans for another body, `-fasting.steps 12500` and
        // `-fasting.sports "boxing:60:3 tennis:90:2"` for another week, for screenshots.
        if defaults.object(forKey: "fasting.weight") != nil {
            weight = defaults.double(forKey: "fasting.weight")
            touched = true
        }
        if defaults.object(forKey: "fasting.steps") != nil {
            moving.steps = defaults.integer(forKey: "fasting.steps")
        }
        if let sports = defaults.string(forKey: "fasting.sports") {
            moving.sports = sports.split(separator: " ").compactMap { item in
                let parts = item.split(separator: ":").map(String.init)
                guard parts.count == 3, let kind = SportKind(rawValue: parts[0]), let minutes = Int(parts[1]), let perWeek = Int(parts[2]) else { return nil }
                return Sport(kind: kind, minutes: minutes, perWeek: perWeek)
            }
            if defaults.bool(forKey: "fasting.sportOpen") { open = moving.sports.first?.id }
        }
        #endif
        let body = FastingBody(
            sex: Sex(rawValue: defaults.string(forKey: "body.sex") ?? "") ?? .female,
            age: defaults.object(forKey: "body.age") != nil ? defaults.integer(forKey: "body.age") : 30,
            heightCm: defaults.object(forKey: "body.height") != nil ? defaults.double(forKey: "body.height") : 170,
            weightKg: weight,
            moving: moving
        )
        _you = State(initialValue: body)
        _goalKg = State(initialValue: FastingModel.suggestedGoal(for: body))
        _weightTouched = State(initialValue: touched)
        _openSport = State(initialValue: open)
    }

    private var cycle: FastingCycle {
        FastingCycle(fastDays: min(max(fastDays, 1), FastingCycle.longest))
    }

    private var intake: FastingModel.Intake {
        once ? .once(fastDays: cycle.fastDays, mealKcal: meal) : .cycle(cycle, mealKcal: meal)
    }

    private var burn: Double { you.burn(atKg: you.weightKg) }
    private var meal: Double { mealKcal ?? burn.rounded() }
    private var female: Bool { you.sex == .female }

    /// The plan and what the screen shows of it.
    private struct Plan {
        let projection: FastingProjection
        /// The chart's days: to the goal and one more turn.
        let days: [FastingDay]
        let floorKg: Double
    }

    private var plan: Plan {
        let projection = FastingModel.project(body: you, intake: intake, goalKg: goalKg, days: 26 * 7)
        // One fast is drawn to three weeks past it, so the water coming back shows.
        let horizon = once ? max(28, cycle.fastDays + 21) : FastingModel.horizon(goalDay: projection.goalDay, cycle: cycle)
        return Plan(projection: projection, days: Array(projection.days.prefix(horizon)), floorKg: FastingModel.floorKg(for: you))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let refusal = FastingModel.refusal(for: you) {
                            youRow
                                .glassGroup()
                            refusalPane(refusal)
                                .glassGroup(after: 26)
                        } else {
                            let plan = self.plan
                            let shown = shownDay(plan)
                            heroPane(plan, shown: shown)
                                .glassGroup()
                            burnPane
                                .glassGroup(after: 30)
                                .id(Anchor.burn)
                            methodsPane
                                .glassGroup(after: 30)
                                .id(Anchor.methods)
                            cyclePane(plan)
                                .glassGroup(after: 30)
                                .id(Anchor.cycle)
                            musclePane(plan, shown: shown)
                                .glassGroup(after: 30)
                                .id(Anchor.muscle)
                            electrolytesPane
                                .glassGroup(after: 30)
                                .id(Anchor.electrolytes)
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
                .overlay(alignment: .top) { RoomTop() }
                .roomBackground()
                .navigationTitle("Plan a fast")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .onAppear {
                    // The day's body grows out of today's: the change, shown moving once.
                    guard !revealed else { return }
                    if reduceMotion {
                        revealed = true
                    } else {
                        withAnimation(Motion.reveal.delay(0.3)) { revealed = true }
                    }
                }
                .onChange(of: fastDays) { _, _ in picked = nil }
                .onChange(of: once) { _, single in
                    picked = nil
                    // Each list has its own lengths: land on one it shows.
                    if single, !FastingModel.onceLengths.contains(fastDays) { fastDays = FastingCycle.longest }
                    if !single, !FastingCycle.all.contains(where: { $0.fastDays == fastDays }) { fastDays = FastingCycle.onceAWeek.fastDays }
                }
                .onChange(of: goalKg) { _, _ in picked = nil }
                .onChange(of: you.moving) { _, moving in movingStored = moving.stored }
                // Your weighings can arrive after the plan opens.
                .onChange(of: currentKg) { _, kilograms in
                    guard let kilograms, !weightTouched else { return }
                    you.weightKg = kilograms
                    goalKg = FastingModel.suggestedGoal(for: you)
                }
                #if DEBUG
                .task {
                    // `-anchor burn|methods|cycle|muscle|electrolytes|bottom` scrolls there, for screenshots.
                    guard let anchor = UserDefaults.standard.string(forKey: "anchor") else { return }
                    try? await Task.sleep(for: .seconds(1))
                    switch anchor {
                    case "burn": reader.scrollTo(Anchor.burn, anchor: .top)
                    case "methods": reader.scrollTo(Anchor.methods, anchor: .top)
                    case "cycle": reader.scrollTo(Anchor.cycle, anchor: .top)
                    case "muscle": reader.scrollTo(Anchor.muscle, anchor: .top)
                    case "electrolytes": reader.scrollTo(Anchor.electrolytes, anchor: .top)
                    case "bottom": reader.scrollTo(Anchor.safety, anchor: .top)
                    default: break
                    }
                }
                #endif
            }
        }
    }

    private enum Anchor: Hashable {
        case burn
        case methods
        case cycle
        case muscle
        case electrolytes
        case safety
    }

    /// The day the chart and the bodies show: the one you dragged to, else the goal's, else the
    /// chart's last.
    private func shownDay(_ plan: Plan) -> FastingDay {
        let fallback = once ? cycle.fastDays : plan.projection.goalDay ?? plan.days.count
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

    /// Your numbers in one line, a tap to change them.
    private var youRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.respond) { editing.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(verbatim: youSummary)
                        .font(.ui(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(editing ? 180 : 0))
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Your numbers"))
            .accessibilityValue(Text(verbatim: youSummary))

            if editing {
                VStack(spacing: 0) {
                    Picker("Sex", selection: $you.sex) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 12)
                    stepRow("Age", value: Text(verbatim: "\(you.age) " + tr("years")), less: { you.age = max(you.age - 1, 10) }, more: { you.age = min(you.age + 1, 100) })
                    stepRow("Height", value: Text(verbatim: "\(Int(you.heightCm)) cm"), less: { you.heightCm = max(you.heightCm - 1, 120) }, more: { you.heightCm = min(you.heightCm + 1, 230) })
                    stepRow("Weight", value: Text(you.weightKg.weightText), less: {
                        weightTouched = true
                        you.weightKg = max(you.weightKg - 0.5, 35)
                    }, more: {
                        weightTouched = true
                        you.weightKg = min(you.weightKg + 0.5, 300)
                    })
                }
                .transition(.opacity)
            }
        }
    }

    private func stepRow(_ title: LocalizedStringKey, value: Text, divided: Bool = true, less: @escaping () -> Void, more: @escaping () -> Void) -> some View {
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
        .overlay(alignment: .top) {
            if divided { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }

    // MARK: You, then

    /// Your body today, dimmed, beside your body on the day you look at, with what goes around
    /// it in green: the change seen at once, its weights under it, then the chart that moves it.
    private func heroPane(_ plan: Plan, shown: FastingDay) -> some View {
        let projection = plan.projection
        let start = projection.start
        let thenBMI = you.bmi * shown.tissueKg / max(start.tissueKg, 1)
        let now = BodyFigure.build(bmi: you.bmi)
        let then = revealed ? BodyFigure.build(bmi: thenBMI) : now
        let early = min(28, max(projection.days.count, 1))
        let perWeek = (projection.lost(by: early).total / Double(early) * 7).weightText
        return VStack(alignment: .leading, spacing: 16) {
            youRow

            HStack(alignment: .bottom, spacing: 0) {
                bodyColumn(when: Text("Today"), kg: start.tissueKg, gone: nil) {
                    BodyFigureShape(build: now, female: female)
                        .fill(Theme.ink.opacity(0.3))
                }
                bodyColumn(when: Text(verbatim: dayText(shown.day)), kg: shown.tissueKg, gone: start.tissueKg - shown.tissueKg) {
                    ZStack {
                        if now - then > 0.002 {
                            BodyFigureShape(build: now, female: female)
                                .fill(Theme.onTarget)
                        }
                        BodyFigureShape(build: then, female: female)
                            .fill(Theme.ink)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if once {
                        let end = projection.day(cycle.fastDays)
                        let length = "\(cycle.fastDays)"
                        let gone = projection.lost(by: cycle.fastDays).total.weightText
                        let waterBack = max(end.tissueKg - end.scaleKg, 0).weightText
                        Text("One fast of \(length) days: \(gone) of fat and lean gone, and \(waterBack) of water that comes back with food.")
                    } else if let goalDay = projection.goalDay, goalDay < 14 {
                        let days = goalDay
                        Text("About \(perWeek) a week: your goal in \(days) days.")
                    } else if let goalDay = projection.goalDay {
                        let weeks = Int((Double(goalDay) / 7).rounded(.up))
                        Text("About \(perWeek) a week: your goal in \(weeks) weeks.")
                    } else if projection.stoppedAtFloor {
                        Text("About \(perWeek) a week. Bite stops at \(plan.floorKg.weightText), a BMI of 20.")
                    } else {
                        Text("About \(perWeek) a week.")
                    }
                }
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if you.bmi < 25 {
                    Text("At a BMI of \(you.bmi.formatted(.number.precision(.fractionLength(1)))) you're in the healthy range already.")
                        .font(.ui(14))
                        .foregroundStyle(Theme.watchText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FastingChart(
                start: projection.start,
                days: plan.days,
                goalKg: goalKg,
                floorKg: plan.floorKg,
                picked: shown.day,
                onPick: { day in withAnimation(Motion.respond) { picked = day } }
            )
            .frame(height: 160)

            stepRow("Goal", value: Text(goalKg.weightText), divided: false, less: { goalKg = max(goalKg - 0.5, 35) }, more: { goalKg = min(goalKg + 0.5, you.weightKg) })
                .frame(minHeight: 44)
        }
    }

    /// One body, its day and its weight under it, and on the day you look at what it lost.
    private func bodyColumn<Figure: View>(when: Text, kg: Double, gone: Double?, @ViewBuilder figure: () -> Figure) -> some View {
        VStack(spacing: 0) {
            figure()
                .frame(width: 150, height: 236)
                .accessibilityHidden(true)
            when
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
                .padding(.top, 10)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(kg.formatted(.number.precision(.fractionLength(1))))
                    .bigNumber(30)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: kg))
                Text(verbatim: "kg")
                    .font(.ui(16))
                    .foregroundStyle(Theme.secondary)
            }
            Text(verbatim: "−" + (gone ?? 0).weightText)
                .font(.ui(15, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.onTarget)
                .contentTransition(.numericText(value: gone ?? 0))
                .opacity(gone == nil ? 0 : 1)
                .accessibilityHidden(gone == nil)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: What you burn

    /// What a day burns, part by part, over the steps and the sport that set it.
    private var burnPane: some View {
        let parts = you.burnParts(atKg: you.weightKg)
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "What you burn", symbol: "flame.fill", symbolColor: Theme.burned)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.total.kcalText)
                    .bigNumber(40)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: parts.total))
                Text("kcal a day")
                    .font(.ui(16))
                    .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                SegmentBar(segments: [
                    .init(value: parts.rest, color: Theme.light),
                    .init(value: parts.life, color: Theme.energy),
                    .init(value: parts.walking, color: Theme.steps),
                    .init(value: parts.sport, color: Theme.burned),
                ])
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    legendItem("At rest", color: Theme.light, value: Text("\(parts.rest.kcalText) kcal"))
                    legendItem("Daily life", color: Theme.energy, value: Text("\(parts.life.kcalText) kcal"))
                    legendItem("Walking", color: Theme.steps, value: Text("\(parts.walking.kcalText) kcal"))
                    legendItem("Sport", color: Theme.burned, value: Text("\(parts.sport.kcalText) kcal"))
                }
            }

            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    SymbolTile(systemImage: "figure.walk", color: Theme.steps, glyph: Theme.steps, size: 32)
                    Text("Steps a day")
                        .font(.ui(16))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(you.moving.steps.formatted())
                        .font(.number(17))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: Double(you.moving.steps)))
                }
                .frame(minHeight: 44)
                Slider(value: Binding(get: { Double(you.moving.steps) }, set: { you.moving.steps = Int($0) }), in: 0...25000, step: 500)
                    .tint(Theme.steps)
                    .accessibilityLabel(Text("Steps a day"))
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1).offset(y: -8) }
            .sensoryFeedback(Feel.tick, trigger: you.moving.steps / 1000)

            if !you.moving.sports.isEmpty {
                VStack(spacing: 0) {
                    ForEach(you.moving.sports) { sport in
                        sportRow(sport)
                    }
                }
            }

            Menu {
                ForEach(SportKind.allCases) { kind in
                    Button {
                        let sport = Sport(kind: kind)
                        withAnimation(Motion.settle) {
                            you.moving.sports.append(sport)
                            openSport = sport.id
                        }
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add a sport")
                        .font(.ui(15, .medium))
                }
                .foregroundStyle(Theme.ink)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .frame(minHeight: 40)
                .background(Theme.fill, in: Capsule())
            }

            if let learnedKcal {
                Text("Your weighings say about \(learnedKcal.kcalText) kcal a day.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func legendItem(_ title: LocalizedStringKey, color: Color, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(title)
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            value
                .font(.ui(14, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }

    /// A sport in one line; a tap opens its minutes and days.
    private func sportRow(_ sport: Sport) -> some View {
        let isOpen = openSport == sport.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(Motion.respond) { openSport = isOpen ? nil : sport.id }
            } label: {
                HStack(spacing: 12) {
                    SymbolTile(systemImage: sport.kind.symbol, color: Theme.burned, glyph: Theme.burned, size: 32)
                    Text(verbatim: sport.kind.title)
                        .font(.ui(16))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: String(format: tr("%@ min, %@× a week"), "\(sport.minutes)", "\(sport.perWeek)"))
                        .font(.ui(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
                .lineLimit(1)
                .frame(minHeight: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen, let index = you.moving.sports.firstIndex(where: { $0.id == sport.id }) {
                VStack(alignment: .leading, spacing: 0) {
                    stepRow("Minutes", value: Text(verbatim: "\(sport.minutes)"), less: {
                        you.moving.sports[index].minutes = max(sport.minutes - 15, 15)
                    }, more: {
                        you.moving.sports[index].minutes = min(sport.minutes + 15, 240)
                    })
                    stepRow("Times a week", value: Text(verbatim: "\(sport.perWeek)"), less: {
                        you.moving.sports[index].perWeek = max(sport.perWeek - 1, 1)
                    }, more: {
                        you.moving.sports[index].perWeek = min(sport.perWeek + 1, 14)
                    })
                    Button {
                        withAnimation(Motion.settle) {
                            openSport = nil
                            you.moving.sports.removeAll { $0.id == sport.id }
                        }
                    } label: {
                        Text("Remove")
                            .font(.ui(15, .medium))
                            .foregroundStyle(Theme.over)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 44)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    // MARK: How you fast

    private struct Method: Identifiable {
        let id: Int
        let title: String
        let lostKg: Double
        let cycle: FastingCycle?
        /// The day it reaches a BMI of 20 inside the four weeks, where the comparison stops.
        var floorDay: Int? = nil
    }

    private func floorDay(_ projection: FastingProjection) -> Int? {
        projection.last.tissueKg <= FastingModel.floorKg(for: you) + 0.01 ? projection.days.count : nil
    }

    private var methods: [Method] {
        var rows: [Method] = once ? singleFasts : FastingCycle.all.map { cycle in
            let projection = FastingModel.project(body: you, intake: .cycle(cycle, mealKcal: meal), goalKg: 0, days: 28)
            return Method(id: cycle.fastDays, title: cycle.title, lostKg: projection.lost(by: 28).total, cycle: cycle, floorDay: floorDay(projection))
        }
        if let dailyGoal, Double(dailyGoal) < burn, !once {
            let projection = FastingModel.project(body: you, intake: .daily(kcal: Double(dailyGoal)), goalKg: 0, days: 28)
            rows.insert(Method(id: 0, title: tr("Your daily goal"), lostKg: projection.lost(by: 28).total, cycle: nil), at: 0)
        }
        return rows
    }

    /// One fast of each length, then eating as usual.
    private var singleFasts: [Method] {
        FastingModel.onceLengths.map { days in
            let projection = FastingModel.project(body: you, intake: .once(fastDays: days, mealKcal: meal), goalKg: 0, days: 28)
            return Method(id: days, title: tr("One fast of %@ days", "\(days)"), lostKg: projection.lost(by: 28).total, cycle: FastingCycle(fastDays: days), floorDay: floorDay(projection))
        }
    }

    private var methodsPane: some View {
        let rows = methods
        let most = max(rows.map(\.lostKg).max() ?? 1, 0.1)
        let weekLong = FastingCycle(fastDays: FastingCycle.longest).shareOfNonstop
        return VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: "How you fast", detail: "In 4 weeks", symbol: "timer")
                .padding(.bottom, 8)
            Picker("How you fast", selection: $once) {
                Text("Over and over").tag(false)
                Text("Just once").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            ForEach(rows) { row in
                methodRow(row, fraction: row.lostKg / most)
            }
            if !once {
                Text("Past a week, each extra day adds little and the risks grow: week-long fasts already keep \(weekLong.formatted(.percent.precision(.fractionLength(0)))) of what a fast that never ends would do.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
    }

    /// A way of fasting in one line, what it takes off in four weeks, and a bar to compare.
    private func methodRow(_ row: Method, fraction: Double) -> some View {
        let isOn = row.cycle?.fastDays == fastDays
        return Button {
            guard let cycle = row.cycle else { return }
            withAnimation(Motion.settle) { fastDays = cycle.fastDays }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                        if let day = row.floorDay {
                            Text(verbatim: tr("Down to a BMI of 20 by day %@", "\(day)"))
                                .font(.ui(13))
                                .foregroundStyle(Theme.watchText)
                        }
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
                .frame(height: 6)
            }
            .padding(12)
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
        let stages = FastingStage.through(fastDays: cycle.fastDays)
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "The cycle", symbol: "arrow.triangle.2.circlepath")
            ViewThatFits(in: .horizontal) {
                pills(size: 38)
                pills(size: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: once ? tr("%@ days without food, then back to eating as usual", "\(cycle.fastDays)") : cycle.detail))

            stepRow("Your meal", value: Text("\(meal.kcalText) kcal"), divided: false, less: { mealKcal = max(meal - 100, 500) }, more: { mealKcal = min(meal + 100, 5000) })
                .frame(minHeight: 44)

            // The stages on a rail: a dot for each, the meal's in green.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    let last = index == stages.count - 1
                    HStack(alignment: .top, spacing: 10) {
                        Text(verbatim: "\(stage.hour) h")
                            .font(.ui(13, .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.top, 2)
                        Circle()
                            .fill(last ? Theme.onTarget : Theme.secondary)
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                            .frame(width: 18)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(alignment: .top) {
                                if !last {
                                    Rectangle()
                                        .fill(Theme.track)
                                        .frame(width: 2)
                                        .padding(.top, 20)
                                        .padding(.bottom, -6)
                                }
                            }
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
                        .padding(.bottom, last ? 0 : 16)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
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

    /// One turn as day pills: the days without food, then the meal, lit.
    private func pills(size: CGFloat) -> some View {
        HStack(spacing: size > 32 ? 6 : 4) {
            ForEach(1...cycle.fastDays, id: \.self) { day in
                Text(verbatim: "\(day)")
                    .font(.ui(size > 32 ? 14 : 12, .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: size, height: size)
                    .background(Theme.track, in: Circle())
            }
            Image(systemName: "fork.knife")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Theme.selectedInk)
                .frame(width: size, height: size)
                .selectedFill(true, in: Circle())
        }
        .fixedSize()
    }

    // MARK: Lose fat, keep muscle

    /// How the loss splits between fat and lean on the day you look at, then what keeps more of
    /// it fat: protein, lifting, sleep, walking, and fasting less as you get leaner.
    private func musclePane(_ plan: Plan, shown: FastingDay) -> some View {
        let lost = plan.projection.lost(by: shown.day)
        let protein = (you.weightKg * Self.proteinPerKg / 5).rounded() * 5
        let grams = Measurement(value: protein, unit: UnitMass.grams).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
        let more = 0.6.formatted(.percent.precision(.fractionLength(0)))
        return VStack(alignment: .leading, spacing: 16) {
            SectionLabel(title: "Lose fat, keep muscle", symbol: "dumbbell.fill")
            VStack(alignment: .leading, spacing: 10) {
                SegmentBar(segments: [
                    .init(value: max(lost.fat, 0), color: Theme.energy),
                    .init(value: max(lost.lean, 0), color: Theme.protein),
                ])
                HStack(spacing: 16) {
                    legendItem("Body fat", color: Theme.energy, value: Text(max(lost.fat, 0).weightText))
                    legendItem("Lean tissue", color: Theme.protein, value: Text(max(lost.lean, 0).weightText))
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                tip(MacroTile(macro: .protein, size: 32), Text("Protein first in your meal: **\(grams)** or more."))
                tip(SymbolTile(systemImage: "dumbbell.fill", color: Theme.ink, glyph: Theme.ink, size: 32), Text("Lift 2 or 3 times a week, on your meal day or the day after."))
                tip(SymbolTile(systemImage: "moon.zzz.fill", color: Theme.water, glyph: Theme.water, size: 32), Text("Sleep 7 hours or more: on 5½ hours, dieters lost half the fat and \(more) more muscle."))
                tip(SymbolTile(systemImage: "figure.walk", color: Theme.steps, glyph: Theme.steps, size: 32), Text("Keep walking on days without food. Save hard sport for after the meal."))
                tip(SymbolTile(systemImage: "chart.line.downtrend.xyaxis", color: Theme.onTarget, glyph: Theme.onTarget, size: 32), Text("Near your goal, fast less often: the leaner you are, the more of each kilo is muscle."))
            }
        }
    }

    /// Protein in the meal for each kilo you weigh: about where more stops saving muscle during a
    /// diet (Helms, 2014; Refalo, 2025).
    private static let proteinPerKg = 1.6

    private func tip(_ tile: some View, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            tile
            text
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
    }

    // MARK: Electrolytes

    /// What to take on days without food, the same for everyone, so the plan never works out a
    /// dose: sodium at the usual reference amount, potassium kept modest because too much is the
    /// dangerous one, magnesium at the most a supplement should give in a day. The amounts first;
    /// how to take them a tap away.
    private var electrolytesPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Electrolytes", symbol: "drop.fill", symbolColor: Theme.water)
            Text("On days without food, in water you sip through the day.")
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                dose("Sodium", milligrams: 2000, note: "5 g of salt")
                dose("Potassium", milligrams: 1000, note: "at most")
                dose("Magnesium", milligrams: 350, note: "at most")
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(Motion.respond) { showsDoses.toggle() }
                } label: {
                    HStack {
                        Text("How to take them")
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .rotationEffect(.degrees(showsDoses ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(showsDoses ? .isSelected : [])

                if showsDoses {
                    VStack(alignment: .leading, spacing: 10) {
                        doseDetail("Sodium", "About 5 g of salt, a level teaspoon, spread over the day. A clear broth counts.")
                        doseDetail("Potassium", "From a potassium salt substitute: a quarter teaspoon has about 650 mg. Split it, never all at once. Not with kidney disease, or with ACE inhibitors, sartans or spironolactone, unless your doctor says so.")
                        doseDetail("Magnesium", "As citrate or glycinate: the most a supplement should give in a day. More tends to loosen the gut. Not with kidney disease.")
                        Text("Water: drink to thirst, about 2 to 3 litres. Plain water alone for days can lower your sodium.")
                        Text("Sodium and potassium as fasting is usually done; magnesium is the most a supplement should give in a day (US National Academy of Medicine). Ask your doctor about your own amounts.")
                            .foregroundStyle(Theme.tertiary)
                    }
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            Text("Headache, dizzy when you stand up, cramps: usually salt. A racing heart or fainting: stop, eat, and get help.")
                .font(.ui(14))
                .foregroundStyle(Theme.watchText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// An amount on a well: the name, the milligrams, and one word on it.
    private func dose(_ name: LocalizedStringKey, milligrams: Double, note: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: milligrams.kcalText)
                    .font(.number(20, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(verbatim: "mg")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            Text(note)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func doseDetail(_ name: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        Text(name).foregroundStyle(Theme.ink).fontWeight(.medium) + Text(verbatim: ". ") + Text(detail)
    }

    // MARK: Before you start

    private var safetyPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Before you start", symbol: "heart.text.square")
            safetyRow("stethoscope", "Ask your doctor first, above all before fasting 3 days or more.")
            safetyRow("exclamationmark.triangle", "Stop and eat if you feel faint or dizzy, can't think straight, or your heart races.")
            safetyRow("hand.raised", "Not for you if you're pregnant or breastfeeding, take medicine for diabetes, or have had an eating disorder.")
            safetyRow("fork.knife", "End a long fast with a small meal, and go slowly for a day.")
        }
    }

    private func safetyRow(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        tip(SymbolTile(systemImage: symbol, color: Theme.ink, glyph: Theme.ink, size: 32), Text(text))
    }

    private var smallPrint: some View {
        let dip = FastingModel.maxDip.formatted(.percent.precision(.fractionLength(0)))
        let life = DailyBurn.lifeShare.formatted(.percent.precision(.fractionLength(0)))
        let protein = Self.proteinPerKg.formatted(.number.precision(.fractionLength(1)))
        return Text("An estimate, and every body differs. What you burn: resting energy from your body (Mifflin-St Jeor), \(life) more for daily life, your steps, and your sport from the Compendium of Physical Activities; it falls up to \(dip) deep into a fast. Body fat comes from your BMI, the split between fat and lean from Forbes. Muscle: protein at \(protein) g a kilo (Helms, Refalo), lifting on a very low calorie diet (Bryner), sleep (Nedeltcheva). Bite plans down to a BMI of 20, and fasts of a week at most.")
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

/// Parts of a whole as one rounded bar, each in its color, 2 pt apart: what a day burns, or
/// how a loss splits between fat and lean.
private struct SegmentBar: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let shown = segments.filter { $0.value > 0 }
            let total = max(shown.reduce(0) { $0 + $1.value }, 1)
            let room = max(proxy.size.width - CGFloat(max(shown.count - 1, 0)) * 2, 0)
            HStack(spacing: 2) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: room * segment.value / total)
                }
            }
        }
        .frame(height: 14)
        .background(Theme.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
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
                let plot = CGRect(x: 8, y: 8, width: proxy.size.width - 16, height: proxy.size.height - 22)
                Canvas { context, _ in
                    func point(_ day: Int, _ kg: Double) -> CGPoint {
                        CGPoint(
                            x: plot.minX + plot.width * CGFloat(day) / CGFloat(count),
                            y: plot.minY + plot.height * CGFloat(1 - (kg - low) / max(high - low, 0.1))
                        )
                    }
                    // The goal, dashed, and the floor when it is in view, each named at its end.
                    let goalName = Text("Goal").font(.ui(11, .medium)).foregroundColor(Theme.onTarget)
                    let floorName = Text("BMI \("20")").font(.ui(11, .medium)).foregroundColor(Theme.over)
                    for (kg, color, name) in [(goalKg, Theme.onTarget, goalName), (floorKg, Theme.over, floorName)] where kg > low && kg < high {
                        var line = Path()
                        line.move(to: point(0, kg))
                        line.addLine(to: point(count, kg))
                        context.stroke(line, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                        context.draw(name, at: CGPoint(x: plot.maxX, y: point(count, kg).y - 3), anchor: .bottomTrailing)
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
                    // The day you look at, a handle to drag.
                    let shown = days.indices.contains(picked - 1) ? days[picked - 1] : start
                    let dot = point(shown.day, shown.tissueKg)
                    var mark = Path()
                    mark.move(to: CGPoint(x: dot.x, y: plot.minY))
                    mark.addLine(to: CGPoint(x: dot.x, y: plot.maxY))
                    context.stroke(mark, with: .color(Theme.hairline), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18)), with: .color(Theme.page))
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 7, y: dot.y - 7, width: 14, height: 14)), with: .color(Theme.ink))
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
