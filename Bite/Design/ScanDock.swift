import SwiftUI

/// The floating dock at the bottom of home: search on the left, the ink Scan capsule in the
/// middle with its laser sweeping, quick add on the right.
struct ScanDock: View {
    let namespace: Namespace.ID
    let onSearch: () -> Void
    let onScan: () -> Void
    let onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            DockButton(systemImage: "magnifyingglass", label: "Search", action: onSearch)
            ScanCapsule(action: onScan)
                .zoomSource(id: "scan", in: namespace)
            DockButton(systemImage: "plus", label: "Quick add", action: onQuickAdd)
        }
        .padding(.horizontal, 7)
        .frame(height: 62)
        .floatingGlass(in: Capsule())
        .padding(.horizontal, 40)
    }
}

private struct DockButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
    }
}

/// The main way in: an ink capsule with a live barcode and its red laser, and the word Scan.
private struct ScanCapsule: View {
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            HStack(spacing: 10) {
                ScanGlyph(color: Theme.page)
                    .frame(width: 26, height: 22)
                Text("Scan")
                    .font(.ui(16, .semibold))
                    .foregroundStyle(Theme.page)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(Theme.ink, in: Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel("Scan food")
        .accessibilityHint("Opens the camera to scan a barcode or a plate")
    }
}

/// A barcode in viewfinder corners, with a red laser sliding up and down over it.
struct ScanGlyph: View {
    var color: Color = Theme.ink
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private static let bars: [CGFloat] = [1.6, 0.8, 2.4, 1, 0.8, 2, 1.2, 0.8, 2.2, 1]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The bars and their gaps share the middle 60% of the width, so the glyph never
            // grows past its frame however small it is drawn.
            let gap: CGFloat = 0.9
            let unit = size.width * 0.6 / (Self.bars.reduce(0, +) + gap * CGFloat(Self.bars.count - 1))
            ZStack {
                ScanCorners()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.6, size.width * 0.07), lineCap: .round, lineJoin: .round))
                HStack(spacing: unit * gap) {
                    ForEach(Self.bars.indices, id: \.self) { index in
                        Rectangle()
                            .fill(color)
                            .frame(width: Self.bars[index] * unit)
                    }
                }
                .padding(.vertical, size.height * 0.26)
                Capsule()
                    .fill(Theme.laser)
                    .frame(height: max(1.6, size.height * 0.07))
                    .padding(.horizontal, size.width * 0.08)
                    .shadow(color: Theme.laser.opacity(0.9), radius: 3)
                    .offset(y: sweep ? size.height * 0.3 : -size.height * 0.3)
            }
        }
        .onAppear {
            guard animated, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatCount(3, autoreverses: true)) { sweep = true }
        }
        .accessibilityHidden(true)
    }
}

/// Four rounded corner brackets, the universal sign for "aim here".
struct ScanCorners: Shape {
    var length: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        let horizontal = rect.width * length
        let vertical = rect.height * length
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + vertical))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + horizontal, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - horizontal, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + vertical))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - vertical))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - horizontal, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + horizontal, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - vertical))
        return path
    }
}

/// "Added to Breakfast" or "Deleted": slides up over the dock after a change to the day, with
/// Undo, then leaves on its own.
struct EventToast: View {
    let event: LogEvents.Event
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FoodThumb(food: event.food, size: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(verbatim: "\(name) · \(event.kcal.kcalText) kcal")
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("Undo")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.fill, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .floatingGlass(in: Capsule())
        .padding(.horizontal, Theme.margin)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Undo"), onUndo)
    }

    private var title: String {
        switch event.change {
        case .added: String(localized: "Added to \(event.meal.title)")
        case .deleted: String(localized: "Deleted")
        }
    }

    private var name: String {
        event.count > 1 ? String(localized: "\(event.count) foods") : event.food.name
    }
}
