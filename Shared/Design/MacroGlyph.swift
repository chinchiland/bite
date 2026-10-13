import SwiftUI

/// The three macro glyphs, drawn on a 24 point grid the way SF Symbols are: a drumstick for
/// protein, a wheat ear for carbs, half an avocado for fat. Foods people know at a glance, so a
/// glyph says its macro before its name or its color does. Filled shapes, so they hold at 12
/// points on the ring and at 18 in a list.
enum MacroGlyph {
    struct Layer {
        let path: Path
        /// The avocado's flesh sits a step lighter than its skin and stone.
        var opacity: Double = 1
        var evenOdd = false
    }

    static func layers(_ macro: Macro) -> [Layer] {
        switch macro {
        case .protein: drumstick
        case .carbs: wheat
        case .fat: avocado
        }
    }

    /// Draws a glyph into a square of the context.
    static func draw(_ macro: Macro, in context: inout GraphicsContext, rect: CGRect, color: Color) {
        let scale = rect.width / 24
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        for layer in layers(macro) {
            context.fill(
                layer.path.applying(transform),
                with: .color(color.opacity(layer.opacity)),
                style: FillStyle(eoFill: layer.evenOdd)
            )
        }
    }

    // Each part is its own layer, so overlapping parts never cancel each other out.

    private static let drumstick: [Layer] = [
        Layer(path: ellipse(x: 14.6, y: 9.4, rx: 6.6, ry: 5.4, degrees: -45)),
        Layer(path: Path { path in
            path.move(to: CGPoint(x: 8.6, y: 13.6))
            path.addLine(to: CGPoint(x: 10.4, y: 15.4))
            path.addLine(to: CGPoint(x: 7.1, y: 18.7))
            path.addLine(to: CGPoint(x: 5.3, y: 16.9))
            path.closeSubpath()
        }),
        Layer(path: Path(ellipseIn: CGRect(x: 2.6, y: 15.6, width: 4, height: 4))),
        Layer(path: Path(ellipseIn: CGRect(x: 4.4, y: 17.4, width: 4, height: 4))),
    ]

    /// An upright ear: tapered kernels angled up a sturdy stem, like an almond on each side.
    private static let wheat: [Layer] = {
        var layers = [
            Layer(path: Path(roundedRect: CGRect(x: 11.15, y: 9.5, width: 1.7, height: 13.1), cornerRadius: 0.85)),
            Layer(path: kernel(x: 12, y: 3.9, degrees: 0)),
        ]
        for y in [8.4, 12.7, 17] as [CGFloat] {
            layers.append(Layer(path: kernel(x: 9.2, y: y, degrees: -30)))
            layers.append(Layer(path: kernel(x: 14.8, y: y, degrees: 30)))
        }
        return layers
    }()

    /// Half an avocado: skin and stone at full strength, the flesh between them at half.
    private static let avocado: [Layer] = {
        let skin = closedCurve(from: CGPoint(x: 12, y: 1.6), [
            [15.2, 1.6, 16.6, 4.6, 17.3, 7.4],
            [17.8, 9.5, 20.4, 11.6, 20.4, 15.4],
            [20.4, 19.7, 16.7, 22.6, 12, 22.6],
            [7.3, 22.6, 3.6, 19.7, 3.6, 15.4],
            [3.6, 11.6, 6.2, 9.5, 6.7, 7.4],
            [7.4, 4.6, 8.8, 1.6, 12, 1.6],
        ])
        let flesh = closedCurve(from: CGPoint(x: 12, y: 4.3), [
            [13.9, 4.3, 14.7, 6.4, 15.2, 8.4],
            [15.7, 10.5, 18, 12.4, 18, 15.4],
            [18, 18.4, 15.4, 20.2, 12, 20.2],
            [8.6, 20.2, 6, 18.4, 6, 15.4],
            [6, 12.4, 8.3, 10.5, 8.8, 8.4],
            [9.3, 6.4, 10.1, 4.3, 12, 4.3],
        ])
        let stone = Path(ellipseIn: CGRect(x: 7.5, y: 10.7, width: 9, height: 9))
        var whole = skin
        whole.addPath(flesh)
        whole.addPath(stone)
        var lighter = flesh
        lighter.addPath(stone)
        return [Layer(path: whole, evenOdd: true), Layer(path: lighter, opacity: 0.5, evenOdd: true)]
    }()

    /// One wheat kernel, pointed at the tip, drawn around its center and turned outward.
    private static func kernel(x: CGFloat, y: CGFloat, degrees: CGFloat) -> Path {
        let almond = closedCurve(from: CGPoint(x: 0, y: -3.9), [
            [2.15, -2.3, 2.25, 1.4, 0, 3.3],
            [-2.25, 1.4, -2.15, -2.3, 0, -3.9],
        ])
        return almond.applying(CGAffineTransform(translationX: x, y: y).rotated(by: degrees * .pi / 180))
    }

    private static func ellipse(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, degrees: CGFloat) -> Path {
        let oval = Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
        guard degrees != 0 else { return oval }
        let turn = CGAffineTransform(translationX: x, y: y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -x, y: -y)
        return oval.applying(turn)
    }

    /// A closed shape of cubic curves, each given as control 1, control 2 and end point.
    private static func closedCurve(from start: CGPoint, _ curves: [[CGFloat]]) -> Path {
        Path { path in
            path.move(to: start)
            for c in curves {
                path.addCurve(
                    to: CGPoint(x: c[4], y: c[5]),
                    control1: CGPoint(x: c[0], y: c[1]),
                    control2: CGPoint(x: c[2], y: c[3])
                )
            }
            path.closeSubpath()
        }
    }
}

/// A macro's glyph on its tile, the way iOS Settings leads a row: the macro's color as a soft
/// fill, the glyph a step deeper so it reads, filling about three quarters of the tile.
struct MacroTile: View {
    let macro: Macro
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvas in
            let side = canvas.width * 0.76
            let rect = CGRect(x: (canvas.width - side) / 2, y: (canvas.height - side) / 2, width: side, height: side)
            MacroGlyph.draw(macro, in: &context, rect: rect, color: macro.glyphColor)
        }
        .frame(width: size, height: size)
        .background(macro.tileFill, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}
