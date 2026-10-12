import SwiftUI
import SwiftData
import TipKit

@main
struct BiteApp: App {
    let container = BiteStore.container
    #if BITE_DEMO
    @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        Typeface.setUp()
        #if BITE_DEMO
        // Bite Demo opens on the seeded day every time: past the goal screen, Health on, and
        // the goal the demo was written for, whatever was changed last time.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "onboarded")
        defaults.set(true, forKey: "health.asked")
        defaults.set(2000, forKey: "goal.kcal")
        for key in ["usual.dismissed", "goal.offerHiddenUntil", "water.goal", "goal.split", "health.addBurned"] {
            defaults.removeObject(forKey: key)
        }
        #endif
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo { DemoData.seed(container.mainContext) }
        #endif
        // Tips teach the hidden gestures once, in place. Screenshots run without them.
        if !BiteStore.isDemo {
            try? Tips.configure([.displayFrequency(.immediate)])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if BITE_DEMO
        // Opened again on a new day, Bite Demo writes its story around the new day.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { DemoData.reseedIfStale(container.mainContext) }
        }
        #endif
    }
}
