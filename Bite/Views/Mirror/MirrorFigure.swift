import SwiftUI

/// A standing figure, arms a little away from the sides and feet apart: the pose for a photo.
/// Drawn from simple rounded parts on a 100 by 260 grid and joined into one outline, the way
/// the macro glyphs are drawn, so it is the same hand as the drumstick and the wheat ear, and
/// never a photo of anyone.
enum MirrorFigure {
    static let grid = CGSize(width: 100, height: 260)
    /// Where the shoulders, hips and ankles sit on the grid, for lining the figure up.
    static let shoulderY: CGFloat = 52
    static let hipY: CGFloat = 132
    static let ankleY: CGFloat = 240

    private static let outline: Path = {
        let parts = [
            Path(ellipseIn: CGRect(x: 37.5, y: 4, width: 25, height: 30)),
            Path(roundedRect: CGRect(x: 45, y: 28, width: 10, height: 20), cornerRadius: 3),
            torso,
            limb(from: CGPoint(x: 30, y: 56), to: CGPoint(x: 20, y: 138), width: 10),
            limb(from: CGPoint(x: 70, y: 56), to: CGPoint(x: 80, y: 138), width: 10),
            limb(from: CGPoint(x: 41, y: 126), to: CGPoint(x: 39, y: 243), width: 15),
            limb(from: CGPoint(x: 59, y: 126), to: CGPoint(x: 61, y: 243), width: 15),
            Path(ellipseIn: CGRect(x: 29, y: 238, width: 16, height: 9)),
            Path(ellipseIn: CGRect(x: 55, y: 238, width: 16, height: 9)),
        ]
        return parts.dropFirst().reduce(parts[0]) { $0.union($1) }
    }()

    /// Rounded shoulders down to the waist, a little out to the hips: one smooth piece, so the
    /// outline never steps where parts meet.
    private static let torso = Path { path in
        path.move(to: CGPoint(x: 45, y: 44))
        path.addQuadCurve(to: CGPoint(x: 28, y: 52), control: CGPoint(x: 32, y: 43))
        path.addQuadCurve(to: CGPoint(x: 33, y: 104), control: CGPoint(x: 27, y: 80))
        path.addQuadCurve(to: CGPoint(x: 31, y: 132), control: CGPoint(x: 34, y: 118))
        path.addQuadCurve(to: CGPoint(x: 50, y: 138), control: CGPoint(x: 33, y: 138))
        path.addQuadCurve(to: CGPoint(x: 69, y: 132), control: CGPoint(x: 67, y: 138))
        path.addQuadCurve(to: CGPoint(x: 67, y: 104), control: CGPoint(x: 66, y: 118))
        path.addQuadCurve(to: CGPoint(x: 72, y: 52), control: CGPoint(x: 73, y: 80))
        path.addQuadCurve(to: CGPoint(x: 55, y: 44), control: CGPoint(x: 68, y: 43))
        path.closeSubpath()
    }

    /// The figure fitted into `rect`, centered.
    static func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / grid.width, rect.height / grid.height)
        let x = rect.midX - grid.width * scale / 2
        let y = rect.midY - grid.height * scale / 2
        return outline.applying(CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }

    /// A rounded limb from one joint to the next.
    private static func limb(from start: CGPoint, to end: CGPoint, width: CGFloat) -> Path {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x) - .pi / 2
        let capsule = Path(roundedRect: CGRect(x: -width / 2, y: 0, width: width, height: length), cornerRadius: width / 2)
        return capsule.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: start.x, y: start.y)))
    }
}

/// The figure as a fine line, for the camera's first photo, the promise and the empty mirror.
struct MirrorFigureShape: Shape {
    func path(in rect: CGRect) -> Path {
        MirrorFigure.path(in: rect)
    }
}
