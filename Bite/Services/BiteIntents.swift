import AppIntents
import Foundation
import Observation

/// Things the system asks the app to do when it opens: scan straight away, for the Action
/// button, Siri or a Control Center shortcut.
@MainActor
@Observable
final class AppActions {
    static let shared = AppActions()
    var pendingScan = false
}

/// "Scan food with Bite": opens on the camera. Put it on the Action button to scan in one
/// press.
struct ScanFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan food"
    static let description = IntentDescription("Opens Bite on the camera, ready for a barcode or your plate.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppActions.shared.pendingScan = true }
        return .result()
    }
}

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
