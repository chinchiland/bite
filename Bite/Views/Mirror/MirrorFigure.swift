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
    static let ankleY: CGFloat = 244

    private static let outline: Path = {
        let parts = [
            Path(ellipseIn: CGRect(x: 37, y: 4, width: 26, height: 31)),
            Path(roundedRect: CGRect(x: 44, y: 28, width: 12, height: 22), cornerRadius: 4),
            Path(roundedRect: CGRect(x: 26, y: 44, width: 48, height: 62), cornerRadius: 16),
            Path(roundedRect: CGRect(x: 31, y: 94, width: 38, height: 48), cornerRadius: 13),
            limb(from: CGPoint(x: 29, y: 54), to: CGPoint(x: 19, y: 140), width: 11),
            limb(from: CGPoint(x: 71, y: 54), to: CGPoint(x: 81, y: 140), width: 11),
            limb(from: CGPoint(x: 41, y: 128), to: CGPoint(x: 37, y: 244), width: 16),
            limb(from: CGPoint(x: 59, y: 128), to: CGPoint(x: 63, y: 244), width: 16),
            Path(ellipseIn: CGRect(x: 26, y: 240, width: 18, height: 10)),
            Path(ellipseIn: CGRect(x: 56, y: 240, width: 18, height: 10)),
        ]
        return parts.dropFirst().reduce(parts[0]) { $0.union($1) }
    }()

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
