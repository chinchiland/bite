import SwiftUI
import TipKit

/// Shown once on the first food of the day: the long press is where editing lives.
struct FoodTileTip: Tip {
    var title: Text { Text("Press and hold a food") }
    var message: Text? { Text("Change it, add it again, save it or delete it.") }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Shown on the day's name from the third visit: the switcher is easy to miss.
struct DaySwitcherTip: Tip {
    static let opened = Tips.Event(id: "home.opened")

    var title: Text { Text("Another day, or your week") }
    var message: Text? { Text("Tap here for yesterday, or your last 7 and 30 days.") }
    var image: Image? { Image(systemName: "calendar") }

    var rules: [Rule] {
        [#Rule(Self.opened) { $0.donations.count >= 3 }]
    }
}
