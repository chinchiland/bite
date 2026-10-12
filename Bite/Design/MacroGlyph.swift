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

    private static let wheat: [Layer] = {
        var layers = [
            Layer(path: Path(roundedRect: CGRect(x: 11.3, y: 6, width: 1.4, height: 16), cornerRadius: 0.7)),
            Layer(path: ellipse(x: 12, y: 4.6, rx: 1.6, ry: 2.6, degrees: 0)),
        ]
        for y in [8.6, 12.8, 17] as [CGFloat] {
            layers.append(Layer(path: ellipse(x: 9.4, y: y, rx: 1.5, ry: 2.7, degrees: -38)))
            layers.append(Layer(path: ellipse(x: 14.6, y: y, rx: 1.5, ry: 2.7, degrees: 38)))
        }
        return layers
    }()

    private static let avocado: [Layer] = {
        let skin = closedCurve(from: CGPoint(x: 12, y: 2.2), [
            [15.4, 2.2, 17, 5.4, 17.7, 8.2],
            [18.2, 10.2, 19.9, 12, 19.9, 15],
            [19.9, 19, 16.5, 21.8, 12, 21.8],
            [7.5, 21.8, 4.1, 19, 4.1, 15],
            [4.1, 12, 5.8, 10.2, 6.3, 8.2],
            [7, 5.4, 8.6, 2.2, 12, 2.2],
        ])
        let flesh = closedCurve(from: CGPoint(x: 12, y: 5.1), [
            [13.8, 5.1, 14.6, 7.1, 15.1, 9.1],
            [15.6, 11.1, 17, 12.7, 17, 15],
            [17, 17.5, 14.9, 19, 12, 19],
            [9.1, 19, 7, 17.5, 7, 15],
            [7, 12.7, 8.4, 11.1, 8.9, 9.1],
            [9.4, 7.1, 10.2, 5.1, 12, 5.1],
        ])
        let stone = Path(ellipseIn: CGRect(x: 8, y: 10.8, width: 8, height: 8))
        var whole = skin
        whole.addPath(flesh)
        whole.addPath(stone)
        var lighter = flesh
        lighter.addPath(stone)
        // Skin and stone at full strength; the flesh between them, lighter.
        return [Layer(path: whole, evenOdd: true), Layer(path: lighter, opacity: 0.34, evenOdd: true)]
    }()

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
/// fill, the glyph a step deeper so it reads.
struct MacroTile: View {
    let macro: Macro
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvas in
            let side = canvas.width * 0.64
            let rect = CGRect(x: (canvas.width - side) / 2, y: (canvas.height - side) / 2, width: side, height: side)
            MacroGlyph.draw(macro, in: &context, rect: rect, color: macro.glyphColor)
        }
        .frame(width: size, height: size)
        .background(macro.tileFill, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}
