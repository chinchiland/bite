import SwiftUI
import WidgetKit

/// The day's dotted ring, still, for a widget: fewer rings than the app's so the dots stay
/// round at widget size. The lit dots are their own layer, so on a tinted or clear Home Screen
/// they take the accent while the dots still to eat stay quiet.
struct WidgetRing: View {
    let snapshot: WidgetSnapshot
    var rings = 4

    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        ZStack {
            RingDots(snapshot: snapshot, rings: rings, lit: false, fullColor: mode == .fullColor)
            RingDots(snapshot: snapshot, rings: rings, lit: true, fullColor: mode == .fullColor)
                .widgetAccentable()
        }
        .accessibilityHidden(true)
    }
}

private struct RingDots: View {
    let snapshot: WidgetSnapshot
    let rings: Int
    let lit: Bool
    let fullColor: Bool

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 176
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = snapshot.ring
            let parts: [(share: Double, color: Color)] = [
                (ring.protein, Theme.protein), (ring.carbs, Theme.carbs), (ring.fat, Theme.fat),
            ]
            let litShare = parts.reduce(0) { $0 + $1.share }
            let diameter = 5.4 * unit
            // The outer ring sits where the app's does; the inner ones step in from it.
            let outer = 82.5
            for index in 0..<rings {
                let radius = (outer - 7.2 * Double(rings - 1 - index)) * unit
                let count = max(Int((2 * .pi * radius / (8.4 * unit)).rounded()), 12)
                let isOuter = index == rings - 1
                for dot in 0..<count {
                    let position = Double(dot) / Double(count)
                    var color: Color?
                    if position < litShare {
                        var start = 0.0
                        for part in parts where part.share > 0 {
                            if position < start + part.share {
                                color = part.color
                                break
                            }
                            start += part.share
                        }
                    }
                    if isOuter, ring.overflow > 0, position < ring.overflow { color = Theme.over }
                    guard (color != nil) == lit else { continue }
                    let fill: Color
                    if lit {
                        fill = fullColor ? (color ?? Theme.ink) : .primary
                    } else {
                        fill = fullColor ? Theme.ringRest : Color.primary.opacity(0.22)
                    }
                    let angle = position * 2 * .pi - .pi / 2
                    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(fill))
                }
            }
        }
    }
}

/// The number a widget leads with, and the words under it: left, over, or eaten.
struct HeadlineNumber: View {
    let snapshot: WidgetSnapshot
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: -2) {
            Text(snapshot.headline.kcalText)
                .font(.number(snapshot.headline >= 1000 ? size * 0.82 : size, .medium))
                .numberTracking(size)
                .foregroundStyle(snapshot.isOver ? Theme.over : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: snapshot.headline))
            Text(unit)
                .font(.ui(11))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }

    private var unit: LocalizedStringKey {
        switch snapshot.headlineKind {
        case .left: "kcal left"
        case .over: "kcal over"
        case .eaten: "kcal eaten"
        }
    }
}

/// A macro's glyph on its tint, as in the app's lists.
struct GlyphTile: View {
    let macro: Macro
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, canvas in
            let inset = canvas.width * 0.12
            MacroGlyph.draw(macro, in: &context, rect: CGRect(x: inset, y: inset, width: canvas.width - 2 * inset, height: canvas.height - 2 * inset), color: macro.glyphColor)
        }
        .frame(width: size, height: size)
        .background(macro.tileFill, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A food as a tile: its photo, or its emoji on its tint.
struct FoodTile: View {
    let emoji: String?
    let tint: FoodTint
    let photo: UIImage?
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.tint(tint)
                Text(verbatim: emoji ?? "🍽️")
                    .font(.system(size: size * 0.46))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Before Bite has been opened once, or in a copy without the shared log.
struct OpenBiteOnce: View {
    var body: some View {
        Text("Open Bite once to see your day here.")
            .font(.ui(13))
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
