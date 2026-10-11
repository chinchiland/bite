import Foundation

extension Double {
    /// Rounded to a whole number, or 0 for values Int cannot hold (NaN, infinity), so a bad
    /// number on screen can never crash the app.
    var safeInt: Int {
        isFinite && abs(self) < 1e15 ? Int(rounded()) : 0
    }

    /// Whole numbers with grouping, the way calories read best: "1,240".
    var kcalText: String { safeInt.formatted() }

    /// A count with grouping: "8,432" steps.
    var countText: String { safeInt.formatted() }

    /// Grams people can read at a glance: "0.4", "8.1", "62".
    var gramsText: String {
        isFinite && self < 10
            ? formatted(.number.precision(.fractionLength(0...1)))
            : safeInt.formatted()
    }
}
