import AppIntents
import Foundation

/// The phrases Siri knows, and the actions Spotlight, Shortcuts and the Action button list.
struct BiteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanFoodIntent(),
            phrases: [
                "Scan food with \(.applicationName)",
                "Scan with \(.applicationName)",
                "Open the \(.applicationName) scanner",
            ],
            shortTitle: "Scan food",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: LogSavedFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)",
            ],
            shortTitle: "Log a saved food",
            systemImageName: "bookmark"
        )
    }
}
