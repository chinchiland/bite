import Foundation
import SwiftData

/// The glasses of water you had on a day, one tap each.
@Model
final class WaterDay {
    /// The start of the day.
    var day: Date = Date.now
    var glasses: Int = 0

    init(day: Date, glasses: Int = 0) {
        self.day = day
        self.glasses = glasses
    }
}
