import SwiftUI

/// A standing figure whose build follows a BMI: shoulders, waist, belly, hips and limbs fill
/// out above 22 and slim below it, while the head and the height never change. Drawn in the
/// same hand as your mirror's figure, from rounded parts joined into one outline, so it is
/// never a photo and never anyone in particular.
enum BodyFigure {
    static let grid = CGSize(width: 120, height: 260)

    /// 1 at a BMI of 22. A body's girth at one height grows with the square root of its BMI.
    static func build(bmi: Double) -> CGFloat {
        CGFloat(min(max((bmi / 22).squareRoot(), 0.85), 1.7))
    }

    static func outline(build: CGFloat) -> Path {
        let cx: CGFloat = 60
        let gain = build - 1
        // Fat goes on the middle first, the frame a little, the limbs in between.
        let shoulder = 21 * (1 + gain * 0.55)
        let waist = 15 * build
        let belly = 16.5 * build
        let hip = 18 * (1 + gain * 0.9)
        let limb = 1 + gain * 0.8

        var torso = Path()
        torso.move(to: CGPoint(x: cx - 5, y: 44))
        torso.addQuadCurve(to: CGPoint(x: cx - shoulder, y: 53), control: CGPoint(x: cx - shoulder + 3, y: 43))
        torso.addQuadCurve(to: CGPoint(x: cx - waist, y: 96), control: CGPoint(x: cx - shoulder - 1, y: 76))
        torso.addQuadCurve(to: CGPoint(x: cx - hip, y: 128), control: CGPoint(x: cx - belly - 1, y: 112))
        torso.addQuadCurve(to: CGPoint(x: cx, y: 138), control: CGPoint(x: cx - hip, y: 138))
        torso.addQuadCurve(to: CGPoint(x: cx + hip, y: 128), control: CGPoint(x: cx + hip, y: 138))
        torso.addQuadCurve(to: CGPoint(x: cx + waist, y: 96), control: CGPoint(x: cx + belly + 1, y: 112))
        torso.addQuadCurve(to: CGPoint(x: cx + shoulder, y: 53), control: CGPoint(x: cx + shoulder + 1, y: 76))
        torso.addQuadCurve(to: CGPoint(x: cx + 5, y: 44), control: CGPoint(x: cx + shoulder - 3, y: 43))
        torso.closeSubpath()

        // Arms hang a little further out as the middle grows, so they never melt into it.
        let armTop = shoulder - 2
        let armBottom = shoulder + 8 + gain * 14
        let thigh = 9 * (1 + gain * 0.8)
        let ankle = 11 + gain * 3
        var parts = [
            Path(ellipseIn: CGRect(x: cx - 12.5, y: 4, width: 25, height: 30)),
            Path(roundedRect: CGRect(x: cx - 5, y: 28, width: 10, height: 20), cornerRadius: 3),
            torso,
        ]
        for side: CGFloat in [-1, 1] {
            parts.append(limb(from: CGPoint(x: cx + side * armTop, y: 56), to: CGPoint(x: cx + side * armBottom, y: 138), width: 10 * limb))
            parts.append(limb(from: CGPoint(x: cx + side * thigh, y: 126), to: CGPoint(x: cx + side * ankle, y: 243), width: 15 * limb))
            parts.append(Path(ellipseIn: CGRect(x: cx + side * (ankle + 2) - 8, y: 238, width: 16, height: 9)))
        }
        return parts.dropFirst().reduce(parts[0]) { $0.union($1) }
    }

    /// The figure fitted into `rect`, standing on its bottom edge.
    static func path(build: CGFloat, in rect: CGRect) -> Path {
        let scale = min(rect.width / grid.width, rect.height / grid.height)
        let x = rect.midX - grid.width * scale / 2
        let y = rect.maxY - grid.height * scale
        return outline(build: build).applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }

    private static func limb(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x) - .pi / 2
        let capsule = Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: width / 2)
        return capsule.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: start.x, y: start.y)))
    }
}

/// The figure as a shape, so a change of build animates.
struct BodyFigureShape: Shape {
    var build: CGFloat

    var animatableData: CGFloat {
        get { build }
        set { build = newValue }
    }

    func path(in rect: CGRect) -> Path {
        BodyFigure.path(build: build, in: rect)
    }
}
