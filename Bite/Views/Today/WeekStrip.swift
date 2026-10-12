import SwiftUI

/// The week at a glance under your day: a dot for each of the last seven days, and how many
/// landed on target. A day opens that day; the header opens the week in full.
struct WeekStrip: View {
    struct Day: Identifiable {
        let date: Date
        let verdict: DayVerdict
        var id: Date { date }
    }

    /// Oldest first, today last.
    let days: [Day]
    let onOpenWeek: () -> Void
    let onOpenDay: (Date) -> Void

    private var calendar: Calendar { .current }

    /// Past days with food logged, and how many of them landed on target.
    private var tally: (onTarget: Int, logged: Int) {
        let past = days.filter { !calendar.isDateInToday($0.date) && $0.verdict != .empty }
        return (past.filter(\.verdict.isOnTarget).count, past.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onOpenWeek) {
                HStack(spacing: 4) {
                    SectionLabel(title: "This week", symbol: "calendar")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your last 7 days")

            HStack(spacing: 0) {
                ForEach(days) { day in
                    Button {
                        onOpenDay(day.date)
                    } label: {
                        VStack(spacing: 8) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.ui(12, calendar.isDateInToday(day.date) ? .semibold : .regular))
                                .foregroundStyle(calendar.isDateInToday(day.date) ? Theme.ink : Theme.secondary)
                            dot(day)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(day.date.formatted(.dateTime.weekday(.wide))): \(day.verdict.label ?? String(localized: "nothing logged"))"))
                }
            }

            let tally = tally
            if tally.logged > 0 {
                Text("On target: \(tally.onTarget) of \(tally.logged)")
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    /// A filled dot in the day's verdict color; an empty ring for a day with nothing logged;
    /// today as a ring, since it is not over yet.
    @ViewBuilder private func dot(_ day: Day) -> some View {
        if calendar.isDateInToday(day.date) {
            Circle()
                .strokeBorder(day.verdict == .empty ? Theme.tertiary : day.verdict.dotColor, lineWidth: 2.5)
                .frame(width: 14, height: 14)
        } else if day.verdict == .empty {
            Circle()
                .strokeBorder(Theme.track, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .fill(day.verdict.dotColor)
                .frame(width: 14, height: 14)
        }
    }

}

/// A thin line of values with a dot on the latest, for a trend in a row.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let span = max(high - low, 0.1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: 3 + (size.height - 6) * CGFloat(1 - (value - low) / span)
                )
            }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .color(Theme.secondary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(Theme.ink))
            }
        }
        .accessibilityHidden(true)
    }
}

extension Double {
    /// "72.4 kg", or pounds where people weigh themselves in pounds.
    var weightText: String {
        Measurement(value: self, unit: UnitMass.kilograms).formatted(
            .measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(1)))
        )
    }
}
