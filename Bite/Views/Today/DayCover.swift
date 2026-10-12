import SwiftUI
import UIKit

/// One photo the cover can show: a meal of the day, what it was and where.
struct CoverPhoto: Identifiable, Equatable {
    let id: AnyHashable
    let image: UIImage
    let dish: String
    let place: MealPlace?

    static func == (a: CoverPhoto, b: CoverPhoto) -> Bool { a.id == b.id }
}

/// The top of a day: the day's meal photos (a fresh gradient until the first one), the latest
/// first, melting into the page so the number that matters sits in ink right under the food.
/// Tap or swipe for the next photo. The day's controls float above.
struct DayCover<Controls: View>: View {
    let photos: [CoverPhoto]
    @Binding var index: Int
    let height: CGFloat
    let topInset: CGFloat
    let number: Double
    /// Already in the reader's language: "kcal left today".
    let unit: String
    /// A past day's verdict ("On target"), shown when the photo has no place.
    var verdict: String? = nil
    /// With no photo: the last thing you ate.
    var lastMeal: String? = nil
    let detail: String
    /// The detail turns red: a day past its goal.
    var detailIsOver = false
    let onPlace: (MealPlace) -> Void
    @ViewBuilder let controls: Controls

    private var current: CoverPhoto? {
        photos.indices.contains(index) ? photos[index] : photos.first
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                // Pulling down past the top stretches the cover instead of opening a gap.
                .visualEffect { content, proxy in
                    let pull = max(proxy.frame(in: .scrollView).minY, 0)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
                }
            hero
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            controls
                .padding(.top, topInset + 2)
                .padding(.horizontal, 16)
        }
        .sensoryFeedback(.selection, trigger: index)
    }

    @ViewBuilder private var backdrop: some View {
        if photos.isEmpty {
            Theme.coverGradient
                .overlay { melt(shade: false) }
                .accessibilityHidden(true)
        } else {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    page(photo)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityHidden(true)
        }
    }

    /// A photo filling the cover, clear down to the number, then softening into the page.
    private func page(_ photo: CoverPhoto) -> some View {
        Color.clear
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                // The same photo blurred, showing only where it melts, so the food turns to
                // color before it turns to paper.
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18, opaque: true)
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0.5), .init(color: .black, location: 0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .overlay { melt(shade: true) }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { advance() }
    }

    /// A soft shade at the head for the controls, clear over the food, paper at the foot.
    private func melt(shade: Bool) -> some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(shade ? 0.26 : 0), location: 0),
                .init(color: .black.opacity(0), location: 0.24),
                .init(color: Theme.page.opacity(0), location: 0.52),
                .init(color: Theme.page.opacity(0.88), location: 0.8),
                .init(color: Theme.page, location: 0.96),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            if photos.count > 1 {
                PageDots(count: photos.count, index: index)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 2)
            }
            // The words sit beside the number when they fit, under it when they do not.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    bigNumber
                    unitText
                }
                VStack(alignment: .leading, spacing: 4) {
                    bigNumber
                    unitText
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                caption
                Spacer(minLength: 0)
                Text(detail)
                    .foregroundStyle(detailIsOver ? Theme.over : Theme.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.ui(13))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 6)
        .animation(.snappy, value: number)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if photos.count > 1 {
                Button("Next photo") { advance() }
            }
        }
    }

    /// Where the photo's meal is from, as a link to the place; else what it was.
    @ViewBuilder private var caption: some View {
        if let place = current?.place {
            Button {
                onPlace(place)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 11, weight: .semibold))
                    Text(place.line)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the dishes people counted there")
        } else if let text = verdict ?? current?.dish ?? lastMeal {
            Text(text)
                .lineLimit(1)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var bigNumber: some View {
        Text(number.kcalText)
            .font(.number(66, .medium))
            .numberTracking(66)
            .contentTransition(.numericText(value: number))
            .lineLimit(1)
            .fixedSize()
    }

    private var unitText: some View {
        Text(unit)
            .font(.ui(17))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private func advance() {
        guard photos.count > 1 else { return }
        withAnimation(.snappy) { index = (index + 1) % photos.count }
    }
}
