import SwiftUI
import TipKit

/// Press and hold a food: shown once you logged again, by search or scan, a food already in
/// your last two weeks, the long way round. Gone once you use the hold menu.
struct FoodTileTip: Tip {
    @Parameter static var relogged: Bool = false

    var title: Text { Text("Press and hold a food") }
    var message: Text? { Text("Change it, add it again, save it or delete it.") }
    var image: Image? { Image(systemName: "hand.tap.fill") }
    var rules: [Rule] { [#Rule(Self.$relogged) { $0 == true }] }
    var options: [any Option] { [MaxDisplayCount(2)] }
}

/// The switcher behind the day's name: shown once Bite has been opened on three different days.
/// Gone once you switch.
struct DaySwitcherTip: Tip {
    /// Donated once a calendar day, so three means three days.
    static let openedOnDay = Tips.Event(id: "home.openedOnDay")

    var title: Text { Text("Another day, or your week") }
    var message: Text? { Text("Tap here for yesterday, or your last 7 and 30 days.") }
    var image: Image? { Image(systemName: "calendar") }
    var rules: [Rule] { [#Rule(Self.openedOnDay) { $0.donations.count >= 3 }] }
    var options: [any Option] { [MaxDisplayCount(2)] }
}

/// Tap a meal's time: shown once you changed a logged food's time on its page instead. Gone
/// once you open the time from the timeline.
struct MealTimeTip: Tip {
    @Parameter static var movedTheLongWay: Bool = false

    var title: Text { Text("Ate it earlier?") }
    var message: Text? { Text("Tap a meal's time to change when you ate it.") }
    var image: Image? { Image(systemName: "clock.fill") }
    var rules: [Rule] { [#Rule(Self.$movedTheLongWay) { $0 == true }] }
    var options: [any Option] { [MaxDisplayCount(2)] }
}
