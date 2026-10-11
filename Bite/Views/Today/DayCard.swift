import SwiftUI

/// What Apple Health can tell Today.
enum HealthState: Equatable {
    case unavailable
    case notConnected
    case connected(DayActivity)
}

/// The day at a glance: calories left on the gauge, what explains it (eaten, burned, steps),
/// then the three macros.
struct DayCard: View {
    let totals: Nutrients
    let goal: Double
    let targets: MacroTargets
    let health: HealthState
    let onConnectHealth: () -> Void

    var body: some View {
        Card(padding: 18) {
            VStack(spacing: 18) {
                CalorieGauge(eaten: totals.kcal, goal: goal)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                InsetBox(padding: 0) {
                    HStack(spacing: 0) {
                        DayStat(systemImage: "fork.knife", color: Theme.energy, label: "Eaten", value: totals.kcal.kcalText)
                        healthStats
                    }
                    .padding(.vertical, 12)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    ForEach(Macro.allCases, id: \.self) { macro in
                        MacroColumn(macro: macro, grams: macro.grams(in: totals), target: macro.target(in: targets))
                    }
                }
            }
        }
    }

    @ViewBuilder private var healthStats: some View {
        switch health {
        case .unavailable:
            EmptyView()
        case .notConnected:
            divider
            Button(action: onConnectHealth) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.burned)
                    Text("Connect Health")
                        .foregroundStyle(Theme.ink)
                }
                .font(.ui(15, .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Shows your steps and burned calories from Apple Health")
        case .connected(let activity):
            divider
            DayStat(systemImage: "flame.fill", color: Theme.burned, label: "Burned", value: activity.activeKcal.kcalText)
            divider
            DayStat(systemImage: "figure.walk", color: Theme.steps, label: "Steps", value: activity.steps.countText)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 0.5)
            .padding(.vertical, 2)
    }
}
