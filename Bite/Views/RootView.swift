import SwiftUI

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("firstRun.stage") private var firstRunRaw = FirstRun.done.rawValue
    @AppStorage("firstRun.day") private var firstRunDay = 0.0
    @State private var events = LogEvents()
    @State private var storeProblem = BiteStore.failedToOpen

    var body: some View {
        TodayView()
            .environment(events)
            .environment(AppActions.shared)
            .fullScreenCover(isPresented: needsWelcome) {
                WelcomeView {
                    firstRunDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                    firstRunRaw = FirstRun.firstBite.rawValue
                    onboarded = true
                }
                .interactiveDismissDisabled()
            }
            .alert("Bite couldn't open your log", isPresented: $storeProblem) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("It's still on your phone, and the next update will open it. Until then, what you add isn't kept.")
            }
    }

    private var needsWelcome: Binding<Bool> {
        Binding(
            get: { !onboarded },
            set: { presented in if !presented { onboarded = true } }
        )
    }
}
