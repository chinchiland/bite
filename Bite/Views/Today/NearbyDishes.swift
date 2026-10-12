import SwiftUI

/// Dishes people counted at the places around you (or the places you eat at, when location is
/// off): their picture, calories, how sure they are, and how far. Tap one for its page.
struct NearbyDishes: View {
    struct Item: Identifiable {
        let dish: CommunityDish
        let distance: Double?
        var id: String { dish.dishID }
    }

    let items: [Item]
    let onOpen: (CommunityDish) -> Void

    private var hasDistances: Bool { items.contains { $0.distance != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(
                title: hasDistances ? "Near you" : "At your places",
                symbol: "mappin.and.ellipse"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onOpen(item.dish)
                        } label: {
                            DishCard(dish: item.dish, distance: item.distance)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// A dish as a card in a shelf: picture, name, calories with a dot for how sure, and the place.
private struct DishCard: View {
    let dish: CommunityDish
    let distance: Double?

    var body: some View {
        let consensus = dish.consensus
        VStack(alignment: .leading, spacing: 0) {
            DishThumb(dish: dish, width: 148, height: 108)
            Text(dish.name)
                .font(.ui(14, .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.top, 8)
            HStack(spacing: 6) {
                Text("\(consensus.nutrients.kcal.kcalText) kcal")
                    .monospacedDigit()
                Circle()
                    .fill(consensus.tier.color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("\(consensus.accuracy)%")
                    .monospacedDigit()
            }
            .font(.ui(13))
            .foregroundStyle(Theme.secondary)
            .padding(.top, 2)
            HStack(spacing: 0) {
                Text(dish.placeName)
                if let distance {
                    Text(verbatim: " · ")
                    Text(distance.distanceText)
                        .monospacedDigit()
                }
            }
            .font(.ui(12))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .padding(.top, 1)
        }
        .frame(width: 148, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
