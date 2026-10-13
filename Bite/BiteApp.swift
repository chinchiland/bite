import SwiftUI
import SwiftData
import TipKit

@main
struct BiteApp: App {
    let container = BiteStore.container
    @UIApplicationDelegateAdaptor(BiteAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Typeface.setUp()
        #if BITE_DEMO
        // Bite Demo opens on the seeded day every time: past the goal screen, Health on, and
        // the goal the demo was written for, whatever was changed last time.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "onboarded")
        defaults.set(true, forKey: "health.asked")
        defaults.set(2000, forKey: "goal.kcal")
        for key in ["usual.dismissed", "checkin.history", "water.goal", "goal.split", "health.addBurned"] {
            defaults.removeObject(forKey: key)
        }
        #endif
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo { DemoData.seed(container.mainContext) }
        #endif
        // Tips teach the hidden gestures once, in place, at most one a day. Bite Demo shows
        // them too; the screenshots run without them.
        #if BITE_DEMO
        try? Tips.configure([.displayFrequency(.daily)])
        #else
        if !BiteStore.isDemo {
            try? Tips.configure([.displayFrequency(.daily)])
        }
        #endif
        HealthSync.shared.start(container)
        WidgetBridge.shared.start()
        Reminders.start(container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            #if BITE_DEMO
            // Opened again on a new day, Bite Demo moves its story to the new day.
            DemoData.moveToToday(container.mainContext)
            #endif
            // Back in front: Health catches up with anything logged from Siri, or written
            // while the phone was locked; the nudges are planned three days ahead again.
            HealthSync.shared.soon()
            Task { await Reminders.reschedule(context: container.mainContext) }
        }
    }
}
