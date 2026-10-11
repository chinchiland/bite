import SwiftUI

/// Seven day pills at a time. Each carries a dot for how the day went: green on target,
/// red over, gray light. Swipe for earlier weeks.
struct WeekPager: View {
    @Binding var selection: Date
    let verdicts: [Date: DayVerdict]

    static let weeks = 12
    static let daysBack = weeks * 7

    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            ForEach((1 - Self.weeks)...0, id: \.self) { offset in
                HStack(spacing: 6) {
                    ForEach(Self.days(page: offset), id: \.self) { day in
                        DayPill(
                            day: day,
                            verdict: verdicts[day] ?? .empty,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selection)
                        ) {
                            withAnimation(.snappy) { selection = day }
                        }
                    }
                }
                .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 66)
        .onAppear { page = Self.page(containing: selection) }
        .onChange(of: selection) { _, day in
            let target = Self.page(containing: day)
            if target != page {
                withAnimation(.snappy) { page = target }
            }
        }
    }

    /// Page 0 is the seven days ending today, page -1 the seven before, and so on.
    static func days(page: Int, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: .now)
        let last = calendar.date(byAdding: .day, value: page * 7, to: today) ?? today
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
    }

    static func page(containing day: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: .now)
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? 0
        return -min(max(daysAgo, 0) / 7, weeks - 1)
    }
}

private struct DayPill: View {
    let day: Date
    let verdict: DayVerdict
    let isSelected: Bool
    let action: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var dot: Color {
        switch verdict {
        case .empty: .clear
        case .light: Theme.tertiary
        case .onTarget: Theme.goodText
        case .over: Theme.over
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.ui(12, .medium))
                    .foregroundStyle(isSelected ? Theme.page.opacity(0.65) : Theme.secondary)
                Text(day.formatted(.dateTime.day()))
                    .font(.number(17))
                    .foregroundStyle(isSelected ? Theme.page : Theme.ink)
                Circle()
                    .fill(dot)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(isSelected ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(verdict.label ?? "Nothing logged")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
