import SwiftUI

/// "Your usual dinner?": the meal you have most days, waiting on the timeline at its usual time.
/// Its foods sit faded until you add them; one tap logs the same foods at the same amounts,
/// and "Not today" puts it away until tomorrow.
struct UsualMoment: View {
    /// Its id on the page, for scrolling to it.
    static let anchor = "usual"

    let meal: Meal
    let entries: [FoodEntry]
    let time: Date
    let onAdd: () -> Void
    let onDismiss: () -> Void

    @State private var taps = 0

    private var total: Double { entries.reduce(0) { $0 + $1.totals.kcal } }
    private var timeText: String { time.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timeText)
                .font(.ui(13))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 54, alignment: .trailing)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meal.usualQuestion)
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text("\(total.kcalText) kcal")
                        .font(.ui(14))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }
                .accessibilityElement(children: .combine)

                FlowLayout(spacing: 6) {
                    ForEach(entries) { entry in
                        FoodThumb(food: entry.food, size: 76)
                            .opacity(0.55)
                            .accessibilityLabel("\(entry.name), \(entry.food.unit.format(entry.amount)), \(entry.totals.kcal.kcalText) calories")
                    }
                }

                HStack(spacing: 18) {
                    Button {
                        taps += 1
                        onAdd()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.ui(15, .semibold))
                            .foregroundStyle(Theme.page)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(Theme.ink, in: Capsule())
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    .accessibilityHint(meal.usualQuestion)

                    Button("Not today", action: onDismiss)
                        .font(.ui(15, .medium))
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.top, 2)
            }
        }
        .sensoryFeedback(Feel.land, trigger: taps)
    }
}
