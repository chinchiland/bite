import Foundation

/// How far a photo is dimmed to become the room behind a screen. A white plate and a dark bar
/// table have to sit at the same depth, or the words on them would read on one and not the
/// other, so each photo is brought toward one brightness. A dark photo keeps its own darkness:
/// it is never lifted past what it has, only left less dimmed.
enum RoomTone {
    /// The brightness a room aims for, on a scale from 0 to 1.
    static let target = 0.2
    /// The most a photo is dimmed, whatever its brightness.
    static let darkest = 0.2
    /// The least a photo is dimmed, so even a dark one stays behind the words.
    static let lightest = 0.62
    /// The brightest a room may get anywhere. Quiet words sit straight on the room under the
    /// cover, and at this brightness they still have 4.5 to 1 against it.
    static let brightest = 0.36

    /// What to multiply a photo's colors by, given its mean and its brightest part, each from
    /// 0 to 1.
    static func level(mean: Double, peak: Double) -> Double {
        let depth = min(max(target / max(mean, 0.05), darkest), lightest)
        return min(depth, brightest / max(peak, 0.05))
    }

    /// The brightest part of a room, past the few specks that would decide it alone.
    static func peak(of brightness: [Double]) -> Double {
        guard !brightness.isEmpty else { return 0 }
        let sorted = brightness.sorted()
        return sorted[min(Int(Double(sorted.count) * 0.98), sorted.count - 1)]
    }

    /// The brightness of an sRGB color's channels, each from 0 to 1, as the eye weighs them.
    static func brightness(red: Double, green: Double, blue: Double) -> Double {
        red * 0.2126 + green * 0.7152 + blue * 0.0722
    }
}
