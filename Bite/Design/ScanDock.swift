import SwiftUI

/// The floating dock at the bottom of Today: search on the left, the scan shutter raised in
/// the middle, quick add on the right. The shutter is the one thing on the screen that moves.
struct ScanDock: View {
    let namespace: Namespace.ID
    let onSearch: () -> Void
    let onScan: () -> Void
    let onQuickAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            DockButton(systemImage: "magnifyingglass", title: "Search", action: onSearch)
            ShutterButton(action: onScan)
                .zoomSource(id: "scan", in: namespace)
                .offset(y: -14)
                .frame(width: 92)
            DockButton(systemImage: "plus", title: "Quick add", action: onQuickAdd)
        }
        .frame(height: 62)
        .floatingGlass(in: Capsule())
        .padding(.horizontal, 40)
    }
}

private struct DockButton: View {
    let systemImage: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .regular))
                Text(title)
                    .font(.ui(12, .medium))
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

/// The big round scan button: a live barcode with a laser sweeping across it.
struct ShutterButton: View {
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            // The page-colored ring cuts the shutter out of the dock, so it needs no shadow.
            ScanGlyph(color: Theme.page)
                .frame(width: 30, height: 26)
                .frame(width: 66, height: 66)
                .background(Theme.ink, in: Circle())
                .padding(5)
                .background(Theme.page, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
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
            ZStack {
                ScanCorners()
                    .stroke(color, style: StrokeStyle(lineWidth: max(1.6, size.width * 0.07), lineCap: .round, lineJoin: .round))
                HStack(spacing: size.width * 0.045) {
                    ForEach(Self.bars.indices, id: \.self) { index in
                        Rectangle()
                            .fill(color)
                            .frame(width: Self.bars[index] * size.width * 0.04)
                    }
                }
                .padding(.horizontal, size.width * 0.2)
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
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = true }
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

/// "Added to Breakfast": slides up over the dock when something lands in today, then leaves.
struct AddedToast: View {
    let added: LogEvents.Added

    var body: some View {
        HStack(spacing: 10) {
            FoodThumb(food: added.food, size: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text("Added to \(added.meal.title)")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(added.food.name)
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "+\(added.kcal.kcalText)")
                    .font(.number(17))
                    .foregroundStyle(Theme.ink)
                Text("kcal")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .floatingGlass(in: Capsule())
        .padding(.horizontal, Theme.margin)
        .accessibilityElement(children: .combine)
    }
}
