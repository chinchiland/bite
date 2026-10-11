import SwiftUI
import Charts

/// Turns logged entries into the plain numbers the scores and ranks are made of.
enum InsightsData {
    /// One summary per day that has logs.
    static func summaries(of entries: [FoodEntry], calendar: Calendar = .current) -> [DaySummary] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        return byDay.map { day, items in
            var graded = 0.0
            var gradedKcal = 0.0
            var kcal = 0.0
            var protein = 0.0
            for item in items {
                let totals = item.totals
                kcal += totals.kcal
                protein += totals.protein
                if let points = Insights.qualityPoints(grade: item.nutriScore) {
                    graded += points * totals.kcal
                    gradedKcal += totals.kcal
                }
            }
            return DaySummary(
                day: day,
                kcal: kcal,
                protein: protein,
                entries: items.count,
                quality: gradedKcal > 0 ? graded / gradedKcal : nil
            )
        }
        .sorted { $0.day < $1.day }
    }
}

/// Your week or month: the days on a chart the way the Health app draws them (touch a bar for
/// its day), how it moved, your best days and the foods you come back to, ranked the
/// Brandsearch way.
struct InsightsView: View {
    enum Range {
        case week
        case month

        var days: Int { self == .week ? 7 : 30 }
        var title: String { self == .week ? "Last 7 days" : "Last 30 days" }
    }

    let range: Range
    let entries: [FoodEntry]
    let goal: Double
    let targets: MacroTargets

    /// The day under your finger on the chart.
    @State private var picked: Date?

    var body: some View {
        // Whole days only: today is still being eaten, so it waits until tomorrow.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -range.days, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -range.days, to: start) ?? start
        let all = InsightsData.summaries(of: entries)
        let current = all.filter { $0.day >= start && $0.day < today }
        let previous = all.filter { $0.day >= previousStart && $0.day < start }
        let now = Insights.period(current, goal: goal)
        let before = Insights.period(previous, goal: goal)
        let periodEntries = entries.filter { $0.date >= start && $0.date < today }

        VStack(spacing: Theme.gap) {
            HStack(alignment: .center) {
                Text(range.title)
                    .font(.ui(32, .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                let streak = Insights.streak(all, goal: goal, today: .now)
                if streak >= 2 {
                    TintChip(title: "\(streak)-day streak", systemImage: "flame.fill", iconColor: Theme.energy)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            if now.loggedDays == 0 {
                Card(padding: 24) {
                    Text("Log a few days and they show up here, with your best days ranked.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            } else {
                chart(current, start: start, today: today, now: now, before: before)
                kpis(now: now, before: before)
                bestDays(current)
                mostEaten(periodEntries)
            }
        }
    }

    // MARK: Chart

    private func chart(_ days: [DaySummary], start: Date, today: Date, now: Insights.Period, before: Insights.Period) -> some View {
        let calendar = Calendar.current
        let last = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let selected = picked.flatMap { date in days.first { calendar.isDate($0.day, inSameDayAs: date) } }
        let shown = selected?.kcal ?? now.averageKcal
        let dayStarts = (0..<range.days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let labelDays = range == .week ? dayStarts : stride(from: 0, to: dayStarts.count, by: 7).map { dayStarts[$0] }
        let axisFormat: Date.FormatStyle = range == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
        let peak = max(days.map(\.kcal).filter(\.isFinite).max() ?? 0, goal, 1)

        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                // The Health app's header: what you are looking at, the number, when.
                Text(selected.map { $0.day.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "Daily average")
                    .font(.ui(13, .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(shown.kcalText)
                            .font(.number(30))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.numericText(value: shown))
                        Text("kcal")
                            .font(.ui(17))
                            .foregroundStyle(Theme.secondary)
                    }
                    if selected == nil, let change = Insights.change(from: before.averageKcal, to: now.averageKcal) {
                        ChangeLabel(change: change)
                    }
                }
                .padding(.top, 2)
                Text(selected.map { DayVerdict(kcal: $0.kcal, entries: $0.entries, goal: goal).label ?? "" } ?? Self.span(start, last))
                    .font(.ui(15))
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 1)
                    .padding(.bottom, 14)

                Chart {
                    ForEach(days, id: \.day) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Calories", day.kcal),
                            width: .ratio(range == .week ? 0.55 : 0.6)
                        )
                        .foregroundStyle(day.kcal > goal * 1.05 ? Theme.over : Theme.energy)
                        .cornerRadius(range == .week ? 5 : 3, style: .continuous)
                        .opacity(selected == nil || selected?.day == day.day ? 1 : 0.35)
                    }
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(Theme.ink.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: start...today)
                .chartYScale(domain: 0...(peak * 1.12))
                .chartXSelection(value: $picked)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, goal / 2]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel()
                            .font(.ui(12))
                    }
                    // The goal is labeled in ink where its dashed line meets the axis.
                    AxisMarks(position: .trailing, values: [goal]) { _ in
                        AxisValueLabel()
                            .font(.ui(12, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: labelDays) { value in
                        AxisValueLabel(centered: true) {
                            if let date = value.as(Date.self) {
                                Text(date, format: axisFormat)
                                    .font(.ui(12, .medium))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .sensoryFeedback(.selection, trigger: selected?.day)
                .accessibilityLabel("Calories each day, with your goal of \(goal.kcalText)")
            }
        }
    }

    /// "4 to 10 October" (or "October 4 to 10", in the order your region writes dates), and
    /// "28 September to 4 October" across two months.
    static func span(_ first: Date, _ last: Date, calendar: Calendar = .current) -> String {
        let full = Date.FormatStyle.dateTime.day().month(.wide)
        guard calendar.isDate(first, equalTo: last, toGranularity: .month) else {
            return "\(first.formatted(full)) to \(last.formatted(full))"
        }
        let dayFirst = DateFormatter.dateFormat(fromTemplate: "dMMMM", options: 0, locale: .current)?.hasPrefix("d") ?? true
        let firstDay = first.formatted(.dateTime.day())
        let lastDay = last.formatted(.dateTime.day())
        let month = last.formatted(.dateTime.month(.wide))
        return dayFirst ? "\(firstDay) to \(lastDay) \(month)" : "\(month) \(firstDay) to \(lastDay)"
    }

    // MARK: Cards

    private func kpis(now: Insights.Period, before: Insights.Period) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Card(padding: 0) {
                HStack(alignment: .top, spacing: 16) {
                    StatTile(
                        label: "On target",
                        value: "\(now.daysOnTarget)",
                        unit: "of \(now.loggedDays) days"
                    )
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(width: 0.5)
                    StatTile(
                        label: "Protein a day",
                        value: now.averageProtein.kcalText,
                        unit: "g",
                        change: Insights.change(from: before.averageProtein, to: now.averageProtein),
                        higherIsBetter: true
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            Text("Moves compare with the \(range.days) days before. Today joins tomorrow.")
                .font(.ui(13))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func bestDays(_ days: [DaySummary]) -> some View {
        let best = Insights.bestDays(days, goal: goal, proteinTarget: targets.protein)
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title: "Best days", detail: "Score out of 100", size: 17)
                    .padding(.horizontal, -4)
                    .padding(.bottom, 4)
                ForEach(Array(best.enumerated()), id: \.offset) { index, item in
                    if index > 0 { RowDivider(leading: 64) }
                    HStack(spacing: 10) {
                        LaurelBadge(rank: index + 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(item.day.kcal.kcalText) kcal · \(item.day.protein.kcalText) g protein")
                                .font(.ui(15))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text("\(item.score)")
                            .font(.number(22))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func mostEaten(_ periodEntries: [FoodEntry]) -> some View {
        let logs = periodEntries.map { (foodID: $0.foodID, name: $0.name, kcal: $0.totals.kcal) }
        let top = Insights.topFoods(logs)
        let latest = Dictionary(periodEntries.map { ($0.foodID, $0) }, uniquingKeysWith: { _, last in last })
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title: "Most eaten", detail: "Times logged", size: 17)
                    .padding(.horizontal, -4)
                    .padding(.bottom, 4)
                ForEach(Array(top.enumerated()), id: \.offset) { index, food in
                    if index > 0 { RowDivider(leading: 114) }
                    HStack(spacing: 10) {
                        LaurelBadge(rank: index + 1)
                        if let entry = latest[food.foodID] {
                            FoodThumb(food: entry.food, size: 40)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name)
                                .font(.ui(17))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(food.kcal.kcalText) kcal in total")
                                .font(.ui(15))
                                .monospacedDigit()
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("×\(food.times)")
                            .font(.number(20))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }
}
