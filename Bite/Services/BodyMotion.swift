import Foundation

/// How the bodies move: a few poses, a walk in place, breathing and a slow sway, and a director
/// that holds each pose a while and blends to the next. Foundation only, like the rig.
enum BodyMove: String, CaseIterable, Identifiable {
    case auto, stand, walk, strike, flex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: tr("Auto")
        case .stand: tr("Stand")
        case .walk: tr("Walk")
        case .strike: tr("Pose")
        case .flex: tr("Flex")
        }
    }
}

enum BodyMotion {
    private typealias Angles = [String: SIMD3<Float>]

    private struct Still {
        let angles: Angles
        let left: Reach
        let right: Reach
    }

    private static let poses: [String: Still] = [
        // Weight on the right leg, the left knee soft, arms loose by the thighs.
        "stand": Still(
            angles: [
                "root": SIMD3(0, -4, 2.5), "spineLow": SIMD3(0, 2, -1.5), "spineMid": SIMD3(-1, 1, -1), "chest": SIMD3(-2, 1, -0.5), "neck": SIMD3(2, 0, 1), "head": SIMD3(0, 2, -2.5),
                "clavicle.L": SIMD3(0, 0, -3), "clavicle.R": SIMD3(0, 0, 3), "hand.L": SIMD3(0, 0, 4), "hand.R": SIMD3(0, 0, -4),
                "thigh.L": SIMD3(-6, 4, -5), "shin.L": SIMD3(12, 0, 0), "foot.L": SIMD3(-6, 8, 4),
                "thigh.R": SIMD3(1, -4, 7), "shin.R": SIMD3(2, 0, 0), "foot.R": SIMD3(-2, -6, -5),
            ],
            left: Reach(bone: "root", at: SIMD3(0.4, -0.95, 0.55), pole: SIMD3(0.3, 0, -1), flank: .hip),
            right: Reach(bone: "root", at: SIMD3(0.4, -0.9, 0.5), pole: SIMD3(0.3, 0, -1), flank: .hip)
        ),
        // Hands on the hips, chest up, feet apart.
        "hips": Still(
            angles: [
                "spineLow": SIMD3(2, 0, 0), "spineMid": SIMD3(3, 0, 0), "chest": SIMD3(3, 0, 0), "neck": SIMD3(-3, 0, 0), "head": SIMD3(-2, 0, 0),
                "clavicle.L": SIMD3(0, 0, 2), "clavicle.R": SIMD3(0, 0, -2), "hand.L": SIMD3(0, 0, -20), "hand.R": SIMD3(0, 0, 20),
                "thigh.L": SIMD3(0, 8, -1), "shin.L": SIMD3(2, 0, 0), "foot.L": SIMD3(0, 10, 1),
                "thigh.R": SIMD3(0, -8, 1), "shin.R": SIMD3(2, 0, 0), "foot.R": SIMD3(0, -10, -1),
            ],
            left: Reach(bone: "root", at: SIMD3(0.12, 1.25, 0.7), pole: SIMD3(1, 0.1, -0.7), flank: .waist),
            right: Reach(bone: "root", at: SIMD3(0.12, 1.25, 0.7), pole: SIMD3(1, 0.1, -0.7), flank: .waist)
        ),
        // A front double biceps: elbows out at the shoulders, fists by the head, chest high.
        "flex": Still(
            angles: [
                "spineLow": SIMD3(2, 0, 0), "spineMid": SIMD3(3, 0, 0), "chest": SIMD3(4, 0, 0), "neck": SIMD3(-4, 0, 0), "head": SIMD3(-3, 0, 0),
                "clavicle.L": SIMD3(0, 0, 4), "clavicle.R": SIMD3(0, 0, -4), "hand.L": SIMD3(-20, 0, 0), "hand.R": SIMD3(-20, 0, 0),
                "thigh.L": SIMD3(-2, 10, -1), "shin.L": SIMD3(5, 0, 0), "foot.L": SIMD3(0, 14, 1),
                "thigh.R": SIMD3(-2, -10, 1), "shin.R": SIMD3(5, 0, 0), "foot.R": SIMD3(0, -14, -1),
            ],
            left: Reach(bone: "chest", at: SIMD3(2.7, 3.0, 0.7), pole: SIMD3(1, -0.6, -0.1)),
            right: Reach(bone: "chest", at: SIMD3(2.7, 3.0, 0.7), pole: SIMD3(1, -0.6, -0.1))
        ),
        // Dramatic, the manga way: hips cocked one way and shoulders the other, a hand held up
        // before the face, the other arm flung down and back, the head tilted.
        "strike": Still(
            angles: [
                "root": SIMD3(0, 24, 6), "spineLow": SIMD3(4, -8, -3), "spineMid": SIMD3(6, -16, -4), "chest": SIMD3(3, -8, -6), "neck": SIMD3(-4, 10, 6), "head": SIMD3(-6, 18, 14),
                "clavicle.L": SIMD3(0, 0, -2), "clavicle.R": SIMD3(0, 0, -6), "hand.R": SIMD3(-10, 0, 20), "hand.L": SIMD3(10, 0, 30),
                "thigh.L": SIMD3(-16, 12, -6), "shin.L": SIMD3(22, 0, 0), "foot.L": SIMD3(-10, 20, 0),
                "thigh.R": SIMD3(3, -10, -7), "shin.R": SIMD3(2, 0, 0), "foot.R": SIMD3(0, -16, 0),
            ],
            left: Reach(bone: "root", at: SIMD3(2.3, 0.3, -1.3), pole: SIMD3(1, 0, 0.3)),
            right: Reach(bone: "chest", at: SIMD3(0.35, 3.2, 1.95), pole: SIMD3(1, -0.5, 0.2))
        ),
    ]

    private struct Frame {
        var angles: Angles
        var left: Reach
        var right: Reach
        var offset = SIMD3<Float>(0, 0, 0)
    }

    /// Walking in place, one stride every 1.1 s: legs swing, knees fold through the swing, arms
    /// counter-swing, hips turn and drop, the body bobs.
    private static func walk(_ t: Double) -> Frame {
        let f = Float(t * .pi * 2 / 1.1), s = sin(f), cl = max(0, cos(f)), cr = max(0, -cos(f))
        return Frame(
            angles: [
                "root": SIMD3(2, 6 * s, 3 * s), "spineLow": SIMD3(0, -2 * s, -1 * s), "spineMid": SIMD3(-1, -3 * s, -1 * s), "chest": SIMD3(-2, -4 * s, 0), "neck": SIMD3(2, 2 * s, 0), "head": SIMD3(0, 3 * s, 0),
                "clavicle.L": SIMD3(0, 0, -2), "clavicle.R": SIMD3(0, 0, 2), "hand.L": SIMD3(0, 0, 4), "hand.R": SIMD3(0, 0, -4),
                "thigh.L": SIMD3(-24 * s, 0, -8), "shin.L": SIMD3(5 + 38 * pow(cl, 1.6), 0, 0), "foot.L": SIMD3(-10 * cl + 6 * max(0, -s), 0, 8),
                "thigh.R": SIMD3(24 * s, 0, 8), "shin.R": SIMD3(5 + 38 * pow(cr, 1.6), 0, 0), "foot.R": SIMD3(-10 * cr + 6 * max(0, s), 0, -8),
            ],
            left: Reach(bone: "root", at: SIMD3(0.4, -0.85, 0.5 - 1.1 * s), pole: SIMD3(0.2, 0, -1), flank: .hip),
            right: Reach(bone: "root", at: SIMD3(0.4, -0.85, 0.5 + 1.1 * s), pole: SIMD3(0.2, 0, -1), flank: .hip),
            offset: SIMD3(0, 0.22 * (abs(cos(f)) - 0.5), 0)
        )
    }

    private static func frame(_ name: String, _ t: Double) -> Frame {
        if name == "walk" { return walk(t) }
        let still = poses[name] ?? poses["stand"]!
        return Frame(angles: still.angles, left: still.left, right: still.right)
    }

    /// Standing, for the small still bodies.
    static var still: Pose { held(.stand) }

    /// One move held still, for Reduce Motion: no breathing, no blend, the walk mid-stride.
    static func held(_ move: BodyMove) -> Pose {
        let s = frame(move == .auto ? "stand" : move.rawValue, 0.275)
        return Pose(angles: s.angles, arms: ["L": (s.left, s.left, 0), "R": (s.right, s.right, 0)], offset: s.offset)
    }

    /// Holds each pose a while and blends to the next over 1.15 s; or keeps one move.
    final class Director {
        private static let order = ["stand", "strike", "hips", "walk", "flex", "walk"]
        private static let hold: [String: Double] = ["stand": 3.0, "strike": 3.2, "hips": 3.0, "flex": 3.0, "walk": 4.4]
        private(set) var move: BodyMove = .auto
        private var current = "stand", previous = "stand", since: Double = -1, step = 0

        func set(_ move: BodyMove) {
            self.move = move
            let next = move == .auto ? current : move.rawValue
            if next != current { previous = current; current = next; since = -1 }
        }

        func pose(at t: Double, breathing: Bool = true) -> Pose {
            if since < 0 { since = t }
            if move == .auto, t - since > Director.hold[current, default: 3] {
                previous = current
                step = (step + 1) % Director.order.count
                current = Director.order[step]
                since = t
            }
            let k = Float(min((t - since) / 1.15, 1)), e = k * k * (3 - 2 * k)
            let a = BodyMotion.frame(previous, t), b = BodyMotion.frame(current, t)
            var angles: Angles = [:]
            for name in Set(a.angles.keys).union(b.angles.keys) {
                let x = a.angles[name] ?? SIMD3(0, 0, 0), y = b.angles[name] ?? SIMD3(0, 0, 0)
                angles[name] = x + (y - x) * e
            }
            if breathing {
                // Breathing and a slow sway, on top of any pose.
                let breath = Float(sin(t * .pi * 2 / 4.2)), sway = Float(sin(t * .pi * 2 / 7.5))
                angles["chest", default: SIMD3(0, 0, 0)] += SIMD3(-1.6 * breath, 0, 0)
                angles["spineMid", default: SIMD3(0, 0, 0)] += SIMD3(-0.7 * breath, 0, 0)
                angles["root", default: SIMD3(0, 0, 0)] += SIMD3(0, 1.5 * sway, 0.8 * sway)
                angles["head", default: SIMD3(0, 0, 0)] += SIMD3(0.8 * breath, 2 * sway, 0)
            }
            return Pose(angles: angles, arms: ["L": (a.left, b.left, e), "R": (a.right, b.right, e)], offset: a.offset + (b.offset - a.offset) * e)
        }
    }
}
