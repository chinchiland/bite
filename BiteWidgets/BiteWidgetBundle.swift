import SwiftUI
import WidgetKit

/// Bite's widgets: Today and Log on the Home Screen, Today on the Lock Screen, and a glass of
/// water in Control Center.
@main
struct BiteWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LogWidget()
        if #available(iOS 18.0, *) {
            WaterControl()
        }
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
