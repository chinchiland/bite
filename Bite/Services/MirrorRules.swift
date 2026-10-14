import Foundation

// Your mirror's rules, Foundation only so tools/check.sh tests them on Linux: how long between
// two photos, when Bite asks for the next one, how two photos line up, and how much of a tilted
// photo is kept once it is straightened.

/// How long between two photos, in the unit people say it in: days under two weeks, weeks
/// under two months, months under a year, then years.
enum MirrorGap: Equatable {
    case days(Int)
    case weeks(Int)
    case months(Int)
    case years(Int)

    static func between(_ first: Date, _ second: Date, calendar: Calendar = .current) -> MirrorGap {
        let start = calendar.startOfDay(for: min(first, second))
        let end = calendar.startOfDay(for: max(first, second))
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case ..<14: return .days(days)
        case ..<60: return .weeks(Int((Double(days) / 7).rounded()))
        case ..<365: return .months(Int((Double(days) / 30.44).rounded()))
        default: return .years(Int((Double(days) / 365.25).rounded()))
        }
    }

    /// Eight weeks or more: the one gap worth drawing in slowly, once.
    var isLong: Bool {
        switch self {
        case .days: false
        case .weeks(let weeks): weeks >= 8
        case .months, .years: true
        }
    }
}

/// When Bite asks for a photo, and what you said, kept as JSON. A photo every four weeks; the
/// morning a weighing comes in, from 25 days. "Not now" waits a week; three in a row and Bite
/// stops asking (Settings still opens your mirror). No notification, no streak, no count.
struct MirrorHistory: Codable, Equatable {
    var notNowsInARow = 0
    var quietUntil: Date?

    static let cadenceDays = 28
    static let weighedDays = 25

    /// Asked, and still answering.
    var isListening: Bool { notNowsInARow < 3 }

    /// The ask for the first photo: from the third day you open Bite, never on the first two,
    /// which are for learning to log.
    func asksFirst(now: Date, firstDay: Date?, calendar: Calendar = .current) -> Bool {
        guard isListening, !isQuiet(now: now) else { return false }
        guard let firstDay else { return true }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstDay), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= 2
    }

    /// The ask for the next photo: four weeks after the last, or from 25 days on a morning
    /// with a new weighing, when you are in the bathroom anyway.
    func asksNext(now: Date, newest: Date, weighedToday: Bool, calendar: Calendar = .current) -> Bool {
        guard isListening, !isQuiet(now: now) else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: newest), to: calendar.startOfDay(for: now)).day ?? 0
        return days >= Self.cadenceDays || (weighedToday && days >= Self.weighedDays)
    }

    func isQuiet(now: Date) -> Bool {
        quietUntil.map { now < $0 } ?? false
    }

    /// "Not now": back in a week.
    mutating func notNow(now: Date, calendar: Calendar = .current) {
        notNowsInARow += 1
        quietUntil = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))
    }

    /// A photo was kept: the next ask is four weeks away, and the count of Not nows starts over.
    mutating func took() {
        notNowsInARow = 0
        quietUntil = nil
    }
}

/// Where a body sits in a kept photo, as fractions of the photo from the top left: the middle
/// of the shoulders, and the torso's height. What two photos are lined up by.
struct MirrorPlacement: Equatable {
    var centerX: Double
    var shoulderY: Double
    var spanTorso: Double

    /// The same point in a frame of `frameAspect` (width over height) that shows a photo of
    /// `photoAspect` filled to its edges, the way the comparison draws both photos.
    func filling(photoAspect: Double, frameAspect: Double) -> MirrorPlacement {
        guard photoAspect > 0, frameAspect > 0 else { return self }
        if photoAspect > frameAspect {
            // Wider than the frame: its sides are cut.
            let stretch = photoAspect / frameAspect
            return MirrorPlacement(centerX: centerX * stretch - (stretch - 1) / 2, shoulderY: shoulderY, spanTorso: spanTorso)
        }
        // Taller than the frame: its top and bottom are cut.
        let stretch = frameAspect / photoAspect
        return MirrorPlacement(centerX: centerX, shoulderY: shoulderY * stretch - (stretch - 1) / 2, spanTorso: spanTorso * stretch)
    }
}

/// How to draw one photo of a pair so the two bodies line up: scaled around its shoulders so
/// the torsos are the same height, then moved so the shoulders meet. The photo that moves is
/// always the one whose body is smaller, so it grows and still fills the frame; never an edge of
/// it inside the frame. Capture is advice; this is where a pair is really lined up.
struct MirrorAlign: Equatable {
    var scale: Double
    /// The point the moving photo is scaled around: its shoulders, in the frame.
    var anchorX: Double
    var anchorY: Double
    /// Then moved by, as fractions of the frame.
    var dx: Double
    var dy: Double
    /// The newer photo moves (its body was the smaller); otherwise the older one does.
    var movesNewer = false

    static let none = MirrorAlign(scale: 1, anchorX: 0.5, anchorY: 0.5, dx: 0, dy: 0)

    /// Both placements already in the frame's own fractions. A pair with no body found in one
    /// of them is shown as it is.
    static func make(older: MirrorPlacement?, newer: MirrorPlacement?) -> MirrorAlign {
        guard let older, let newer, older.spanTorso > 0.05, newer.spanTorso > 0.05 else { return .none }
        let movesNewer = newer.spanTorso < older.spanTorso
        let moving = movesNewer ? newer : older
        let still = movesNewer ? older : newer
        // A body measured badly could ask for a wild zoom; past 1.4 it is a bad read.
        let align = MirrorAlign(
            scale: min(still.spanTorso / moving.spanTorso, 1.4),
            anchorX: moving.centerX,
            anchorY: moving.shoulderY,
            dx: still.centerX - moving.centerX,
            dy: still.shoulderY - moving.shoulderY,
            movesNewer: movesNewer
        )
        return align.filling()
    }

    /// Grown just enough that the moved photo still covers the whole frame once it is moved.
    func filling() -> MirrorAlign {
        func need(_ anchor: Double, _ shift: Double) -> Double {
            if shift > 0 { return 1 + shift / max(anchor, 0.05) }
            if shift < 0 { return 1 - shift / max(1 - anchor, 0.05) }
            return 1
        }
        var copy = self
        copy.scale = min(max(scale, need(anchorX, dx), need(anchorY, dy)), 1.6)
        return copy
    }

    /// Where a point of the moving photo lands.
    func place(x: Double, y: Double) -> (x: Double, y: Double) {
        (anchorX + scale * (x - anchorX) + dx, anchorY + scale * (y - anchorY) + dy)
    }
}

/// Straightening a photo the hand tilted a little.
enum MirrorLevel {
    /// Tilts past this are kept as they were: straightening would cut too much.
    static let maxDegrees = 6.0

    /// The share of the photo's width and height left once it is turned by `degrees` and cut to
    /// its own shape again.
    static func keptShare(width: Double, height: Double, degrees: Double) -> Double {
        guard width > 0, height > 0 else { return 1 }
        let angle = abs(degrees) * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        return min(width / (width * cosine + height * sine), height / (width * sine + height * cosine))
    }
}
