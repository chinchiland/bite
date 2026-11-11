import SwiftUI

/// From the fasting plan: what its day would change, in fat and in lean, so the goal here is the
/// body of that day.
struct BodyChange: Equatable {
    var fatKg: Double
    var leanKg: Double
}

/// What your body screen keeps between visits, as JSON under `bodymap`.
struct BodyMapSettings: Codable, Equatable {
    var sex: String
    var heightCm: Double
    var now: BodyNumbers
    var goal: BodyNumbers
    var outfit: String
    var move: String
    var tone: Int
    var waist: Double
    var neck: Double
    var hips: Double
    /// You typed your own tape measures, so they are no longer the example's.
    var taped: Bool
    /// You turned the bodies once: the hint has done its job.
    var turned: Bool
    /// You set your weight here: your weighings no longer move it.
    var weightTouched: Bool

    var frame: BodyFrame { BodyFrame(sex: Sex(rawValue: sex) ?? .female, heightCm: heightCm) }

    /// Both bodies kept inside what a human can be.
    mutating func settle() {
        heightCm = min(max(heightCm.rounded(), 140), 210)
        tone = min(max(tone, 0), BodyTone.all.count - 1)
        now = frame.settle(now, goal: false)
        goal = frame.settle(goal, goal: true)
    }

    /// The first visit: your numbers from the goal calculator and your weighings, your body fat
    /// estimated from them (Deurenberg), and a goal of the same muscle, leaner: eight points of
    /// body fat off, down to a lean but easy to keep 10% for a man and 18% for a woman, or a few
    /// kilos of muscle more when you are that lean already.
    static func fresh(currentKg: Double?) -> BodyMapSettings {
        let defaults = UserDefaults.standard
        let sex = Sex(rawValue: defaults.string(forKey: "body.sex") ?? "") ?? .female
        let height = defaults.object(forKey: "body.height") != nil ? defaults.double(forKey: "body.height") : (sex == .male ? 176 : 164)
        let kg = currentKg ?? (defaults.object(forKey: "body.weight") != nil ? defaults.double(forKey: "body.weight") : (sex == .male ? 80 : 65))
        let age = defaults.object(forKey: "body.age") != nil ? defaults.integer(forKey: "body.age") : 30
        let you = FastingBody(sex: sex, age: age, heightCm: height, weightKg: kg, moving: .usual(for: .light))
        let now = BodyNumbers(kg: kg, fat: (you.fatShare * 100).rounded())
        let leanest: Double = sex == .male ? 10 : 18, fat = max(now.fat - 8, leanest)
        let goal = fat < now.fat - 1
            ? BodyNumbers(kg: now.leanKg / (1 - fat / 100), fat: fat)
            : BodyNumbers(kg: kg + 3, fat: now.fat)
        var settings = BodyMapSettings(
            sex: sex.rawValue, heightCm: height, now: now, goal: goal,
            outfit: BodyOutfit.body.rawValue, move: BodyMove.auto.rawValue, tone: 1,
            waist: sex == .male ? 100 : 80, neck: sex == .male ? 40 : 33, hips: 100,
            taped: false, turned: false, weightTouched: false
        )
        settings.settle()
        return settings
    }
}

/// Your body: you now beside the body you want, moving on a lit stage, each made of two numbers,
/// a weight and a body fat. You pick yourself from bodies at your weight and the goal the same
/// way, and it says how long the change takes naturally. Under them, every body at your height,
/// muscle down and fat across. It shows a build, never a picture of you, and it says so.
struct BodyMapView: View {
    /// Your weight now: the trend of your weighings.
    let currentKg: Double?
    /// Opened from the fasting plan: the goal is the body of the day it shows.
    var change: BodyChange?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @AppStorage("bodymap") private var stored = ""

    @State private var map: BodyMapSettings
    @State private var studio = BodyStudio()
    @State private var stageOnScreen = true
    @State private var frameOpen = false
    @State private var tapeOpen: Bool
    /// A body in the chart became the goal.
    @State private var chosen = 0

    private static let lineupSize = CGSize(width: 58, height: 125)
    private static let ramp: [UInt32] = [0x6E1A14, 0xB3301F, 0xE2672B, 0xF4AD3B, 0xFFE28E]

    init(currentKg: Double?, change: BodyChange? = nil) {
        self.currentKg = currentKg
        self.change = change
        let defaults = UserDefaults.standard
        #if DEBUG
        // A screenshot that sets the screen up starts from a first visit, whatever the shot before kept.
        let staged = defaults.volatileDomain(forName: UserDefaults.argumentDomain).keys.contains { $0.hasPrefix("bodymap") && $0 != "bodymap" }
        let tape = defaults.bool(forKey: "bodymap.tape")
        #else
        let staged = false, tape = false
        #endif
        var map = (staged ? nil : defaults.string(forKey: "bodymap"))
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(BodyMapSettings.self, from: $0) }
            ?? BodyMapSettings.fresh(currentKg: currentKg)
        // Your weighings move you here, until you set your weight yourself.
        if let currentKg, !map.weightTouched, abs(currentKg - map.now.kg) >= 0.25 {
            map.now.kg = currentKg
        }
        if let change {
            let fat = max(map.now.fatKg + change.fatKg, 0.5), lean = max(map.now.leanKg + change.leanKg, 1)
            map.goal = BodyNumbers(kg: fat + lean, fat: 100 * fat / (fat + lean))
        }
        #if DEBUG
        // `-bodymap.now 85:30` and `-bodymap.goal 72:15` (kilos and body fat), `-bodymap.sex`,
        // `-bodymap.height`, `-bodymap.outfit body|clothes|fat`, `-bodymap.move auto|stand|walk|strike|flex`,
        // `-bodymap.tone 0...4` and `-bodymap.tape YES` set the screen up for screenshots.
        func numbers(_ key: String) -> BodyNumbers? {
            let parts = (defaults.string(forKey: key) ?? "").split(separator: ":").compactMap { Double($0) }
            return parts.count == 2 ? BodyNumbers(kg: parts[0], fat: parts[1]) : nil
        }
        if let sex = defaults.string(forKey: "bodymap.sex") { map.sex = sex }
        if defaults.object(forKey: "bodymap.height") != nil { map.heightCm = defaults.double(forKey: "bodymap.height") }
        if let now = numbers("bodymap.now") {
            map.now = now
            map.weightTouched = true
        }
        if let goal = numbers("bodymap.goal") { map.goal = goal }
        if let outfit = defaults.string(forKey: "bodymap.outfit") { map.outfit = outfit }
        if let move = defaults.string(forKey: "bodymap.move") { map.move = move }
        if defaults.object(forKey: "bodymap.tone") != nil { map.tone = defaults.integer(forKey: "bodymap.tone") }
        #endif
        map.settle()
        _map = State(initialValue: map)
        _tapeOpen = State(initialValue: tape)
    }

    private enum Which {
        case now, goal
    }

    private enum Anchor: Hashable {
        case stage, now, goal, chart, bottom
    }

    private var frame: BodyFrame { map.frame }
    private var sex: Sex { frame.sex }
    private var female: Bool { sex == .female }
    private var outfit: BodyOutfit { BodyOutfit(rawValue: map.outfit) ?? .body }
    private var move: BodyMove { BodyMove(rawValue: map.move) ?? .auto }
    private var tone: UInt32 { BodyTone.all[min(max(map.tone, 0), BodyTone.all.count - 1)] }
    private var heightText: String { "\(Int(map.heightCm)) " + "cm" }

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        stagePane
                            .glassGroup()
                            .id(Anchor.stage)
                        bodyPane(.now)
                            .glassGroup(after: 30)
                            .id(Anchor.now)
                        bodyPane(.goal)
                            .glassGroup(after: 30)
                            .id(Anchor.goal)
                        chartPane(reader)
                            .glassGroup(after: 30)
                            .id(Anchor.chart)
                        smallPrint
                            .padding(.top, 18)
                            .id(Anchor.bottom)
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .overlay(alignment: .top) { RoomTop() }
                .roomBackground()
                .navigationTitle("Your body")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .keyboardDone()
                .onAppear {
                    studio.scale = displayScale
                    studio.start()
                    request()
                }
                .onChange(of: map) { _, settings in
                    if let data = try? JSONEncoder().encode(settings), let text = String(data: data, encoding: .utf8) {
                        stored = text
                    }
                    request()
                }
                .onChange(of: studio.phase) { _, _ in request() }
                // Your weighings can arrive after the screen opens.
                .onChange(of: currentKg) { _, kilograms in
                    guard let kilograms, !map.weightTouched else { return }
                    update { $0.now.kg = kilograms }
                }
                .sensoryFeedback(Feel.click, trigger: chosen)
                #if DEBUG
                .task {
                    // `-anchor now|goal|chart|bottom` scrolls there, for screenshots.
                    guard let anchor = UserDefaults.standard.string(forKey: "anchor") else { return }
                    try? await Task.sleep(for: .seconds(1))
                    switch anchor {
                    case "now": reader.scrollTo(Anchor.now, anchor: .top)
                    case "goal": reader.scrollTo(Anchor.goal, anchor: .top)
                    case "chart": reader.scrollTo(Anchor.chart, anchor: .top)
                    case "bottom": reader.scrollTo(Anchor.bottom, anchor: .bottom)
                    default: break
                    }
                }
                #endif
            }
        }
    }

    /// Every change goes through here: both bodies settle back inside what a human can be.
    private func update(_ change: (inout BodyMapSettings) -> Void) {
        var next = map
        change(&next)
        next.settle()
        if next != map { map = next }
    }

    private func numbers(_ which: Which) -> BodyNumbers {
        which == .now ? map.now : map.goal
    }

    private func percentText(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private func bmi(_ body: BodyNumbers) -> Double {
        body.kg / pow(map.heightCm / 100, 2)
    }

    /// What the studio should draw now: the stage's two bodies, the pickers' and the chart's.
    private func request() {
        let frame = self.frame
        studio.show([(stageKey(map.now), frame, map.now), (stageKey(map.goal), frame, map.goal)])
        studio.want(lineupPictures(map.now), in: .now)
        studio.want(lineupPictures(map.goal), in: .goal)
        studio.want(chartPictures, in: .chart)
    }

    private func stageKey(_ body: BodyNumbers) -> String {
        let sliders = frame.sliders(body)
        return "\(map.sex)|\(Int((sliders.muscle * 1000).rounded()))|\(Int((sliders.weight * 1000).rounded()))"
    }

    // MARK: The stage

    private var stagePane: some View {
        VStack(alignment: .leading, spacing: 14) {
            frameRow
            stage
            stageLabels
            key
        }
    }

    /// Sex and height in one line, a tap to change them, and the skin tones beside it.
    private var frameRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Motion.respond) { frameOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: "\(sex.title) · \(heightText)")
                            .font(.ui(15))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .rotationEffect(.degrees(frameOpen ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Sex and height"))
                .accessibilityValue(Text(verbatim: "\(sex.title), \(heightText)"))
                Spacer(minLength: 4)
                tones
            }
            if frameOpen {
                VStack(spacing: 0) {
                    Picker("Sex", selection: sexBinding) {
                        ForEach(Sex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 12)
                    HStack(spacing: 10) {
                        Text("Height")
                            .font(.ui(16))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text(verbatim: heightText)
                            .font(.number(17))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText(value: map.heightCm))
                        StepButton(systemImage: "minus", label: "Shorter", value: map.heightCm) {
                            withAnimation(Motion.respond) { update { $0.heightCm -= 1 } }
                        }
                        StepButton(systemImage: "plus", label: "Taller", value: map.heightCm) {
                            withAnimation(Motion.respond) { update { $0.heightCm += 1 } }
                        }
                    }
                    .frame(minHeight: 54)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                }
                .transition(.opacity)
            }
        }
    }

    /// A woman and a man of the same numbers differ, so switching moves both bodies the way the
    /// average one moves: lighter and a little fatter as a woman.
    private var sexBinding: Binding<Sex> {
        Binding(
            get: { sex },
            set: { next in
                guard next != sex else { return }
                let kilos: Double = next == .female ? -12 : 12, fat: Double = next == .female ? 8 : -8
                withAnimation(Motion.respond) {
                    update {
                        $0.sex = next.rawValue
                        $0.now = BodyNumbers(kg: $0.now.kg + kilos, fat: $0.now.fat + fat)
                        $0.goal = BodyNumbers(kg: $0.goal.kg + kilos, fat: $0.goal.fat + fat)
                        $0.weightTouched = true
                        if !$0.taped {
                            $0.waist = next == .male ? 100 : 80
                            $0.neck = next == .male ? 40 : 33
                        }
                    }
                }
            }
        )
    }

    private var tones: some View {
        HStack(spacing: 0) {
            ForEach(BodyTone.all.indices, id: \.self) { index in
                let on = map.tone == index
                Button {
                    withAnimation(Motion.respond) { update { $0.tone = index } }
                } label: {
                    Circle()
                        .fill(Color(hex: BodyTone.all[index]))
                        .overlay { Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1) }
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .overlay {
                            if on { Circle().strokeBorder(Theme.ink, lineWidth: 1.5) }
                        }
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Skin tone"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(Feel.tick, trigger: map.tone)
    }

    /// Now and goal, alive under one light: the outfit above, the move below, a drag to turn.
    private var stage: some View {
        let ready = studio.stage.allSatisfy { $0 != nil }
        return ZStack {
            RadialGradient(colors: [Color(hex: 0xFFECD6).opacity(0.07), .clear], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 260)
            if let gpu = studio.gpu {
                BodyStageView(
                    gpu: gpu,
                    bodies: studio.stage,
                    outfit: outfit,
                    tone: tone,
                    move: reduceMotion && move == .auto ? .stand : move,
                    running: stageOnScreen && scenePhase == .active,
                    still: reduceMotion,
                    onTurn: {
                        guard !map.turned else { return }
                        withAnimation(.easeOut(duration: 0.4)) { map.turned = true }
                    }
                )
                .opacity(ready ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: ready)
            } else if studio.phase == .missing {
                HStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { index in
                        BodyFigureShape(build: BodyFigure.build(bmi: bmi(index == 0 ? map.now : map.goal)), female: female)
                            .fill(Color.white.opacity(0.85))
                            .aspectRatio(BodyFigure.grid.width / BodyFigure.grid.height, contentMode: .fit)
                            .padding(.vertical, 56)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ProgressView()
                    .tint(.white)
            }
            VStack(spacing: 0) {
                StageChoice(options: BodyOutfit.allCases, selection: outfitBinding) { $0.title }
                if !map.turned, studio.gpu != nil {
                    Label("Drag to turn", systemImage: "arrow.left.and.right")
                        .font(.ui(12))
                        .foregroundStyle(Color.white.opacity(0.54))
                        .padding(.top, 8)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                StageChoice(options: BodyMove.allCases, selection: moveBinding) { $0.title }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1 / 1.08, contentMode: .fit)
        .background(Color(hex: 0x0E0F11))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY > 60 } action: { stageOnScreen = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Your body now and your goal, moving. Drag to turn them."))
    }

    private var outfitBinding: Binding<BodyOutfit> {
        Binding(get: { outfit }, set: { value in update { $0.outfit = value.rawValue } })
    }

    private var moveBinding: Binding<BodyMove> {
        Binding(get: { move }, set: { value in update { $0.move = value.rawValue } })
    }

    private var stageLabels: some View {
        HStack(alignment: .top, spacing: 0) {
            stageLabel(when: Text("Now"), body: map.now, delta: nil)
            stageLabel(when: Text("Goal"), body: map.goal, delta: map.goal.kg - map.now.kg)
        }
        .accessibilityElement(children: .combine)
    }

    private func stageLabel(when: Text, body: BodyNumbers, delta: Double?) -> some View {
        VStack(spacing: 0) {
            when
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(body.kg.formatted(.number.precision(.fractionLength(1))))
                    .bigNumber(32)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: body.kg))
                Text(verbatim: "kg")
                    .font(.ui(16))
                    .foregroundStyle(Theme.secondary)
            }
            Text("\(percentText(body.fat)) fat")
                .font(.ui(15))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
            if let delta {
                Group {
                    if abs(delta) < 0.05 {
                        Text("Same weight")
                    } else {
                        Text(verbatim: (delta < 0 ? "−" : "+") + abs(delta).weightText)
                    }
                }
                .font(.ui(15, .medium))
                .monospacedDigit()
                .foregroundStyle(delta > 0.05 && map.goal.fatKg > map.now.fatKg ? Theme.watchText : Theme.onTarget)
                .contentTransition(.numericText(value: delta))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What changes, fat and lean, from now to the goal; on the fat map, what its colors mean.
    private var key: some View {
        VStack(spacing: 8) {
            if outfit == .fat {
                HStack(spacing: 8) {
                    Text("Thin fat")
                    LinearGradient(colors: Self.ramp.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
                        .frame(width: 110, height: 8)
                        .clipShape(Capsule())
                    Text("Thick fat")
                }
                .font(.ui(13))
                .foregroundStyle(Theme.tertiary)
                .accessibilityElement(children: .combine)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { keyItems }
                VStack(spacing: 6) { keyItems }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var keyItems: some View {
        keyItem("Fat mass", color: Theme.energy, from: map.now.fatKg, to: map.goal.fatKg)
        keyItem("Lean mass", color: Theme.protein, from: map.now.leanKg, to: map.goal.leanKg)
    }

    private func keyItem(_ title: LocalizedStringKey, color: Color, from: Double, to: Double) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text(title)
                .foregroundStyle(Theme.secondary)
            Text(verbatim: "\(from.formatted(.number.precision(.fractionLength(1)))) → \(to.weightText)")
                .fontWeight(.medium)
                .foregroundStyle(Theme.ink)
        }
        .font(.ui(14))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    // MARK: You now, your goal

    private func bodyPane(_ which: Which) -> some View {
        let body = numbers(which), level = frame.level(body)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(which == .now ? "You now" : "Your goal")
                    .font(.ui(20, .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                weightStepper(which)
            }
            Text(which == .now ? "Which one looks like you? Tap the closest, then slide to fine-tune." : "The body you want, at the weight you want. It stays as it is while you change the rest.")
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            picker(which)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(percentText(body.fat)) fat")
                    .font(.ui(22, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: body.fat))
                Text("\(level.title), \(body.leanKg.weightText) lean")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if level == .beyond {
                Text("That much lean mass at \(heightText) is more than most people build without drugs. At \(body.kg.weightText), the natural range starts at \(percentText(frame.naturalLeast(kg: body.kg).rounded(.up))) fat.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.watchText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if which == .now {
                tape
            } else {
                time
            }
        }
        .animation(Motion.settle, value: level == .beyond)
    }

    private func weightStepper(_ which: Which) -> some View {
        let kg = numbers(which).kg
        return HStack(spacing: 6) {
            StepButton(systemImage: "minus", label: "Lighter", value: kg) { step(which, by: -0.5) }
            Text(kg.weightText)
                .font(.number(17))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: kg))
                .frame(minWidth: 68)
            StepButton(systemImage: "plus", label: "Heavier", value: kg) { step(which, by: 0.5) }
        }
    }

    private func step(_ which: Which, by kilos: Double) {
        withAnimation(Motion.respond) {
            update {
                if which == .now {
                    $0.now.kg += kilos
                    $0.weightTouched = true
                } else {
                    $0.goal.kg += kilos
                }
            }
        }
    }

    private func setFat(_ which: Which, _ fat: Double) {
        update {
            if which == .now { $0.now.fat = fat } else { $0.goal.fat = fat }
        }
    }

    /// Five bodies at one weight, standing on the slider that sets the body fat: tap the closest,
    /// slide to fine-tune.
    private func picker(_ which: Which) -> some View {
        let body = numbers(which), choices = frame.choices(around: body)
        let range = sliderRange(body, choices: choices), size = Self.lineupSize
        let nearest = choices.min { abs(Double($0) - body.fat) < abs(Double($1) - body.fat) }
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - 28, 1), span = max(range.upperBound - range.lowerBound, 1)
                ForEach(choices, id: \.self) { fat in
                    let option = BodyNumbers(kg: body.kg, fat: Double(fat)), level = frame.level(option)
                    let on = fat == nearest && abs(Double(fat) - body.fat) <= 2
                    Button {
                        withAnimation(Motion.respond) { setFat(which, Double(fat)) }
                    } label: {
                        VStack(spacing: 1) {
                            BodyThumb(picture: lineupPicture(option), studio: studio, bmi: bmi(option), dim: level == .beyond)
                            Text(verbatim: percentText(Double(fat)))
                                .font(.ui(15, .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            Text(verbatim: level.short)
                                .font(.ui(12))
                                .foregroundStyle(level == .beyond ? Theme.tertiary : Theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: size.width + 8)
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                        .selectedFill(on, in: RoundedRectangle(cornerRadius: 16, style: .continuous), off: .clear)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Text("\(percentText(Double(fat))) body fat, \(level.title)"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .position(x: 14 + width * CGFloat((Double(fat) - range.lowerBound) / span), y: proxy.size.height / 2)
                }
            }
            .frame(height: size.height + 52)
            FatSlider(
                value: Binding(get: { body.fat }, set: { setFat(which, $0) }),
                range: range,
                natural: frame.naturalLeast(kg: body.kg),
                label: which == .now ? Text("Your body fat") : Text("Goal body fat")
            )
        }
    }

    /// The slider's ends: the five bodies with a little room either side, and always the body itself.
    private func sliderRange(_ body: BodyNumbers, choices: [Int]) -> ClosedRange<Double> {
        let fats = frame.fatRange(kg: body.kg)
        let first = Double(choices.first ?? fats.lowerBound), last = Double(choices.last ?? fats.upperBound)
        let low = min(max(Double(fats.lowerBound), first - 2), body.fat)
        let high = max(min(Double(fats.upperBound), last + 2), body.fat)
        return low...max(high, low + 1)
    }

    private func lineupPicture(_ body: BodyNumbers) -> BodyPicture {
        BodyPicture(frame: frame, body: body, tone: tone, width: Self.lineupSize.width, height: Self.lineupSize.height)
    }

    private func lineupPictures(_ body: BodyNumbers) -> [BodyPicture] {
        frame.choices(around: body).map { lineupPicture(BodyNumbers(kg: body.kg, fat: Double($0))) }
    }

    /// Your body fat from a tape measure, for when no body looks quite like you.
    private var tape: some View {
        let measured = frame.tape(waist: map.waist, neck: map.neck, hips: map.hips)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.settle) { tapeOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Not sure? Measure it")
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(tapeOpen ? 180 : 0))
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if tapeOpen {
                VStack(alignment: .leading, spacing: 12) {
                    Text(female ? "Relaxed, the tape level: the waist at the navel, the neck just under the larynx, the hips at their widest." : "Relaxed, the tape level: the waist at the navel, the neck just under the Adam's apple.")
                        .font(.ui(14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        tapeField("Waist", value: \.waist)
                        tapeField("Neck", value: \.neck)
                        if female { tapeField("Hips", value: \.hips) }
                    }
                    if let measured {
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(Motion.respond) { setFat(.now, measured.rounded()) }
                                Feel.play(.click)
                            } label: {
                                Text("Use \(percentText(measured.rounded()))")
                            }
                            .buttonStyle(SoftButtonStyle())
                            if !map.taped {
                                Text("Example numbers: put in yours.")
                                    .font(.ui(13))
                                    .foregroundStyle(Theme.tertiary)
                            }
                        }
                    } else {
                        Text("The waist must be wider than the neck.")
                            .font(.ui(14))
                            .foregroundStyle(Theme.watchText)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func tapeField(_ title: LocalizedStringKey, value: WritableKeyPath<BodyMapSettings, Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField(title, value: Binding(get: { map[keyPath: value] }, set: { measure in
                    guard measure > 0, measure < 250 else { return }
                    map[keyPath: value] = measure
                    map.taped = true
                }), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .font(.number(22))
                .foregroundStyle(Theme.ink)
                Text(verbatim: "cm")
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Theme.insetRadius, style: .continuous))
    }

    /// How long from now to the goal, naturally, and why.
    private var time: some View {
        let plan = frame.plan(from: map.now, to: map.goal)
        let when = Calendar.current.date(byAdding: .day, value: Int(plan.months * 30.44), to: .now) ?? .now
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if plan.months < 0.25 {
                    Text("You are there")
                } else if plan.months < 2 {
                    let weeks = max(1, Int((plan.months * 4.35).rounded()))
                    Text("About \(weeks) weeks")
                } else if plan.months > 30 {
                    Text("Years, not months")
                } else {
                    let months = Int(plan.months.rounded())
                    Text("About \(months) months")
                }
            }
            .bigNumber(28)
            .foregroundStyle(Theme.ink)
            .contentTransition(.numericText())
            if plan.months >= 0.25, plan.months <= 30 {
                Text("Around \(when.formatted(.dateTime.month(.wide).year()))")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
            why(plan)
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            if plan.leanChange < -1 {
                Text("This goal has \((-plan.leanChange).weightText) less lean mass than you: muscle you would lose. Keep lifting and eat enough protein to hold on to it.")
                    .font(.ui(14))
                    .foregroundStyle(Theme.watchText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func why(_ plan: BodyPlan) -> Text {
        let fat = abs(plan.fatChange).weightText, week = plan.fatPerWeek.weeklyWeightText
        let lean = plan.leanChange.weightText, month = plan.leanPerMonth.weeklyWeightText
        let loses = plan.fatChange < -0.05, gainsFat = plan.fatChange > 0.05, gainsLean = plan.leanChange > 0.3
        switch (loses, gainsFat, gainsLean) {
        case (true, _, true): return Text("Lose \(fat) of fat at about \(week) a week and add \(lean) of lean mass at about \(month) a month, both at once.")
        case (true, _, false): return Text("Lose \(fat) of fat at about \(week) a week.")
        case (_, true, true): return Text("Add \(lean) of lean mass at about \(month) a month, and put on \(fat) of fat.")
        case (_, true, false): return Text("Put on \(fat) of fat.")
        case (_, _, true): return Text("Add \(lean) of lean mass at about \(month) a month.")
        default: return Text("Same body, nothing to change.")
        }
    }

    // MARK: Every body

    /// The chart's grid, in points, so its marks land on the bodies without measuring them. The
    /// names stay put on the left and the bodies scroll beside them, like a frozen column.
    private enum Grid {
        static let name: CGFloat = 96
        static let cell: CGFloat = 84
        static let gap: CGFloat = 2
        static let head: CGFloat = 22
        static let row: CGFloat = 166
        static let thumb = CGSize(width: 70, height: 136)

        static func x(_ column: Int) -> CGFloat { CGFloat(column) * (cell + gap) + cell / 2 }
        static func y(_ row: Int) -> CGFloat { head + gap + CGFloat(row) * (Self.row + gap) + 4 + thumb.height / 2 }
    }

    /// The rows' muscle, as the fat-free mass index for the height, and the columns' body fat.
    private var rows: [Double] { female ? [14, 15.5, 17, 18.5, 20] : [17, 19, 21, 23, 25] }
    private var columns: [Double] { female ? [16, 20, 24, 28, 32, 36, 40, 45] : [8, 12, 16, 20, 25, 30, 35, 40] }

    private struct ChartColumn: Hashable {
        let index: Int
    }

    /// The column halfway between you and your goal.
    private var focusColumn: Int {
        let middle = (map.now.fat + map.goal.fat) / 2
        return columns.indices.min { abs(columns[$0] - middle) < abs(columns[$1] - middle) } ?? 0
    }

    private func cellBody(row: Int, column: Int) -> BodyNumbers {
        let lean = frame.leanKg(index: rows[row]), fat = columns[column]
        return BodyNumbers(kg: lean / (1 - fat / 100), fat: fat)
    }

    private var chartPictures: [BodyPicture] {
        rows.indices.flatMap { row in
            columns.indices.map { column in
                BodyPicture(frame: frame, body: cellBody(row: row, column: column), tone: tone, width: Grid.thumb.width, height: Grid.thumb.height)
            }
        }
    }

    private func chartPane(_ reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Every body at \(heightText)")
            Text("Muscle down, fat across, the weight under each. The dashed line is \(map.now.kg.weightText), the dot is you, the green ring your goal. Tap a body to make it your goal.")
                .font(.ui(14))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 0) {
                rowNames
                ScrollViewReader { across in
                    ScrollView(.horizontal) {
                        chart(reader)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.trailing, Theme.margin, for: .scrollContent)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    // The bodies fade as they pass under the names.
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05)], startPoint: .leading, endPoint: .trailing)
                    }
                    .padding(.trailing, -Theme.margin)
                    // It opens on you and your goal, wherever they stand across.
                    .onAppear {
                        // A turn of the run loop first, so the row is laid out before it scrolls.
                        let column = ChartColumn(index: focusColumn)
                        DispatchQueue.main.async { across.scrollTo(column, anchor: .center) }
                    }
                    .onChange(of: map.sex) { _, _ in across.scrollTo(ChartColumn(index: focusColumn), anchor: .center) }
                }
            }
        }
    }

    /// Each row's muscle, by name and lean mass, beside its bodies.
    private var rowNames: some View {
        VStack(alignment: .leading, spacing: Grid.gap) {
            Color.clear
                .frame(height: Grid.head)
            ForEach(rows.indices, id: \.self) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: frame.level(index: rows[row]).title)
                        .font(.ui(14, .medium))
                        .foregroundStyle(Theme.ink)
                    Text("\(frame.leanKg(index: rows[row]).weightText) lean")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.trailing, 8)
                .frame(width: Grid.name, height: Grid.row, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func chart(_ reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: Grid.gap) {
            HStack(spacing: Grid.gap) {
                ForEach(columns.indices, id: \.self) { column in
                    Text(verbatim: percentText(columns[column]))
                        .font(.ui(13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .frame(width: Grid.cell, height: Grid.head)
                        .id(ChartColumn(index: column))
                }
            }
            .accessibilityHidden(true)
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: Grid.gap) {
                    ForEach(columns.indices, id: \.self) { column in
                        chartCell(row: row, column: column, reader: reader)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            chartMarks
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func chartCell(row: Int, column: Int, reader: ScrollViewProxy) -> some View {
        let body = cellBody(row: row, column: column)
        let picture = BodyPicture(frame: frame, body: body, tone: tone, width: Grid.thumb.width, height: Grid.thumb.height)
        return Button {
            withAnimation(Motion.respond) {
                update { $0.goal = BodyNumbers(kg: (body.kg * 2).rounded() / 2, fat: body.fat) }
            }
            chosen += 1
            withAnimation(reduceMotion ? nil : Motion.settle) { reader.scrollTo(Anchor.stage, anchor: .top) }
        } label: {
            VStack(spacing: 2) {
                BodyThumb(picture: picture, studio: studio, bmi: bmi(body))
                Text(verbatim: "\(Int(body.kg.rounded())) kg")
                    .font(.ui(14, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 4)
            .frame(width: Grid.cell, height: Grid.row, alignment: .top)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Make \(body.kg.weightText) at \(percentText(body.fat)) fat your goal"))
    }

    /// Over the grid: the dashed line of your weight, you as a dot, your goal as a ring, and the
    /// way between them in green.
    private var chartMarks: some View {
        let rows = self.rows, columns = self.columns, frame = self.frame
        let now = map.now, goal = map.goal
        let width = Grid.x(columns.count - 1) + Grid.cell / 2, height = Grid.y(rows.count - 1) + Grid.row
        // A body fat to a place across: between the columns, or on past the first and the last.
        func x(_ fat: Double) -> CGFloat {
            var low = 0
            while low < columns.count - 2, fat > columns[low + 1] { low += 1 }
            let t = (fat - columns[low]) / (columns[low + 1] - columns[low])
            return Grid.x(low) + CGFloat(t) * (Grid.x(low + 1) - Grid.x(low))
        }
        // A body to its place: down by its muscle between the rows, across by its fat.
        func spot(_ body: BodyNumbers) -> CGPoint {
            let index = frame.index(leanKg: body.leanKg)
            var row = 0.0
            if index >= rows[rows.count - 1] {
                row = Double(rows.count - 1)
            } else if index > rows[0] {
                var r = 0
                while r < rows.count - 2, index > rows[r + 1] { r += 1 }
                row = Double(r) + (index - rows[r]) / (rows[r + 1] - rows[r])
            }
            let r0 = Int(row), r1 = min(r0 + 1, rows.count - 1), t = CGFloat(row - Double(r0))
            return CGPoint(x: x(body.fat), y: Grid.y(r0) * (1 - t) + Grid.y(r1) * t)
        }
        return Canvas { context, _ in
            let me = spot(now), aim = spot(goal)
            let line = rows.indices.map { row in CGPoint(x: x(100 * (1 - frame.leanKg(index: rows[row]) / now.kg)), y: Grid.y(row)) }
            let left = Grid.x(0) - 34, right = Grid.x(columns.count - 1) + 34
            var clipped = context
            clipped.clip(to: Path(CGRect(x: left, y: 0, width: right - left, height: height)))
            var dashed = Path()
            dashed.addLines(line)
            clipped.stroke(dashed, with: .color(Theme.ink.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
            var way = Path()
            way.move(to: me)
            way.addLine(to: aim)
            clipped.stroke(way, with: .color(Theme.onTarget.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            // The weight, named where its line is farthest from you, so the label never covers the dot.
            if let far = line.filter({ $0.x >= left + 10 && $0.x <= right - 10 }).max(by: { hypot($0.x - me.x, $0.y - me.y) < hypot($1.x - me.x, $1.y - me.y) }) {
                let label = context.resolve(Text(verbatim: now.kg.weightText).font(.ui(13, .semibold)).foregroundStyle(Theme.page))
                let size = label.measure(in: CGSize(width: 200, height: 40))
                let pill = CGRect(x: min(max(far.x - size.width / 2 - 8, left), right - size.width - 16), y: far.y - 11, width: size.width + 16, height: 22)
                context.fill(Path(roundedRect: pill, cornerRadius: 11), with: .color(Theme.ink.opacity(0.95)))
                context.draw(label, at: CGPoint(x: pill.midX, y: pill.midY))
            }
            let ring = Path(ellipseIn: CGRect(x: aim.x - 10, y: aim.y - 10, width: 20, height: 20))
            context.fill(ring, with: .color(Theme.page.opacity(0.6)))
            context.stroke(ring, with: .color(Theme.onTarget), lineWidth: 3)
            context.fill(Path(ellipseIn: CGRect(x: me.x - 11, y: me.y - 11, width: 22, height: 22)), with: .color(Theme.page.opacity(0.8)))
            context.fill(Path(ellipseIn: CGRect(x: me.x - 8, y: me.y - 8, width: 16, height: 16)), with: .color(Theme.ink))
        }
        .frame(width: width, height: height)
    }

    // MARK: Small print

    private var smallPrint: some View {
        // Percentages go in as values, so each language writes its own: 0.7%, 0,7 %.
        let share = { (percent: Double) in (percent / 100).formatted(.percent.precision(.fractionLength(0...1))) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Lean mass is everything that isn't fat: muscle, bone, organs and water. The muscle levels use the fat-free mass index adjusted for height (Kouri, 1995): about 25 is as much as most men build without drugs, about 21 for women. The tape is the US Navy's method (Hodgdon and Beckett, 1984), right to within about 3 or 4 points.")
            Text("The time assumes you lose about \(share(0.7)) of your weight a week, between \(share(0.5)) and \(share(1)), which keeps muscle (Helms, 2014), and gain lean mass at typical natural rates, slower the more you have: about 1 kg a month for a man new to lifting, half that for a woman. Doing both at once works best when you are new to lifting or carry some fat.")
            Text("The body is MakeHuman's (CC0), with its own skeleton and skin weights, shaped from these numbers by its muscle and weight targets. It shows a build, not you: real bodies carry fat in their own places.")
        }
        .font(.ui(13))
        .foregroundStyle(Theme.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
    }
}

/// A small choice floating on the stage: a dark capsule of words, the chosen one lit.
private struct StageChoice<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(Motion.respond) { selection = option }
                } label: {
                    Text(verbatim: title(option))
                        .font(.ui(13, .medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.white.opacity(0.16))
                                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.42), in: Capsule())
        .sensoryFeedback(Feel.tick, trigger: selection)
    }
}
