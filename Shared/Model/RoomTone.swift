import Foundation

/// How far a photo is dimmed to become the room behind a screen. A white plate and a dark bar
/// table have to sit at the same depth, or the words on them would read on one and not the
/// other, so each photo is brought toward one brightness. A dark photo keeps its own darkness:
/// it is never lifted past what it has, only left less dimmed.
enum RoomTone {
    /// The brightness a room aims for, on a scale from 0 to 1.
    static let target = 0.14
    /// The most a photo is dimmed, whatever its brightness.
    static let darkest = 0.2
    /// The least a photo is dimmed, so even a dark one stays behind the words.
    static let lightest = 0.62

    /// What to multiply a photo's colors by, given its mean brightness from 0 to 1.
    static func level(meanBrightness mean: Double) -> Double {
        min(max(target / max(mean, 0.05), darkest), lightest)
    }

    /// The brightness of an sRGB color's channels, each from 0 to 1, as the eye weighs them.
    static func brightness(red: Double, green: Double, blue: Double) -> Double {
        red * 0.2126 + green * 0.7152 + blue * 0.0722
    }
}
