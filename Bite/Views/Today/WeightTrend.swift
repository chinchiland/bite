import SwiftUI

/// If you keep this up: your weighings as dots, then a dotted line to where your weight is
/// heading in four weeks at the way you have been eating, with that weight in big numbers and
/// one sentence on why. An estimate, and it says so.
struct WeightTrend: View {
    /// Your weighings, oldest first; empty when none are known.
    let weights: [WeightPoint]
    let forecast: WeightForecast?
    /// Where you are going: a forecast toward it draws in green.
    let goal: WeightGoal
    /// What your body really burns, when your weighings and meals have said.
    var learned: LearnedMaintenance? = nil
    /// A daily goal that fits what you burn, when it differs from yours.
    var suggestedGoal: Int? = nil
    var onUseGoal: () -> Void = {}
    var onHideGoal: () -> Void = {}
    let onAddWeight: () -> Void
    var horizonDays = 28

    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: horizonDays, to: .now) ?? .now
    }

    /// The line is green when it heads where you want to go.
    private var onCourse: Bool {
        guard let direction = forecast?.direction else { return false }
        switch (direction, goal) {
        case (.losing, .lose), (.holding, .maintain), (.gaining, .gain): return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
                .accessibilityElement(children: .combine)
            if let suggestedGoal, forecast != nil {
                GoalOffer(kcal: suggestedGoal, goal: goal, onUse: onUseGoal, onHide: onHideGoal)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "If you keep this up", symbol: "chart.line.downtrend.xyaxis")
            if let forecast {
                let end = forecast.weight(afterDays: Double(horizonDays))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(end.weightText)
                        .font(.number(34, .medium))
                        .numberTracking(34)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: end))
                    Text("by \(endDate.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                }
                TrendChart(weights: weights, forecast: forecast, horizonDays: horizonDays, lineColor: onCourse ? Theme.onTarget : Theme.secondary)
                    .frame(height: 112)
                Text(sentence(forecast))
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if let learned {
                        Text("What you burn, about \(learned.kcal.roughKcalText) kcal a day, is learned from \(learned.days) days of your weighings and meals.")
                    } else {
                        Text("An estimate from your last \(forecast.days) logged days.")
                    }
                }
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if weights.isEmpty {
                Button(action: onAddWeight) {
                    HStack(spacing: 10) {
                        SymbolTile(systemImage: "scalemass.fill", color: Theme.steps, glyph: Theme.steps)
                        Text("Add your weight to see where it is heading")
                            .font(.ui(15))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("Log a few whole days and Bite shows where your weight is heading.")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sentence(_ forecast: WeightForecast) -> String {
        let kcal = abs(forecast.dailyBalance).roughKcalText
        let week = abs(forecast.perWeek).weeklyWeightText
        switch forecast.direction {
        case .losing: return String(localized: "You eat about \(kcal) kcal a day under what you burn, about \(week) a week.")
        case .gaining: return String(localized: "You eat about \(kcal) kcal a day over what you burn, about \(week) a week.")
        case .holding: return String(localized: "You eat about what you burn, so your weight should hold.")
        }
    }
}

/// A goal that fits what your body really burns, one tap from being yours; "Not now" puts it
/// away for a week. Laid out like your usual meal: the line, then the ink button and the quiet one.
private struct GoalOffer: View {
    let kcal: Int
    let goal: WeightGoal
    let onUse: () -> Void
    let onHide: () -> Void

    @State private var taps = 0

    private var detail: LocalizedStringKey {
        switch goal {
        case .lose: "About half a kilo a week down"
        case .maintain: "To stay where you are"
        case .gain: "A slow, steady gain"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A goal of \(Double(kcal).kcalText) kcal fits what you burn")
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 18) {
                Button {
                    taps += 1
                    onUse()
                } label: {
                    Text("Use it")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Theme.page)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .accessibilityHint("Makes it your daily goal")

                Button("Not now", action: onHide)
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(Feel.click, trigger: taps)
    }
}

/// The weighings as dots and the road ahead as a dotted line, today marked on the way.
private struct TrendChart: View {
    let weights: [WeightPoint]
    let forecast: WeightForecast
    let horizonDays: Int
    let lineColor: Color

    var body: some View {
        let now = Date.now
        let lead = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let start = min(weights.first?.date ?? lead, lead)
        let end = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let span = max(end.timeIntervalSince(start), 1)
        let endKg = forecast.weight(afterDays: Double(horizonDays))
        let values = weights.map(\.kilograms) + [forecast.startKg, endKg]
        let low = (values.min() ?? endKg) - 0.3
        let high = (values.max() ?? endKg) + 0.3
        let todayShare = CGFloat(now.timeIntervalSince(start) / span)

        VStack(spacing: 6) {
            Canvas { context, size in
                let plot = CGRect(x: 6, y: 8, width: size.width - 12, height: size.height - 16)
                func point(_ date: Date, _ kg: Double) -> CGPoint {
                    CGPoint(
                        x: plot.minX + plot.width * CGFloat(date.timeIntervalSince(start) / span),
                        y: plot.minY + plot.height * CGFloat(1 - (kg - low) / max(high - low, 0.1))
                    )
                }
                // Today, as a hairline.
                let today = point(now, forecast.startKg)
                var mark = Path()
                mark.move(to: CGPoint(x: today.x, y: plot.minY - 4))
                mark.addLine(to: CGPoint(x: today.x, y: plot.maxY + 4))
                context.stroke(mark, with: .color(Theme.hairline), lineWidth: 1)

                // The road ahead, dotted.
                let target = point(end, endKg)
                var road = Path()
                road.move(to: today)
                road.addLine(to: target)
                context.stroke(road, with: .color(lineColor), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 7]))

                // Each weighing.
                for weight in weights {
                    let dot = point(weight.date, weight.kilograms)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(Theme.ink.opacity(0.7)))
                }
                // Today and where it leads, as bigger dots.
                for (dot, color) in [(today, Theme.ink), (target, lineColor)] {
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 6, y: dot.y - 6, width: 12, height: 12)), with: .color(Theme.page))
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 4.5, y: dot.y - 4.5, width: 9, height: 9)), with: .color(color))
                }
            }
            GeometryReader { proxy in
                Text("Today")
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize()
                    .position(x: 6 + (proxy.size.width - 12) * todayShare, y: proxy.size.height / 2)
                Text(end.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: proxy.size.height)
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}
