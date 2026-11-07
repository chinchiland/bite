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
        // Weight goes on the middle first: past a BMI of 25 the belly leads, below 22 the waist
        // shows. The frame moves a little, the tops of the limbs more than their ends.
        let shoulder = 21 * (1 + gain * 0.5)
        let waist = 14.5 * pow(build, 1.5)
        let belly = 16 * pow(build, 1.9)
        let hip = 18 * (1 + gain * 1.1)

        var torso = Path()
        torso.move(to: CGPoint(x: cx - 5, y: 44))
        torso.addQuadCurve(to: CGPoint(x: cx - shoulder, y: 53), control: CGPoint(x: cx - shoulder + 3, y: 43))
        torso.addQuadCurve(to: CGPoint(x: cx - waist, y: 94), control: CGPoint(x: cx - shoulder - 1, y: 74))
        torso.addQuadCurve(to: CGPoint(x: cx - hip, y: 128), control: CGPoint(x: cx - belly - 1.5, y: 108))
        torso.addQuadCurve(to: CGPoint(x: cx, y: 139), control: CGPoint(x: cx - hip, y: 139))
        torso.addQuadCurve(to: CGPoint(x: cx + hip, y: 128), control: CGPoint(x: cx + hip, y: 139))
        torso.addQuadCurve(to: CGPoint(x: cx + waist, y: 94), control: CGPoint(x: cx + belly + 1.5, y: 108))
        torso.addQuadCurve(to: CGPoint(x: cx + shoulder, y: 53), control: CGPoint(x: cx + shoulder + 1, y: 74))
        torso.addQuadCurve(to: CGPoint(x: cx + 5, y: 44), control: CGPoint(x: cx + shoulder - 3, y: 43))
        torso.closeSubpath()

        // The arms hang clear of the belly, however round it gets.
        let armTop = shoulder - 2.5
        let armBottom = max(shoulder + 8, belly + 9) + gain * 4
        let thigh = 9.5 * (1 + gain * 0.9)
        let ankle = 10 + gain * 4
        var parts = [
            Path(ellipseIn: CGRect(x: cx - 12.5, y: 4, width: 25, height: 30)),
            Path(roundedRect: CGRect(x: cx - 5, y: 28, width: 10, height: 20), cornerRadius: 3),
            torso,
        ]
        for side: CGFloat in [-1, 1] {
            parts.append(limb(
                from: CGPoint(x: cx + side * armTop, y: 57), to: CGPoint(x: cx + side * armBottom, y: 138),
                startWidth: 11 * (1 + gain * 1.1), endWidth: 8 * (1 + gain * 0.5)
            ))
            parts.append(limb(
                from: CGPoint(x: cx + side * thigh, y: 128), to: CGPoint(x: cx + side * ankle, y: 242),
                startWidth: 17 * (1 + gain * 1.3), endWidth: 10 * (1 + gain * 0.5)
            ))
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

    /// A limb from one joint to the next, wider at the top than at the end, rounded at both.
    private static func limb(from start: CGPoint, to end: CGPoint, startWidth: CGFloat, endWidth: CGFloat) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        var body = Path()
        body.move(to: CGPoint(x: start.x + normal.x * startWidth / 2, y: start.y + normal.y * startWidth / 2))
        body.addLine(to: CGPoint(x: end.x + normal.x * endWidth / 2, y: end.y + normal.y * endWidth / 2))
        body.addLine(to: CGPoint(x: end.x - normal.x * endWidth / 2, y: end.y - normal.y * endWidth / 2))
        body.addLine(to: CGPoint(x: start.x - normal.x * startWidth / 2, y: start.y - normal.y * startWidth / 2))
        body.closeSubpath()
        let top = Path(ellipseIn: CGRect(x: start.x - startWidth / 2, y: start.y - startWidth / 2, width: startWidth, height: startWidth))
        let foot = Path(ellipseIn: CGRect(x: end.x - endWidth / 2, y: end.y - endWidth / 2, width: endWidth, height: endWidth))
        return body.union(top).union(foot)
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
