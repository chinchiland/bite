import SwiftUI

/// A standing figure, seen from the front, whose build follows a BMI: shoulders, chest, waist,
/// belly, hips and limbs fill out above 22 and slim below it, while the head and the height never
/// change. A woman's carries it lower, with narrower shoulders and waist and wider hips. Smooth
/// curves through a few points of the outline, the limbs as tapered joints, all joined into one
/// silhouette, so it is never a photo and never anyone in particular.
enum BodyFigure {
    static let grid = CGSize(width: 160, height: 260)

    /// 1 at a BMI of 22. A body's girth at one height grows with the square root of its BMI.
    static func build(bmi: Double) -> CGFloat {
        CGFloat(min(max((bmi / 22).squareRoot(), 0.85), 1.7))
    }

    static func outline(build: CGFloat, female: Bool) -> Path {
        let cx: CGFloat = 80
        let woman: CGFloat = female ? 1 : 0
        func grown(_ power: CGFloat) -> CGFloat { pow(build, power) }
        // Weight goes on the middle first: past a BMI of 25 the belly leads, below 22 the waist
        // shows. The frame moves a little, the tops of the limbs more than their ends.
        let shoulder = 29 * grown(0.5) * (1 - 0.1 * woman)
        let chest = 24.5 * grown(1) * (1 - 0.07 * woman)
        let waist = 20 * grown(1.7) * (1 - 0.12 * woman)
        let belly = 21.5 * grown(1.9) * (1 - 0.05 * woman)
        let hip = 25 * grown(1.15) * (1 + 0.1 * woman)
        let neck = 6.5 * grown(0.8) * (1 - 0.15 * woman)

        var parts = [
            Path(ellipseIn: CGRect(x: cx - 12.5, y: 3, width: 25, height: 32)),
            Path(CGRect(x: cx - neck, y: 28, width: neck * 2, height: 20)),
        ]

        // The torso: one smooth loop down the right side and back up the left.
        let side: [CGPoint] = [
            CGPoint(x: neck + 0.5, y: 41), CGPoint(x: shoulder - 8, y: 44), CGPoint(x: shoulder - 2, y: 48.5),
            CGPoint(x: shoulder, y: 57), CGPoint(x: chest, y: 74), CGPoint(x: waist, y: 98),
            CGPoint(x: belly, y: 116), CGPoint(x: hip, y: 136), CGPoint(x: hip - 3, y: 149),
        ]
        let loop = [CGPoint(x: cx, y: 41)] + side.map { CGPoint(x: cx + $0.x, y: $0.y) }
            + [CGPoint(x: cx, y: 153)] + side.reversed().map { CGPoint(x: cx - $0.x, y: $0.y) }
        parts.append(smoothLoop(through: loop))

        // The arms hang clear of the belly and the hips, however round they get.
        let upperArm = 13 * grown(1.1) * (1 - 0.1 * woman)
        let elbowWidth = 10.5 * grown(1) * (1 - 0.1 * woman)
        let wristWidth = 7 * grown(0.6) * (1 - 0.1 * woman)
        let elbow = max(shoulder + 2.5, max(waist, belly * 0.97) + elbowWidth / 2 + 3.5)
        let wrist = max(elbow + 2.5, hip + wristWidth / 2 + 3.5)
        let thigh = hip * 1.02
        let knee = 10.5 + 4 * (build - 1)
        let ankle = 9.5 + 2.5 * (build - 1)
        for direction: CGFloat in [-1, 1] {
            parts += limb([
                (CGPoint(x: cx + direction * (shoulder - 5), y: 59), upperArm),
                (CGPoint(x: cx + direction * elbow, y: 103), elbowWidth),
                (CGPoint(x: cx + direction * wrist, y: 145), wristWidth),
            ])
            parts.append(Path(ellipseIn: CGRect(x: cx + direction * (wrist + 0.5) - 4.5, y: 144.5, width: 9, height: 17)))
            parts += limb([
                (CGPoint(x: cx + direction * (thigh / 2 - 0.5), y: 143), thigh),
                (CGPoint(x: cx + direction * knee, y: 199), 13 * grown(0.8)),
                (CGPoint(x: cx + direction * (knee - 0.5), y: 214), 13.5 * grown(1)),
                (CGPoint(x: cx + direction * ankle, y: 249), 6.5 * grown(0.4)),
            ])
            parts.append(Path(ellipseIn: CGRect(x: cx + direction * (ankle + 2) - 7.5, y: 249.5, width: 15, height: 9)))
        }
        return parts.dropFirst().reduce(parts[0]) { $0.union($1) }
    }

    /// The figure fitted into `rect`, standing on its bottom edge.
    static func path(build: CGFloat, female: Bool, in rect: CGRect) -> Path {
        let scale = min(rect.width / grid.width, rect.height / grid.height)
        let x = rect.midX - grid.width * scale / 2
        let y = rect.maxY - grid.height * scale
        return outline(build: build, female: female).applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }

    /// A closed Catmull-Rom curve through the points, as cubic Béziers.
    private static func smoothLoop(through points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        func point(_ index: Int) -> CGPoint { points[(index + count) % count] }
        path.move(to: points[0])
        for index in 0..<count {
            let before = point(index - 1), from = point(index), to = point(index + 1), after = point(index + 2)
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + (to.x - before.x) / 6, y: from.y + (to.y - before.y) / 6),
                control2: CGPoint(x: to.x - (after.x - from.x) / 6, y: to.y - (after.y - from.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }

    /// A limb through its joints, each with its width: tapered pieces between them, rounded at
    /// every joint.
    private static func limb(_ joints: [(point: CGPoint, width: CGFloat)]) -> [Path] {
        var pieces: [Path] = []
        for (start, end) in zip(joints, joints.dropFirst()) {
            let angle = atan2(end.point.y - start.point.y, end.point.x - start.point.x)
            let normal = CGPoint(x: -sin(angle), y: cos(angle))
            var piece = Path()
            piece.move(to: CGPoint(x: start.point.x + normal.x * start.width / 2, y: start.point.y + normal.y * start.width / 2))
            piece.addLine(to: CGPoint(x: end.point.x + normal.x * end.width / 2, y: end.point.y + normal.y * end.width / 2))
            piece.addLine(to: CGPoint(x: end.point.x - normal.x * end.width / 2, y: end.point.y - normal.y * end.width / 2))
            piece.addLine(to: CGPoint(x: start.point.x - normal.x * start.width / 2, y: start.point.y - normal.y * start.width / 2))
            piece.closeSubpath()
            pieces.append(piece)
        }
        for joint in joints {
            pieces.append(Path(ellipseIn: CGRect(x: joint.point.x - joint.width / 2, y: joint.point.y - joint.width / 2, width: joint.width, height: joint.width)))
        }
        return pieces
    }
}

/// The figure as a shape, so a change of build animates.
struct BodyFigureShape: Shape {
    var build: CGFloat
    var female = false

    var animatableData: CGFloat {
        get { build }
        set { build = newValue }
    }

    func path(in rect: CGRect) -> Path {
        BodyFigure.path(build: build, female: female, in: rect)
    }
}
