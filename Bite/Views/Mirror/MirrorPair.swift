import SwiftUI

/// Two photos in one frame: your first on the left of a line you drag, the other on the right,
/// lined up at the shoulders and the torso's height so what changed is you, not where the phone
/// was. How long between them on top, the two weighings under it. No arrow, no percentage, no
/// color, and no share: for a body, no direction is news.
struct MirrorPair: View {
    let older: MirrorShot
    let newer: MirrorShot

    @AppStorage("mirror.longGap") private var longGapShown = false
    @State private var split = 0.5
    @State private var drawn = true
    @State private var atEnd = 0

    private var gap: MirrorGap { MirrorGap.between(older.takenAt, newer.takenAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MirrorGapText(gap: gap)
                    .font(.number(34, .medium))
                    .numberTracking(34)
                    .foregroundStyle(Theme.ink)
                    .opacity(drawn ? 1 : 0)
                    .offset(y: drawn ? 0 : 8)

                frame
                    .padding(.top, 14)

                if let from = older.weightKg, let to = newer.weightKg {
                    Text("From \(from.weightText) to \(to.weightText)")
                        .font(.ui(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page.ignoresSafeArea())
        .modifier(MirrorPrivacy())
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(Feel.tick, trigger: atEnd)
        .onAppear {
            // The one celebration in your mirror: the first time two photos are eight weeks
            // apart, the time between them draws itself in, once. No haptic: a body is not a goal.
            guard gap.isLong, !longGapShown else { return }
            longGapShown = true
            drawn = false
            withAnimation(Motion.reveal.delay(0.2)) { drawn = true }
        }
    }

    private var frame: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let align = MirrorAlign.make(
                older: older.placement?.filling(photoAspect: older.aspect, frameAspect: 0.75),
                newer: newer.placement?.filling(photoAspect: newer.aspect, frameAspect: 0.75)
            )
            ZStack(alignment: .topLeading) {
                MirrorPhoto(id: newer.photoID, thumbnail: false, maxPixel: 1400)
                    .modifier(MirrorMove(align: align, moves: align.movesNewer, size: size))
                MirrorPhoto(id: older.photoID, thumbnail: false, maxPixel: 1400)
                    .modifier(MirrorMove(align: align, moves: !align.movesNewer, size: size))
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * split)
                    }
                divider(in: size)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let next = min(max(value.location.x / max(size.width, 1), 0.02), 0.98)
                        let wasEnd = split <= 0.02 || split >= 0.98
                        split = next
                        let isEnd = next <= 0.02 || next >= 0.98
                        if isEnd && !wasEnd { atEnd += 1 }
                    }
            )
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.edge, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your photos from \(older.takenAt.formatted(date: .long, time: .omitted)) and \(newer.takenAt.formatted(date: .long, time: .omitted))"))
        .accessibilityValue(Text(split.formatted(.percent.precision(.fractionLength(0)))))
        .accessibilityHint("Drag to compare")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(split + 0.1, 0.98)
            case .decrement: split = max(split - 0.1, 0.02)
            @unknown default: break
            }
        }
    }

    /// One photo of the pair in the frame: moved into line when it is the one that moves.
    private struct MirrorMove: ViewModifier {
        let align: MirrorAlign
        let moves: Bool
        let size: CGSize

        func body(content: Content) -> some View {
            content
                .frame(width: size.width, height: size.height)
                .scaleEffect(moves ? align.scale : 1, anchor: UnitPoint(x: align.anchorX, y: align.anchorY))
                .offset(x: moves ? align.dx * size.width : 0, y: moves ? align.dy * size.height : 0)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    /// The line between the two, and the grip to drag it by.
    private func divider(in size: CGSize) -> some View {
        let x = size.width * split
        return ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: size.height)
            Image(systemName: "chevron.left.chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .coverGlass(in: Circle(), onPhoto: true)
        }
        .position(x: x, y: size.height / 2)
        .allowsHitTesting(false)
    }
}
