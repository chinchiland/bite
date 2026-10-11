import SwiftUI

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @State private var events = LogEvents()

    var body: some View {
        TodayView()
            .environment(events)
            .fullScreenCover(isPresented: needsGoal) {
                NavigationStack {
                    GoalCalculatorView(isWelcome: true) { kcal in
                        goalKcal = kcal
                        onboarded = true
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Skip") { onboarded = true }
                        }
                    }
                }
            }
    }

    private var needsGoal: Binding<Bool> {
        Binding(
            get: { !onboarded },
            set: { presented in if !presented { onboarded = true } }
        )
    }
}
