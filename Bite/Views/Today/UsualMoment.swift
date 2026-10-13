import SwiftUI

/// "Your usual dinner?" or, on day two, "Same as yesterday?": the meal waiting on the timeline at
/// its hour, as one quiet line. Its foods sit as a small faded stack beside the hour and the
/// calories; one tap on Add logs the same foods at the same amounts. Press and hold for
/// Not today, which puts it away until tomorrow.
struct UsualMoment: View {
    /// Its id on the page, for scrolling to it.
    static let anchor = "usual"

    let question: String
    let entries: [FoodEntry]
    let time: Date
    let onAdd: () -> Void
    let onDismiss: () -> Void

    @State private var taps = 0

    private var total: Double { entries.reduce(0) { $0 + $1.totals.kcal } }
    private var timeText: String { time.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        HStack(spacing: 12) {
            stack
            VStack(alignment: .leading, spacing: 1) {
                Text(question)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(timeText) · \(total.kcalText) kcal")
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button {
                taps += 1
                onAdd()
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.page)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .fixedSize()
            .accessibilityHint(question)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button("Add", systemImage: "plus") {
                taps += 1
                onAdd()
            }
            Button("Not today", systemImage: "xmark", action: onDismiss)
        }
        .accessibilityAction(named: Text("Not today"), onDismiss)
        .sensoryFeedback(Feel.land, trigger: taps)
    }

    /// Up to three of its foods, overlapping, faded: a glance at what it is, not a list.
    private var stack: some View {
        HStack(spacing: -12) {
            ForEach(entries.prefix(3)) { entry in
                FoodThumb(food: entry.food, size: 40)
                    .padding(2)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: FoodThumb.radius(for: 44), style: .continuous))
            }
        }
        .opacity(0.75)
        .accessibilityHidden(true)
    }
}
