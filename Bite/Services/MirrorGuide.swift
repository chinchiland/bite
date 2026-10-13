import Foundation

// Your mirror's live guide, Foundation only so tools/check.sh tests it on Linux: what the camera
// measures in a frame, and the one line it says about it. It speaks about the frame, never the
// body: where you stand, whether the phone is level, whether you are still.

/// One person in a frame, from 0 to 1 measured from the top left, the way the screen draws it.
/// The front camera's frames are mirrored like its preview, so left on the screen is left here.
struct MirrorBody: Equatable {
    var shoulderY: Double
    var hipY: Double
    /// Where the ankles are, when both are seen: the whole body is in the frame.
    var ankleY: Double?
    /// Halfway between the shoulders and the hips, across.
    var centerX: Double
    /// The highest point seen, the head, to keep room above it.
    var top: Double

    var spanTorso: Double { max(hipY - shoulderY, 0) }
    var spanFull: Double? { ankleY.map { max($0 - shoulderY, 0) } }
}

/// What the camera saw in one frame.
struct MirrorReading: Equatable {
    /// The person being guided, when the shoulders and hips are seen clearly enough to measure.
    var body: MirrorBody?
    /// Someone is there but too close: only the head and shoulders fit.
    var tooClose = false
    /// How much of the frame's height the person fills, 0 to 1.
    var height: Double = 0
    /// How bright the person is, 0 to 1.
    var luma: Double?

    static let nobody = MirrorReading()
}

/// Where the first photo stood, so the next one lands in the same frame. The same fractions as
/// `MirrorBody`, taken from the live frame at the moment the first photo was kept.
struct MirrorTarget: Equatable {
    var shoulderY: Double
    var hipY: Double
    var ankleY: Double?
    var centerX: Double

    var spanTorso: Double { max(hipY - shoulderY, 0) }
    var spanFull: Double? { ankleY.map { max($0 - shoulderY, 0) } }
}

/// The one thing the camera says, always in the same place, one at a time.
enum MirrorLine: Equatable {
    /// Propped: the phone is up but nobody is far enough away yet.
    case setUp
    case fitIn
    case stepBack
    case stepCloser
    /// The first photo, once stepping back stopped helping: the room's own distance.
    case yourSpot
    case level
    case holdStill
    case ready
    /// Propped, after 25 seconds: the photo is taken whatever the checks say.
    case takingNow
    case kept
}

/// Which of the first photo's marks the live frame matches, each drawn solid when it does.
struct MirrorMarks: Equatable {
    var shoulders = false
    var hips = false
    var ankles = false
    var center = false
}

/// A median of the last five values, then a gentle follow: the body pose moves a few percent
/// from frame to frame on its own, and a shutter waiting on the raw values would never fire.
struct MirrorSmoother: Equatable {
    private var recent: [Double] = []
    private(set) var value: Double?

    @discardableResult
    mutating func add(_ sample: Double) -> Double {
        recent.append(sample)
        if recent.count > 5 { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]
        let next = value.map { $0 + 0.3 * (median - $0) } ?? median
        value = next
        return next
    }

    mutating func reset() {
        recent = []
        value = nil
    }
}

/// The last ten values, to tell still from moving.
struct MirrorWindow: Equatable {
    private var values: [Double] = []

    var isFull: Bool { values.count >= 10 }
    var range: Double { (values.max() ?? 0) - (values.min() ?? 0) }

    mutating func add(_ value: Double) {
        values.append(value)
        if values.count > 10 { values.removeFirst() }
    }

    mutating func reset() { values = [] }
}

/// The guide: frames in, one line out, and when to take the photo. Fed about ten times a second
/// with what the camera measured and the phone's roll (0 upright, positive turned clockwise).
struct MirrorGuide {
    enum Mode: Equatable {
        /// Facing a mirror with the phone in hand, the back camera on your reflection.
        case mirror
        /// Standing on a sink or a shelf, the front camera on you, two meters away.
        case propped
    }

    struct Output: Equatable {
        var line: MirrorLine
        var level: Bool
        var marks: MirrorMarks
        /// Propped: 3, 2, 1 before the photo; 10 down to 1 when nobody could be seen.
        var countdown: Int?
        /// Take the photo now.
        var fire: Bool
    }

    let mode: Mode
    /// The first photo of this mode, when there is one.
    let target: MirrorTarget?

    // Tolerances, as fractions of the frame's height.
    static let closer = 0.06
    static let back = 0.09
    static let still = 0.02
    static let stillRoll = 1.5
    static let levelRoll = 2.0
    static let tooTilted = 6.0
    static let markTolerance = 0.03

    private var shoulder = MirrorSmoother()
    private var hip = MirrorSmoother()
    private var ankle = MirrorSmoother()
    private var center = MirrorSmoother()
    private var roll = MirrorSmoother()
    private var spans = MirrorWindow()
    private var centers = MirrorWindow()
    /// Where the shoulders are: the phone moving up and down changes no span.
    private var heights = MirrorWindow()
    private var rolls = MirrorWindow()

    private var line: MirrorLine = .fitIn
    private var isLevel = false
    private var isStill = false
    private var started: Double?
    /// Propped: the pose begins once someone stands far enough away; until then the screen is
    /// the setup screen.
    private var poseStarted: Double?
    private var noBodySince: Double?
    private var anklesSeenAt: Double?
    private var readySince: Double?
    private var readyTotal = 0.0
    private var lastTick: Double?
    /// The first photo: the closest the room let you get to a whole body, and since when.
    private var bestSpan: Double?
    private var bestSince: Double?
    private var spotFoundAt: Double?
    private var countdownEnds: Double?
    private var countdownLine: MirrorLine?
    private var keptAt: Double?
    /// One photo by itself per session; the shutter takes as many more as you like.
    private var autoDone = false

    init(mode: Mode, target: MirrorTarget?) {
        self.mode = mode
        self.target = target
        line = mode == .propped ? .setUp : .fitIn
    }

    /// The photo was kept, by the guide or by the shutter.
    mutating func kept(now: Double) {
        keptAt = now
        autoDone = true
        countdownEnds = nil
        countdownLine = nil
        readySince = nil
        readyTotal = 0
    }

    mutating func update(_ reading: MirrorReading, roll rawRoll: Double, now: Double) -> Output {
        if started == nil { started = now }
        let elapsed = lastTick.map { min(now - $0, 0.5) } ?? 0
        lastTick = now

        let roll = self.roll.add(rawRoll)
        rolls.add(roll)
        // Level within 2 degrees, and it stays level until 3: no flicker at the edge.
        isLevel = abs(roll) <= (isLevel ? Self.levelRoll * 1.5 : Self.levelRoll)

        // A countdown runs to the end whatever happens: someone two meters away can't stop it.
        if let ends = countdownEnds {
            let left = Int((ends - now).rounded(.up))
            if left <= 0 {
                let line = countdownLine ?? .ready
                kept(now: now)
                return Output(line: line, level: isLevel, marks: marks(reading.body), countdown: nil, fire: true)
            }
            return Output(line: countdownLine ?? .ready, level: isLevel, marks: marks(reading.body), countdown: left, fire: false)
        }

        if let keptAt, now - keptAt < 2.5 {
            return Output(line: .kept, level: isLevel, marks: marks(reading.body), countdown: nil, fire: false)
        }

        guard let body = reading.body else {
            return nobody(reading, now: now)
        }
        noBodySince = nil

        // Propped: the pose starts once someone stands back far enough to fit, under 85% of
        // the frame's height.
        if mode == .propped, poseStarted == nil {
            if reading.height > 0, reading.height < 0.85 {
                poseStarted = now
            } else {
                return output(.setUp, body: body, now: now, elapsed: elapsed)
            }
        }
        if poseStarted == nil { poseStarted = now }

        let shoulderY = shoulder.add(body.shoulderY)
        let hipY = hip.add(body.hipY)
        let centerX = center.add(body.centerX)
        var ankleY: Double?
        if let seen = body.ankleY {
            ankleY = ankle.add(seen)
            anklesSeenAt = now
        } else if let seenAt = anklesSeenAt, now - seenAt < 5 {
            // Ankles come and go at the frame's edge: keep the whole body for five seconds.
            ankleY = ankle.value
        } else {
            ankle.reset()
        }
        let torso = max(hipY - shoulderY, 0)
        let full = ankleY.map { max($0 - shoulderY, 0) }
        spans.add(full ?? torso)
        centers.add(centerX)
        heights.add(shoulderY)

        var smoothed = body
        smoothed.shoulderY = shoulderY
        smoothed.hipY = hipY
        smoothed.ankleY = ankleY
        smoothed.centerX = centerX

        if let distance = distanceLine(torso: torso, full: full, top: body.top, now: now) {
            return output(distance, body: smoothed, now: now, elapsed: elapsed)
        }
        if abs(roll) > Self.tooTilted {
            return output(.level, body: smoothed, now: now, elapsed: elapsed)
        }
        let factor = isStill ? 1.5 : 1
        isStill = spans.isFull && spans.range < Self.still * factor
            && centers.range < Self.still * factor
            && heights.range < Self.still * factor
            && rolls.range < Self.stillRoll * factor
        if !isStill {
            return output(.holdStill, body: smoothed, now: now, elapsed: elapsed)
        }
        if let spotFoundAt, now - spotFoundAt < 1.5 {
            return output(.yourSpot, body: smoothed, now: now, elapsed: elapsed)
        }
        return output(.ready, body: smoothed, now: now, elapsed: elapsed)
    }

    // MARK: Pieces

    /// Nobody to measure: too close, out of the frame, or a room too dark to see in.
    private mutating func nobody(_ reading: MirrorReading, now: Double) -> Output {
        if noBodySince == nil { noBodySince = now }
        readySince = nil
        // Whoever comes back is measured afresh, not pulled toward where someone was.
        shoulder.reset()
        hip.reset()
        center.reset()
        ankle.reset()
        spans.reset()
        centers.reset()
        heights.reset()
        isStill = false
        let line: MirrorLine
        if mode == .propped, poseStarted == nil {
            line = .setUp
        } else if reading.tooClose {
            line = .stepBack
        } else {
            line = .fitIn
        }
        self.line = line
        // Propped in a dark room: after 15 seconds without seeing anyone, a plain 10 second
        // countdown, so a room too dark to see in never costs the photo.
        if mode == .propped, !autoDone, let since = noBodySince, now - since >= 15 {
            countdownEnds = now + 10
            countdownLine = line
            return Output(line: line, level: isLevel, marks: MirrorMarks(), countdown: 10, fire: false)
        }
        return Output(line: line, level: isLevel, marks: MirrorMarks(), countdown: nil, fire: false)
    }

    /// Step back or closer: toward the first photo's distance, or for the very first photo
    /// until the whole body fits or the room stops you. Nil when the distance is right.
    private mutating func distanceLine(torso: Double, full: Double?, top: Double, now: Double) -> MirrorLine? {
        if let target {
            // Like with like: the whole body when both show it, else the torso.
            let live: Double
            let goal: Double
            if let full, let whole = target.spanFull {
                live = full
                goal = whole
            } else {
                live = torso
                goal = target.spanTorso
            }
            // A line, once shown, stays until you are well inside the tolerance.
            let closer = line == .stepCloser ? Self.closer / 1.5 : Self.closer
            let back = line == .stepBack ? Self.back / 1.5 : Self.back
            if live < goal - closer { return .stepCloser }
            if live > goal + back { return .stepBack }
            return nil
        }
        // The first photo. The whole body in the frame, with room above the head.
        if let full {
            if top < 0.03 { return .stepBack }
            if full < 0.38 { return .stepCloser }
            spotFoundAt = spotFoundAt ?? now
            return nil
        }
        // Only the torso fits: step back until the room stops you. Smaller is farther, so the
        // best is the smallest span seen; six seconds without getting smaller is your spot.
        if spotFoundAt != nil { return nil }
        if bestSpan == nil || torso < (bestSpan ?? 0) - 0.01 {
            bestSpan = torso
            bestSince = now
        }
        if let since = bestSince, now - since >= 6 {
            spotFoundAt = now
            return nil
        }
        return .stepBack
    }

    /// The line out, and whether to take the photo: Ready held 0.8 seconds, or Ready for 2.5
    /// seconds in all; propped, 25 seconds after the pose began whatever the checks say.
    private mutating func output(_ line: MirrorLine, body: MirrorBody, now: Double, elapsed: Double) -> Output {
        self.line = line
        var fire = false
        // After the photo, Ready offers another instead of taking it by itself.
        var shown = autoDone && line == .ready ? .kept : line
        if line == .ready {
            readySince = readySince ?? now
            readyTotal += elapsed
        } else {
            readySince = nil
        }
        if !autoDone {
            let heldReady = readySince.map { now - $0 >= 0.8 } ?? false
            let tookLong = mode == .propped && (poseStarted.map { now - $0 >= 25 } ?? false)
            if heldReady || readyTotal >= 2.5 || tookLong {
                if tookLong && !heldReady && readyTotal < 2.5 { shown = .takingNow }
                if mode == .propped {
                    // Out loud: three, two, one, then the photo.
                    countdownEnds = now + 3
                    countdownLine = shown
                    return Output(line: shown, level: isLevel, marks: marks(body), countdown: 3, fire: false)
                }
                kept(now: now)
                fire = true
            }
        }
        return Output(line: shown, level: isLevel, marks: marks(body), countdown: nil, fire: fire)
    }

    private func marks(_ body: MirrorBody?) -> MirrorMarks {
        guard let body, let target else { return MirrorMarks() }
        var marks = MirrorMarks()
        marks.shoulders = abs(body.shoulderY - target.shoulderY) < Self.markTolerance
        marks.hips = abs(body.hipY - target.hipY) < Self.markTolerance
        if let ankle = body.ankleY, let goal = target.ankleY {
            marks.ankles = abs(ankle - goal) < Self.markTolerance
        }
        marks.center = abs(body.centerX - target.centerX) < Self.markTolerance * 1.4
        return marks
    }
}
