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

/// "Scan food with Bite": opens on the camera. Put it on the Action button, in Control Center
/// or on the Lock Screen (the Scan control) to scan in one press. It lives in Shared so the
/// widget extension can offer it; with openAppWhenRun it always runs in the app.
struct ScanFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan food"
    static let description = IntentDescription("Opens Bite on the camera, ready for a barcode or your plate.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppActions.shared.pendingScan = true }
        return .result()
    }
}
