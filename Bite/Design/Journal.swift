import SwiftUI

// MARK: - The dotted ring

/// Calories as rings of dots, a halftone: lit in the colors of where the calories come from
/// (protein, carbs, fat), quiet gray for what is still to eat. Each macro wide enough to hold
/// one carries its glyph on a disc in the middle of its arc. The dots light up round the ring
/// when it appears, each glyph as the light reaches it. Past the goal, the overflow runs round
/// the outer ring in red.
struct DottedRing: View {
    struct Part: Equatable {
        /// Share of the whole ring, 0 to 1.
        var share: Double
        var color: Color
        /// The macro this part is, for its glyph; nil for calories with no macros.
        var macro: Macro? = nil
    }

    let parts: [Part]
    /// How far past the whole the calories go, as a share of the ring (0 when within it).
    var overflow: Double = 0
    /// What the ring sits on, so a glyph's disc can cut its dots cleanly.
    var surface: Color = Theme.page
    /// Each change sends one warmer light round the lit dots: the day just landed on target.
    var glint = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    var body: some View {
        let shares = Shares(parts)
        let still = reduceMotion
        DotRingCanvas(shares: shares, overflow: overflow, surface: surface, reveal: reveal)
            .animation(reduceMotion ? nil : Motion.count, value: shares)
            .animation(reduceMotion ? nil : Motion.count, value: overflow)
            .keyframeAnimator(initialValue: -1.0, trigger: glint) { ring, sweep in
                ring.environment(\.ringGlint, still ? -1 : sweep)
            } keyframes: { _ in
                // Starts just before twelve and ends past the last lit dot, then rests unseen.
                LinearKeyframe(-0.1, duration: 0.01)
                CubicKeyframe(1.15, duration: 0.8)
                LinearKeyframe(-1, duration: 0.01)
            }
            .onAppear {
                guard reveal < 1 else { return }
                if reduceMotion {
                    reveal = 1
                } else {
                    withAnimation(Motion.reveal.delay(0.1)) { reveal = 1 }
                }
            }
    }

    /// The ring's four possible parts, zero when absent, so they can animate from one value to
    /// the next: protein, carbs, fat, and calories with no macros.
    struct Shares: Equatable {
        var protein = 0.0
        var carbs = 0.0
        var fat = 0.0
        var plain = 0.0

        init(protein: Double = 0, carbs: Double = 0, fat: Double = 0, plain: Double = 0) {
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.plain = plain
        }

        init(_ parts: [Part]) {
            for part in parts {
                switch part.macro {
                case .protein: protein += part.share
                case .carbs: carbs += part.share
                case .fat: fat += part.share
                case nil: plain += part.share
                }
            }
        }

        /// Back to drawable parts, in the ring's order, the empty ones left out.
        var parts: [Part] {
            [
                Part(share: protein, color: Theme.protein, macro: .protein),
                Part(share: carbs, color: Theme.carbs, macro: .carbs),
                Part(share: fat, color: Theme.fat, macro: .fat),
                Part(share: plain, color: Theme.tertiary),
            ]
            .filter { $0.share > 0.0005 }
        }
    }

    /// The day's calories against its goal, split by where they came from.
    static func day(_ nutrients: Nutrients, goal: Double) -> (parts: [Part], overflow: Double) {
        guard goal > 0, nutrients.kcal > 0 else { return ([], 0) }
        let progress = nutrients.kcal / goal
        return (food(nutrients, filling: min(progress, 1)), min(max(progress - 1, 0), 1))
    }

    /// A food's own calories as the whole ring, split by where they come from.
    static func food(_ nutrients: Nutrients, filling whole: Double = 1) -> [Part] {
        let split = nutrients.energySplit
        let total = split.protein + split.carbs + split.fat
        guard total > 0 else {
            // Calories with no macros (a quick add): one quiet part.
            return nutrients.kcal > 0 ? [Part(share: whole, color: Theme.tertiary)] : []
        }
        return [
            Part(share: split.protein * whole, color: Theme.protein, macro: .protein),
            Part(share: split.carbs * whole, color: Theme.carbs, macro: .carbs),
            Part(share: split.fat * whole, color: Theme.fat, macro: .fat),
        ]
    }
}

private struct RingGlintKey: EnvironmentKey {
    static let defaultValue = -1.0
}

extension EnvironmentValues {
    /// Where the ring's warmer light is, as a share of its lit arc; below 0 when there is none.
    var ringGlint: Double {
        get { self[RingGlintKey.self] }
        set { self[RingGlintKey.self] = newValue }
    }
}

/// Draws the rings. Animating `reveal` sweeps the colors in from twelve o'clock; animating the
/// shares and the overflow grows or shrinks each part from where it was.
private struct DotRingCanvas: View, Animatable {
    var shares: DottedRing.Shares
    var overflow: Double
    let surface: Color
    var reveal: Double

    var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>,
        AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(reveal, overflow),
                AnimatablePair(AnimatablePair(shares.protein, shares.carbs), AnimatablePair(shares.fat, shares.plain))
            )
        }
        set {
            reveal = newValue.first.first
            overflow = newValue.first.second
            shares = DottedRing.Shares(
                protein: newValue.second.first.first,
                carbs: newValue.second.first.second,
                fat: newValue.second.second.first,
                plain: newValue.second.second.second
            )
        }
    }

    private var parts: [DottedRing.Part] { shares.parts }
    /// Where the warmer light is, as a share of the lit arc; below 0 when there is none.
    @Environment(\.ringGlint) private var glint

    private static let rings = 6
    // Drawn on a 176 pt square and scaled: six rings from radius 50 out to 82.5.
    private static let inner: CGFloat = 50
    private static let ringGap: CGFloat = 6.5
    private static let dot: CGFloat = 4.6
    private static let pitch: CGFloat = 7.4
    /// A glyph's disc sits across the middle rings and leaves the outer one free for overflow.
    private static let discRadius: CGFloat = 14
    /// About three quarters of the disc, so the glyph reads without the disc growing.
    private static let glyphSize: CGFloat = 21
    /// The narrowest arc that carries a glyph.
    private static let glyphMinimum = 0.08

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 176
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let diameter = Self.dot * unit
            let parts = self.parts
            let colored = parts.reduce(0) { $0 + max($1.share, 0) }
            let boundaries = Self.boundaries(parts.map(\.share), colored: colored)
            for ring in 0..<Self.rings {
                let radius = (Self.inner + Self.ringGap * CGFloat(ring)) * unit
                let count = max(Int((2 * .pi * radius / (Self.pitch * unit)).rounded()), 12)
                let step = 1 / Double(count)
                let isOuter = ring == Self.rings - 1
                for index in 0..<count {
                    let position = Double(index) * step
                    if boundaries.contains(where: { Self.distance(position, $0) < step / 2 }) { continue }
                    var lit = Self.color(at: position, in: parts)
                    if lit != nil, position > reveal * colored { lit = nil }
                    if isOuter, overflow > 0, position < overflow * reveal { lit = Theme.over }
                    let angle = position * 2 * .pi - .pi / 2
                    let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                    // The light lifts the lit dots it passes, a little larger and paler.
                    let warmth = lit == nil || glint < -0.5 ? 0 : max(0, 1 - abs(position - glint * colored) / 0.07)
                    let grown = diameter * (1 + 0.3 * warmth)
                    let rect = CGRect(x: point.x - grown / 2, y: point.y - grown / 2, width: grown, height: grown)
                    context.fill(Path(ellipseIn: rect), with: .color(lit ?? Theme.ringRest))
                    if warmth > 0 {
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.45 * warmth)))
                    }
                }
            }
            drawGlyphs(in: context, center: center, unit: unit, colored: colored)
        }
        .accessibilityHidden(true)
    }

    /// Each macro's glyph on a disc in the middle of its arc, appearing as the light reaches it.
    private func drawGlyphs(in context: GraphicsContext, center: CGPoint, unit: CGFloat, colored: Double) {
        let middle = (Self.inner + Self.ringGap * 2.5) * unit
        let radius = Self.discRadius * unit
        let side = Self.glyphSize * unit
        var start = 0.0
        for part in parts where part.share > 0 {
            defer { start += part.share }
            guard let macro = part.macro, part.share >= Self.glyphMinimum else { continue }
            let position = start + part.share / 2
            let shown = min(max((reveal * colored - position) / 0.05, 0), 1)
            guard shown > 0 else { continue }
            let angle = position * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + middle * CGFloat(cos(angle)), y: center.y + middle * CGFloat(sin(angle)))
            var disc = context
            disc.opacity = shown
            // A ring of the surface first, so the disc stands clear of the dots around it.
            let clear = radius + 2 * unit
            disc.fill(Path(ellipseIn: CGRect(x: point.x - clear, y: point.y - clear, width: clear * 2, height: clear * 2)), with: .color(surface))
            let face = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            disc.fill(face, with: .color(macro.tileFill))
            let glyph = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
            MacroGlyph.draw(macro, in: &disc, rect: glyph, color: macro.glyphColor)
        }
    }

    /// The part a position falls in, or nil for the part of the ring still to eat.
    private static func color(at position: Double, in parts: [DottedRing.Part]) -> Color? {
        var start = 0.0
        for part in parts where part.share > 0 {
            if position < start + part.share { return part.color }
            start += part.share
        }
        return nil
    }

    /// Where one part meets the next, each leaving one dot empty so the parts read apart. A
    /// sliver (under 4% of the ring) gets no gaps: two gaps would swallow its few dots and
    /// leave a notch.
    private static func boundaries(_ shares: [Double], colored: Double) -> [Double] {
        var segments = shares.filter { $0 > 0 }
        guard colored > 0 else { return [] }
        if colored < 0.999 { segments.append(1 - colored) }
        guard segments.count > 1 else { return [] }
        var result: [Double] = []
        var start = 0.0
        for (index, share) in segments.enumerated() {
            let previous = segments[(index + segments.count - 1) % segments.count]
            if share >= 0.04, previous >= 0.04 { result.append(start) }
            start += share
        }
        return result
    }

    /// Distance round the ring, so 0.99 and 0.01 are close.
    private static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }
}

// MARK: - Macros

/// The three macros as one quiet list beside the ring. Each line is the macro's glyph on its
/// tile, its name and its grams. On Today the grams sit over the day's target and a rule under
/// the line fills toward it; on a food the line ends with the macro's share of the calories.
struct MacroList: View {
    let nutrients: Nutrients
    let targets: MacroTargets
    var showsTarget = true
    /// The day's fiber, when enough of the day has it on record, and its target.
    var fiber: FiberDay? = nil
    var fiberTarget: Double = 28

    var body: some View {
        VStack(alignment: .leading, spacing: showsTarget ? 2 : 0) {
            ForEach(Macro.allCases, id: \.self) { macro in
                if showsTarget {
                    targetRow(macro)
                } else {
                    shareRow(macro)
                        .overlay(alignment: .top) {
                            if macro != .protein {
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                        }
                }
            }
            if showsTarget, let fiber {
                fiberRow(fiber)
                    .transition(.opacity)
            }
        }
    }

    /// Fiber, quieter than the macros: its name in gray, a thin ink rule that fills toward
    /// the target and simply stays full past it.
    private func fiberRow(_ day: FiberDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Fiber")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(day.grams.gramsText)
                        .font(.number(15))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: day.grams))
                    Text(verbatim: " / \(fiberTarget.kcalText) g")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .frame(height: 34)
            ProgressBar(value: fiberTarget > 0 ? day.grams / fiberTarget : 0, color: Theme.ink.opacity(0.45), height: 2)
            if day.isPartial {
                Text("from \(day.known) of \(day.counted) foods")
                    .font(.ui(12))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)
            }
        }
        .padding(.leading, 36)
        .animation(.smooth, value: day.grams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fiber: \(day.grams.gramsText) of at least \(fiberTarget.kcalText) grams")
    }

    private func targetRow(_ macro: Macro) -> some View {
        let grams = macro.grams(in: nutrients)
        let target = macro.target(in: targets)
        // Past the target is news for carbs and fat; more protein is fine.
        let over = macro != .protein && target > 0 && grams > target * 1.05
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                MacroTile(macro: macro)
                name(macro)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(grams.gramsText)
                        .font(.number(17))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: grams))
                    Text(verbatim: " / \(target.kcalText) g")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                }
                .lineLimit(1)
                .fixedSize()
            }
            .frame(height: 47)
            ProgressBar(value: target > 0 ? grams / target : 0, color: over ? Theme.over : macro.color, height: 3)
                .padding(.leading, 36)
        }
        .animation(.smooth, value: grams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.title): \(grams.gramsText) of \(target.kcalText) grams")
    }

    private func shareRow(_ macro: Macro) -> some View {
        let grams = macro.grams(in: nutrients)
        let share = macro.share(in: nutrients)
        return HStack(spacing: 8) {
            MacroTile(macro: macro)
            name(macro)
            Text(verbatim: "\(grams.gramsText) g")
                .font(.number(17))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: grams))
                .lineLimit(1)
                .fixedSize()
            Text("\((share * 100).safeInt)%")
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: 46)
        .animation(.smooth, value: grams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.title): \(grams.gramsText) grams")
    }

    /// The name takes the room the numbers leave (no spacer, whose spacing would eat it), so
    /// "Protéines" and "Glucides" stay whole beside four-character grams.
    private func name(_ macro: Macro) -> some View {
        Text(macro.title)
            .font(.ui(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The dotted ring with the calories in its middle, the macros listed beside it. The same block
/// on Today (the day against its goal) and on a food (the food's own calories).
struct MacroBlock: View {
    let nutrients: Nutrients
    let targets: MacroTargets
    let ring: [DottedRing.Part]
    var overflow: Double = 0
    let number: Double
    let unit: LocalizedStringKey
    var showsTarget = true
    /// What the block sits on: the paper on Today, a white sheet on a food.
    var surface: Color = Theme.page
    /// Bumped when a log lands today on target: the ring warms once.
    var glint = 0
    /// The day's fiber line, on Today only.
    var fiber: FiberDay? = nil
    var fiberTarget: Double = 28

    /// Under 345 pt across (a 375 pt phone, or Display Zoom), the ring steps down to 124.
    @State private var narrow = false

    var body: some View {
        let side: CGFloat = narrow ? 124 : 150
        HStack(alignment: .center, spacing: narrow ? 12 : 16) {
            ZStack {
                DottedRing(parts: ring, overflow: overflow, surface: surface, glint: glint)
                // Inside the inner ring, which leaves about 81 pt across the middle and less below
                // it: the number steps down for four digits, the unit takes a second line when a
                // language needs it ("kcal" over "mangées"), so each word stays short.
                // The number's line leaves room under its digits; a negative gap sets the unit
                // right under them, as one label.
                VStack(spacing: -3) {
                    Text(number.kcalText)
                        .font(.number(30, .medium))
                        .numberTracking(30)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: number))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.ui(12))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: side * 0.48)
                .accessibilityElement(children: .combine)
            }
            .frame(width: side, height: side)
            .animation(Motion.count, value: number)

            MacroList(nutrients: nutrients, targets: targets, showsTarget: showsTarget, fiber: fiber, fiberTarget: fiberTarget)
                .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 345 } action: { narrow = $0 }
    }
}

// MARK: - Activity

/// What Apple Health can tell Today.
enum HealthState: Equatable {
    case unavailable
    case notConnected
    case connected(DayActivity)
}

/// Burned and steps as soft chips under the macros (or the way to connect Health), and the day's
/// water: one tap a glass, the chip filling toward the day's glasses.
struct ActivityChips: View {
    let health: HealthState
    var water: Int = 0
    var waterGoal: Int = 8
    var onWater: (() -> Void)? = nil
    var onWaterRemove: (() -> Void)? = nil
    let onConnect: () -> Void

    /// Bumped by the glass that meets the day's goal, never by the ones after it.
    @State private var goalGlass = 0

    var body: some View {
        FlowLayout(spacing: 8) {
            switch health {
            case .unavailable:
                EmptyView()
            case .notConnected:
                Button(action: onConnect) {
                    chip(systemImage: "heart.fill", color: Theme.burned) {
                        Text("Connect Health")
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityHint("Shows your steps and burned calories from Apple Health")
            case .connected(let activity):
                chip(systemImage: "flame.fill", color: Theme.burned) {
                    Text("\(activity.activeKcal.kcalText) kcal burned")
                }
                chip(systemImage: "shoeprints.fill", color: Theme.steps) {
                    Text("\(activity.steps.countText) steps")
                }
            }
            if let onWater {
                waterChip(onWater)
            }
        }
    }

    private func waterChip(_ add: @escaping () -> Void) -> some View {
        let progress = waterGoal > 0 ? min(Double(water) / Double(waterGoal), 1) : 0
        return Button(action: add) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.water)
                    .symbolEffect(.bounce, value: goalGlass)
                Group {
                    if water == 0 {
                        Text("Water")
                    } else {
                        Text("\(water) glasses")
                    }
                }
                .font(.ui(14, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(water)))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                // The chip fills with water toward the day's glasses.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Theme.fill
                        Theme.water.opacity(0.2)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .clipShape(Capsule())
            }
            .animation(Motion.settle, value: water)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .sensoryFeedback(trigger: water) { old, new in
            guard new > old else { return nil }
            return new == waterGoal ? Feel.reached : Feel.drop
        }
        .onChange(of: water) { old, new in
            if new > old, new == waterGoal { goalGlass += 1 }
        }
        .contextMenu {
            if let onWaterRemove, water > 0 {
                Button("Remove a glass", systemImage: "minus", action: onWaterRemove)
            }
        }
        .accessibilityLabel("Water: \(water) of \(waterGoal) glasses")
        .accessibilityHint("Adds a glass")
    }

    private func chip(systemImage: String, color: Color, @ViewBuilder label: () -> Text) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            label()
                .font(.ui(14, .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Theme.fill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Day verdicts

extension DayVerdict {
    /// The dot beside a day: green on target, red over, gray light.
    var dotColor: Color {
        switch self {
        case .empty: .clear
        case .light: Theme.light
        case .onTarget: Theme.onTarget
        case .over: Theme.over
        }
    }
}

// MARK: - Chrome on photos

/// A round button that floats on a cover: dark glass on a photo, light glass on paper.
struct GlassCircleButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var onPhoto = true
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(onPhoto ? Color.white : Theme.ink)
                .frame(width: size, height: size)
                .coverGlass(in: Circle(), onPhoto: onPhoto)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

extension View {
    /// Glass for chrome that sits on a cover: dark on a photo so white words read on any
    /// picture, light on paper so ink words do.
    func coverGlass<S: Shape>(in shape: S, onPhoto: Bool) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(onPhoto ? Color.black.opacity(0.12) : Color.white.opacity(0.35))
            }
            .environment(\.colorScheme, onPhoto ? .dark : .light)
        }
        .overlay {
            shape.stroke(onPhoto ? Color.white.opacity(0.22) : Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}
