import SwiftUI
import SwiftData

@main
struct BiteApp: App {
    let container: ModelContainer

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        let demo = false
        #endif
        do {
            container = try ModelContainer(
                for: FoodEntry.self, SavedFood.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: demo)
            )
        } catch {
            fatalError("Could not open the food log: \(error)")
        }
        #if DEBUG
        if demo { DemoData.seed(container.mainContext) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
