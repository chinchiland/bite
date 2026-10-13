import SwiftUI
import UIKit

/// Bite's haptics: six, each with one meaning, so a buzz always says the same thing.
/// tick: a value moved under your finger. land: food went into your day. drop: a glass of
/// water. click: a crisp yes (a code read, a photo taken, a like, a bookmark, a setting kept).
/// reached: a goal reached or a result you waited for. snag and failed: a dead end with a way
/// out, and something that didn't work. Removing, navigating and going over stay silent.
enum Feel {
    static let tick = SensoryFeedback.selection
    static let land = SensoryFeedback.impact(flexibility: .soft, intensity: 0.7)
    static let drop = SensoryFeedback.impact(flexibility: .soft, intensity: 0.45)
    static let click = SensoryFeedback.impact(flexibility: .rigid, intensity: 0.6)
    static let reached = SensoryFeedback.success
    static let snag = SensoryFeedback.warning
    static let failed = SensoryFeedback.error

    enum Kind {
        case tick, land, drop, click, reached, snag, failed
    }

    /// The same feels, played now: for a view that leaves as it plays, like a sheet's Add.
    @MainActor static func play(_ kind: Kind) {
        switch kind {
        case .tick: UISelectionFeedbackGenerator().selectionChanged()
        case .land: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        case .drop: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
        case .click: UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        case .reached: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .snag: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failed: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Bite's motion: five curves, each with one job, so the same kind of change always moves the
/// same way. Springs keep their speed when interrupted; none of them wobbles.
enum Motion {
    /// A direct answer to a finger: chips, toggles, a selection, a card folding away.
    static let respond = Animation.snappy(duration: 0.3)
    /// Content moving into place: tiles in and out, the toast, a section appearing.
    static let settle = Animation.smooth(duration: 0.4)
    /// Numbers rolling, rules and the ring filling to a new value. Never a bounce on a number.
    static let count = Animation.smooth(duration: 0.5)
    /// Data drawing itself the first time on a screen: the ring, the columns.
    static let reveal = Animation.smooth(duration: 0.9)
    /// The give under a finger: quick, a touch of spring, no wobble.
    static let press = Animation.spring(duration: 0.22, bounce: 0.1)
}
