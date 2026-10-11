import SwiftUI

/// Calories left as a half dial of fine ticks that fill as you eat, light yellow warming to
/// amber, with the number in the middle. Past the goal the ticks turn red and the number
/// counts what is over.
struct CalorieGauge: View {
    let eaten: Double
    let goal: Double
    var radius: CGFloat = 114
    var ticks: Int = 41

    private static let tickLength: CGFloat = 16
    private static let tickWidth: CGFloat = 3.5
    /// Room under the dial's baseline for the "kcal left" line.
    private static let below: CGFloat = 22

    private var progress: Double { goal > 0 ? min(max(eaten, 0) / goal, 1) : 0 }
    private var isOver: Bool { eaten > goal }
    private var remaining: Double { abs(goal - eaten) }

    var body: some View {
        let width = 2 * radius + Self.tickLength
        let height = radius + Self.tickLength / 2 + Self.below
        // Where the dial's center sits, as a share of the frame, for the gradient to turn around.
        let center = UnitPoint(x: 0.5, y: (radius + Self.tickLength / 2) / height)
        ZStack {
            GaugeTicks(count: ticks, from: progress, to: 1, length: Self.tickLength, width: Self.tickWidth)
                .fill(Theme.track)
            GaugeTicks(count: ticks, from: 0, to: progress, length: Self.tickLength, width: Self.tickWidth)
                .fill(isOver
                    ? AnyShapeStyle(Theme.over)
                    : AnyShapeStyle(AngularGradient(
                        colors: [Theme.energyLight, Theme.energy],
                        center: center,
                        startAngle: .degrees(180),
                        endAngle: .degrees(360)
                    )))
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) { label }
        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: progress)
        .animation(.smooth, value: isOver)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOver ? "\(remaining.kcalText) calories over your goal" : "\(remaining.kcalText) calories left")
    }

    private var label: some View {
        VStack(spacing: 0) {
            Image(systemName: "flame.fill")
                .font(.system(size: 19))
                .foregroundStyle(isOver ? Theme.over : Theme.energy)
                .padding(.bottom, 6)
            Text(remaining.kcalText)
                .font(.number(52))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: remaining))
            Text(isOver ? "kcal over" : "kcal left")
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
    }
}

/// The ticks of the gauge between two shares of the dial, as one shape. Animating the shares
/// lights the ticks up one by one.
private struct GaugeTicks: Shape {
    let count: Int
    var from: Double
    var to: Double
    let length: CGFloat
    let width: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(from, to) }
        set {
            from = newValue.first
            to = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 1, from.isFinite, to.isFinite else { return path }
        let radius = (rect.width - length) / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + length / 2 + radius)
        let tick = Path(
            roundedRect: CGRect(x: -width / 2, y: -length / 2, width: width, height: length),
            cornerRadius: width / 2
        )
        let first = Int((from * Double(count)).rounded())
        let last = Int((to * Double(count)).rounded())
        guard first < last else { return path }
        for index in max(first, 0)..<min(last, count) {
            // From nine o'clock over the top to three o'clock.
            let angle = Double.pi * (Double(index) / Double(count - 1) - 0.5)
            let transform = CGAffineTransform(
                translationX: center.x + radius * CGFloat(sin(angle)),
                y: center.y - radius * CGFloat(cos(angle))
            )
            .rotated(by: CGFloat(angle))
            path.addPath(tick, transform: transform)
        }
        return path
    }
}

/// One fact under the gauge: a small colored symbol and its label over the number.
struct DayStat: View {
    let systemImage: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                Text(label)
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            Text(value)
                .font(.number(20))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One macro against its target: icon and name, grams over target, a bar in the macro's color.
struct MacroColumn: View {
    let macro: Macro
    let grams: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: macro.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(macro.color)
                Text(macro.title)
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(grams.kcalText)
                    .font(.number(20))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: grams))
                Text(" / \(target.kcalText) g")
                    .font(.ui(15))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            ProgressBar(value: target > 0 ? grams / target : 0, color: macro.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth, value: grams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.title): \(grams.kcalText) of \(target.kcalText) grams")
    }
}

/// The three macros of one food in a line: small colored icon, grams.
struct MacroMinis: View {
    let nutrients: Nutrients

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Macro.allCases, id: \.self) { macro in
                HStack(spacing: 3) {
                    Image(systemName: macro.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(macro.color)
                    Text(macro.grams(in: nutrients).gramsText)
                        .font(.number(13, .medium))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(nutrients.protein.gramsText) grams, carbs \(nutrients.carbs.gramsText), fat \(nutrients.fat.gramsText)")
    }
}

/// A macro in a pill, for a food's page and the photo estimate: icon, name, grams.
struct MacroPill: View {
    let macro: Macro
    let grams: Double
    var onPhoto = false

    var body: some View {
        HStack(spacing: 8) {
            MacroIcon(macro: macro, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(macro.title)
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondary)
                Text("\(grams.gramsText) g")
                    .font(.number(15))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: grams))
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 14)
        .frame(height: 42)
        .pillBackground(onPhoto: onPhoto)
    }
}

/// The calories in a pill: flame, number, "kcal".
struct KcalPill: View {
    let kcal: Double
    var onPhoto = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.energy)
                .frame(width: 28, height: 28)
                .background(Theme.energySoft, in: Circle())
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(kcal.kcalText)
                    .font(.number(20))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: kcal))
                Text("kcal")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 44)
        .pillBackground(onPhoto: onPhoto)
    }
}

private extension View {
    /// Glass over a photo, a card everywhere else.
    @ViewBuilder func pillBackground(onPhoto: Bool) -> some View {
        if onPhoto {
            floatingGlass(in: Capsule())
        } else {
            background(Theme.card, in: Capsule())
        }
    }
}
