import SwiftUI
import UIKit

/// The top of a day: your latest meal photo as its cover (a fresh gradient until the first
/// photo), the one number that matters on it, and the day's controls floating above.
struct DayCover<Controls: View>: View {
    let photo: UIImage?
    let height: CGFloat
    let topInset: CGFloat
    let number: Double
    /// Already in the reader's language: "kcal left today".
    let unit: String
    let caption: String?
    let detail: String
    @ViewBuilder let controls: Controls

    private var onPhoto: Bool { photo != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            hero
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            controls
                .padding(.top, topInset + 2)
                .padding(.horizontal, 16)
        }
    }

    private var backdrop: some View {
        Color.clear
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .overlay { scrim }
                } else {
                    Theme.coverGradient
                }
            }
            .clipped()
            // Pulling down past the top stretches the cover instead of opening a gap.
            .visualEffect { content, proxy in
                let pull = max(proxy.frame(in: .scrollView).minY, 0)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    /// Dark at the foot so white numbers read on any photo, a soft shade at the head for the
    /// controls, clear in between so the food shows.
    private var scrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.32), location: 0),
                .init(color: .black.opacity(0), location: 0.24),
                .init(color: .black.opacity(0), location: 0.34),
                .init(color: .black.opacity(0.5), location: 0.62),
                .init(color: .black.opacity(0.84), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                if let caption {
                    Text(caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(detail)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.ui(13))
            .opacity(0.85)
        }
        .foregroundStyle(onPhoto ? Color.white : Theme.ink)
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, Theme.sheetRadius + 26)
        .animation(.snappy, value: number)
        .accessibilityElement(children: .combine)
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
            .opacity(0.85)
            .lineLimit(1)
            .fixedSize()
    }
}
