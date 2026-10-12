import SwiftUI
import SwiftData
import TipKit

@main
struct BiteApp: App {
    let container = BiteStore.container

    init() {
        Typeface.setUp()
        #if DEBUG
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
    }
}
