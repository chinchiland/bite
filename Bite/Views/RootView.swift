import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("firstRun.stage") private var firstRunRaw = FirstRun.done.rawValue
    @AppStorage("firstRun.day") private var firstRunDay = 0.0
    @State private var startTapped = false
    @State private var events = LogEvents()
    @State private var storeProblem = BiteStore.failedToOpen
    @Environment(\.scenePhase) private var scenePhase
    /// The log as the screens read it. A widget or Siri that wrote to it while Bite was away
    /// leaves the main context holding old values, so Bite reads through a fresh one then.
    @State private var context = BiteStore.container.mainContext
    @State private var seenWrite = AppGroup.defaults.double(forKey: AppGroup.Key.wroteAt)

    var body: some View {
        #if DEBUG
        if let gallery = WidgetGallery.requested {
            gallery
        } else {
            journal
        }
        #else
        journal
        #endif
    }

    private var journal: some View {
        TodayView()
            .environment(events)
            .environment(AppActions.shared)
            .modelContext(context)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let wrote = AppGroup.defaults.double(forKey: AppGroup.Key.wroteAt)
                guard wrote > seenWrite else { return }
                seenWrite = wrote
                let fresh = ModelContext(BiteStore.container)
                fresh.autosaveEnabled = true
                context = fresh
            }
            .fullScreenCover(isPresented: needsWelcome, onDismiss: {
                // The first bite comes once the welcome has gone.
                if startTapped { firstRunRaw = FirstRun.firstBite.rawValue }
            }) {
                WelcomeView {
                    firstRunDay = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                    startTapped = true
                    onboarded = true
                }
                .interactiveDismissDisabled()
            }
            // bite://scan, from the Scan widget, opens on the camera; any other link opens Today.
            .onOpenURL { url in
                if url.scheme == "bite", url.host == "scan" { AppActions.shared.pendingScan = true }
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
