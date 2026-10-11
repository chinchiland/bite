import SwiftUI

// MARK: - The dotted ring

/// Calories as rings of dots, a halftone: lit in the colors of where the calories come from
/// (protein, carbs, fat), quiet gray for what is still to eat. The dots light up round the
/// ring when it appears. Past the goal, the overflow runs round the outer ring in red.
struct DottedRing: View {
    struct Part: Equatable {
        /// Share of the whole ring, 0 to 1.
        var share: Double
        var color: Color
    }

    let parts: [Part]
    /// How far past the whole the calories go, as a share of the ring (0 when within it).
    var overflow: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    var body: some View {
        DotRingCanvas(parts: parts, overflow: overflow, reveal: reveal)
            .onAppear {
                guard reveal < 1 else { return }
                if reduceMotion {
                    reveal = 1
                } else {
                    withAnimation(.easeOut(duration: 1.1).delay(0.15)) { reveal = 1 }
                }
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
            Part(share: split.protein * whole, color: Theme.protein),
            Part(share: split.carbs * whole, color: Theme.carbs),
            Part(share: split.fat * whole, color: Theme.fat),
        ]
    }
}

/// Draws the rings. Animating `reveal` sweeps the colors in from twelve o'clock.
private struct DotRingCanvas: View, Animatable {
    let parts: [DottedRing.Part]
    let overflow: Double
    var reveal: Double

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    private static let rings = 6
    // Drawn on a 176 pt square and scaled: six rings from radius 50 out to 82.5.
    private static let inner: CGFloat = 50
    private static let ringGap: CGFloat = 6.5
    private static let dot: CGFloat = 4.6
    private static let pitch: CGFloat = 7.4

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 176
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let diameter = Self.dot * unit
            let colored = parts.reduce(0) { $0 + max($1.share, 0) }
            // Where one part ends and the next starts; each boundary leaves one dot empty.
            var boundaries: [Double] = []
            if colored > 0 {
                var running = 0.0
                for part in parts where part.share > 0 {
                    boundaries.append(running)
                    running += part.share
                }
                if running < 0.999 { boundaries.append(running) }
            }
            for ring in 0..<Self.rings {
                let radius = (Self.inner + Self.ringGap * CGFloat(ring)) * unit
                let count = max(Int((2 * .pi * radius / (Self.pitch * unit)).rounded()), 12)
                let step = 1 / Double(count)
                let isOuter = ring == Self.rings - 1
                for index in 0..<count {
                    let position = Double(index) * step
                    if boundaries.contains(where: { Self.distance(position, $0) < step / 2 }) { continue }
                    var lit = partColor(at: position)
                    if lit != nil, position > reveal * colored { lit = nil }
                    if isOuter, overflow > 0, position < overflow * reveal { lit = Theme.over }
                    let angle = position * 2 * .pi - .pi / 2
                    let point = CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                    let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(lit ?? Theme.ringRest))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The part a position falls in, or nil for the part of the ring still to eat.
    private func partColor(at position: Double) -> Color? {
        var start = 0.0
        for part in parts where part.share > 0 {
            if position < start + part.share { return part.color }
            start += part.share
        }
        return nil
    }

    /// Distance round the ring, so 0.99 and 0.01 are close.
    private static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }
}

// MARK: - Macros

/// The three macros stacked: the name, the grams (over the day's target on Today), and a thin
/// bar filled toward the target in the macro's color.
struct MacroBars: View {
    let nutrients: Nutrients
    let targets: MacroTargets
    var showsTarget = true

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(Macro.allCases, id: \.self) { macro in
                row(macro)
            }
        }
    }

    private func row(_ macro: Macro) -> some View {
        let grams = macro.grams(in: nutrients)
        let target = macro.target(in: targets)
        return VStack(alignment: .leading, spacing: 0) {
            Text(macro.title)
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(grams.gramsText) g")
                    .font(.number(22))
                    .numberTracking(22)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: grams))
                if showsTarget {
                    Text(verbatim: " / \(target.kcalText)")
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ProgressBar(value: target > 0 ? grams / target : 0, color: macro.color)
                .padding(.top, 5)
        }
        .animation(.smooth, value: grams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(macro, grams: grams, target: target))
    }

    private func label(_ macro: Macro, grams: Double, target: Double) -> LocalizedStringKey {
        showsTarget
            ? "\(macro.title): \(grams.gramsText) of \(target.kcalText) grams"
            : "\(macro.title): \(grams.gramsText) grams"
    }
}

/// Macros on the left, the dotted ring on the right with the calories in its middle. The same
/// block on Today (the day against its goal) and on a food (the food's own calories).
struct MacroBlock: View {
    let nutrients: Nutrients
    let targets: MacroTargets
    let ring: [DottedRing.Part]
    var overflow: Double = 0
    let number: Double
    let unit: LocalizedStringKey
    var numberSize: CGFloat = 28
    var showsTarget = true

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MacroBars(nutrients: nutrients, targets: targets, showsTarget: showsTarget)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                DottedRing(parts: ring, overflow: overflow)
                VStack(spacing: 3) {
                    Text(number.kcalText)
                        .font(.number(numberSize))
                        .numberTracking(numberSize)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: number))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(unit)
                        .font(.ui(numberSize >= 34 ? 13 : 12))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 30)
                .accessibilityElement(children: .combine)
            }
            .frame(width: 176, height: 176)
            .animation(.smooth, value: number)
        }
    }
}

// MARK: - Activity

/// What Apple Health can tell Today.
enum HealthState: Equatable {
    case unavailable
    case notConnected
    case connected(DayActivity)
}

/// Burned and steps as two soft chips under the macros, or the way to connect Health.
struct ActivityChips: View {
    let health: HealthState
    let onConnect: () -> Void

    var body: some View {
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
            HStack(spacing: 8) {
                chip(systemImage: "flame.fill", color: Theme.burned) {
                    Text("\(activity.activeKcal.kcalText) burned")
                }
                chip(systemImage: "shoeprints.fill", color: Theme.steps) {
                    Text("\(activity.steps.countText) steps")
                }
            }
        }
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
                shape.fill(onPhoto ? Color.black.opacity(0.2) : Color.white.opacity(0.35))
            }
            .environment(\.colorScheme, onPhoto ? .dark : .light)
        }
        .overlay {
            shape.stroke(onPhoto ? Color.white.opacity(0.22) : Color.black.opacity(0.06), lineWidth: 0.5)
        }
    }
}
