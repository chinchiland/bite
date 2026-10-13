import SwiftUI
import WidgetKit

/// Bite's widgets: Today, Log and Scan on the Home Screen (StandBy shows the small ones); Today,
/// Scan and Water on the Lock Screen; and Scan food and a glass of water as controls, for
/// Control Center, the Lock Screen's two buttons and the Action button.
@main
struct BiteWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LogWidget()
        ScanWidget()
        WaterWidget()
        if #available(iOS 18.0, *) {
            ScanControl()
            WaterControl()
        }
    }
}

/// Bite's camera in one press, from Control Center, the Lock Screen or the Action button.
@available(iOS 18.0, *)
struct ScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "scan") {
            ControlWidgetButton(action: ScanFoodIntent()) {
                Label("Scan food", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan food")
        .description("Open Bite on the camera.")
    }
}

/// A glass of water from Control Center or the Lock Screen, without opening Bite.
@available(iOS 18.0, *)
struct WaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "water") {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("Add water", systemImage: "drop.fill")
            }
        }
        .displayName("Add water")
        .description("A glass of water, one tap.")
    }
}
