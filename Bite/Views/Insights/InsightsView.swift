import SwiftUI

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

    /// "4 to 10 October" (or "October 4 to 10", in the order your region writes dates), and
    /// "28 September to 4 October" across two months.
    static func span(_ first: Date, _ last: Date, calendar: Calendar = .current) -> String {
        let full = Date.FormatStyle.dateTime.day().month(.wide)
        guard calendar.isDate(first, equalTo: last, toGranularity: .month) else {
            return String(localized: "\(first.formatted(full)) to \(last.formatted(full))")
        }
        let dayFirst = DateFormatter.dateFormat(fromTemplate: "dMMMM", options: 0, locale: .current)?.hasPrefix("d") ?? true
        let firstDay = first.formatted(.dateTime.day())
        let lastDay = last.formatted(.dateTime.day())
        let month = last.formatted(.dateTime.month(.wide))
        return dayFirst
            ? String(localized: "\(firstDay) to \(lastDay) \(month)")
            : String(localized: "\(month) \(firstDay) to \(lastDay)")
    }
}

/// The two ranges home can show besides a day.
enum InsightsRange {
    case week
    case month

    var days: Int { self == .week ? 7 : 30 }
    var title: LocalizedStringKey { self == .week ? "Last 7 days" : "Last 30 days" }
    var foodTitle: LocalizedStringKey { self == .week ? "Your week in food" : "Your month in food" }
    var comparison: LocalizedStringKey { self == .week ? "vs the 7 days before" : "vs the 30 days before" }
}

/// Your last 7 or 30 days as a food diary: the daily average and its bars, each day with its
/// verdict and its food, then your best days and the foods you come back to, ranked the
/// Brandsearch way. Whole days only: today joins tomorrow.
struct RangeView<Switcher: View>: View {
    let range: InsightsRange
    let entries: [FoodEntry]
    let goal: Double
    let targets: MacroTargets
    let onOpenDay: (Date) -> Void
    let onSettings: () -> Void
    @ViewBuilder let switcher: Switcher

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -range.days, to: today) ?? today
        let last = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let previousStart = calendar.date(byAdding: .day, value: -range.days, to: start) ?? start
        let all = InsightsData.summaries(of: entries)
        let current = all.filter { $0.day >= start && $0.day < today }
        let previous = all.filter { $0.day >= previousStart && $0.day < start }
        let now = Insights.period(current, goal: goal)
        let before = Insights.period(previous, goal: goal)
        let periodEntries = entries.filter { $0.date >= start && $0.date < today }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(start: start, last: last)
                if now.loggedDays == 0 {
                    Card(padding: 24) {
                        Text("Log a few days and they show up here, with your best days ranked.")
                            .font(.ui(15))
                            .foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 18)
                } else {
                    averageCard(current, start: start, now: now, before: before)
                        .padding(.top, 18)
                    SectionLabel(title: range.foodTitle)
                        .padding(.top, 28)
                        .padding(.bottom, 6)
                    dayRows(current, entries: periodEntries)
                    bestDays(current)
                        .padding(.top, 30)
                    mostEaten(periodEntries)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(ScreenshotFlags.scrollAnchor)
    }

    private func header(start: Date, last: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                switcher
                Text(InsightsData.span(start, last))
                    .font(.ui(14))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            CircleIconButton(systemImage: "gearshape", label: "Settings", action: onSettings)
        }
    }

    // MARK: Average

    private func averageCard(_ days: [DaySummary], start: Date, now: Insights.Period, before: Insights.Period) -> some View {
        let calendar = Calendar.current
        let dayStarts = (0..<range.days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let kcal = Dictionary(days.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
        let bars = DayBars(days: dayStarts, kcal: kcal, goal: goal)
        return Card(padding: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily average")
                            .font(.ui(13))
                            .foregroundStyle(Theme.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(now.averageKcal.kcalText)
                                .font(.number(36))
                                .numberTracking(36)
                                .foregroundStyle(Theme.ink)
                            Text("kcal")
                                .font(.ui(15))
                                .foregroundStyle(Theme.secondary)
                        }
                        if let change = Insights.change(from: before.averageKcal, to: now.averageKcal) {
                            HStack(spacing: 5) {
                                ChangeLabel(change: change)
                                Text(range.comparison)
                                    .font(.ui(13))
                                    .foregroundStyle(Theme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if range == .week {
                        bars.frame(width: 120, height: 56)
                    }
                }
                if range == .month {
                    bars.frame(height: 64)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    // MARK: Days

    private func dayRows(_ summaries: [DaySummary], entries: [FoodEntry]) -> some View {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        let logged = summaries.filter { $0.entries > 0 }.sorted { $0.day > $1.day }
        return VStack(spacing: 0) {
            ForEach(logged, id: \.day) { summary in
                Button { onOpenDay(summary.day) } label: {
                    DayRow(summary: summary, entries: byDay[summary.day] ?? [], goal: goal)
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
    }

    // MARK: Ranks

    private func bestDays(_ days: [DaySummary]) -> some View {
        let best = Insights.bestDays(days, goal: goal, proteinTarget: targets.protein)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Best days", detail: "Score out of 100")
                .padding(.bottom, 4)
            ForEach(Array(best.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    LaurelBadge(rank: index + 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("\(item.day.kcal.kcalText) kcal · \(item.day.protein.kcalText) g protein")
                            .font(.ui(14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: "\(item.score)")
                        .font(.number(22))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 64)
                    }
                }
            }
        }
    }

    private func mostEaten(_ periodEntries: [FoodEntry]) -> some View {
        let logs = periodEntries.map { (foodID: $0.foodID, name: $0.name, kcal: $0.totals.kcal) }
        let top = Insights.topFoods(logs)
        let latest = Dictionary(periodEntries.map { ($0.foodID, $0) }, uniquingKeysWith: { _, last in last })
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Most eaten", detail: "Times logged")
                .padding(.bottom, 4)
            ForEach(Array(top.enumerated()), id: \.offset) { index, food in
                HStack(spacing: 10) {
                    LaurelBadge(rank: index + 1)
                    if let entry = latest[food.foodID] {
                        FoodThumb(food: entry.food, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name)
                            .font(.ui(16, .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text("\(food.kcal.kcalText) kcal in total")
                            .font(.ui(14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(verbatim: "×\(food.times)")
                        .font(.number(20))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 118)
                    }
                }
            }
        }
    }
}

/// One day in the diary: its name, a dot for how it went and its calories, then its food.
private struct DayRow: View {
    let summary: DaySummary
    let entries: [FoodEntry]
    let goal: Double

    private var verdict: DayVerdict {
        DayVerdict(kcal: summary.kcal, entries: summary.entries, goal: goal)
    }

    /// Up to four of the day's foods, photos first, each food once.
    private var pictures: [FoodEntry] {
        var seen = Set<String>()
        let unique = entries.filter { seen.insert($0.foodID).inserted }
        let ranked = unique.enumerated().sorted { a, b in
            let rankA = a.element.imageData != nil ? 0 : a.element.imageURLString != nil ? 1 : 2
            let rankB = b.element.imageData != nil ? 0 : b.element.imageURLString != nil ? 1 : 2
            return (rankA, a.offset) < (rankB, b.offset)
        }
        return ranked.prefix(4).map(\.element)
    }

    private var isOver: Bool {
        if case .over = verdict { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.day.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(verdict.dotColor)
                        .frame(width: 7, height: 7)
                    Text(summary.kcal.kcalText)
                        .font(.ui(13))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Theme.over : Theme.secondary)
                }
            }
            .frame(width: 74, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(pictures) { entry in
                    FoodThumb(food: entry.food, size: 58)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.day.formatted(date: .complete, time: .omitted)), \(summary.kcal.kcalText) kcal, \(verdict.label ?? "")")
    }
}

/// The days as thin bars against the goal's dashed line: ink when fine, red when over. They
/// grow from the baseline when they appear.
private struct DayBars: View {
    let days: [Date]
    let kcal: [Date: Double]
    let goal: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let count = max(days.count, 1)
            let barWidth: CGFloat = count > 10 ? max(3, (size.width - CGFloat(count - 1) * 3) / CGFloat(count)) : 6
            let spacing = count > 1 ? (size.width - barWidth * CGFloat(count)) / CGFloat(count - 1) : 0
            let peak = max(kcal.values.filter(\.isFinite).max() ?? 0, goal, 1) * 1.06
            let goalY = size.height * (1 - goal / peak)
            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: goalY))
                    path.addLine(to: CGPoint(x: size.width, y: goalY))
                }
                .stroke(Theme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let value = kcal[day] ?? 0
                    let height = value > 0 ? max(size.height * value / peak, barWidth) : 0
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(value > goal * 1.05 ? Theme.over : Theme.ink)
                        .frame(width: barWidth, height: grown ? height : 0)
                        .offset(x: CGFloat(index) * (barWidth + spacing))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        }
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { grown = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories each day, with your goal of \(goal.kcalText)")
    }
}
