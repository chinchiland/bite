import SwiftUI

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("goal.kcal") private var goalKcal = 2000
    @State private var events = LogEvents()
    @State private var storeProblem = BiteStore.failedToOpen

    var body: some View {
        TodayView()
            .environment(events)
            .environment(AppActions.shared)
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
            .alert("Bite couldn't open your log", isPresented: $storeProblem) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("It's still on your phone, and the next update will open it. Until then, what you add isn't kept.")
            }
    }

    private var needsGoal: Binding<Bool> {
        Binding(
            get: { !onboarded },
            set: { presented in if !presented { onboarded = true } }
        )
    }
}
