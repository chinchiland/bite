import SwiftUI
import UIKit

extension Consensus.Tier {
    /// Green when people agree closely, blue when they mostly do, orange when it is rough, gray
    /// when there are too few estimates to say.
    var color: Color {
        switch self {
        case .veryAccurate: Theme.onTarget
        case .accurate: Theme.accurate
        case .rough: Theme.rough
        case .needsMore: Theme.tertiary
        }
    }
}

/// A dish's picture: its photo, or its emoji on its pastel, in the shape every food tile has.
struct DishThumb: View {
    let dish: CommunityDish
    var width: CGFloat = 58
    var height: CGFloat? = nil

    var body: some View {
        let side = height ?? width
        Group {
            if let data = dish.photo, let image = ImageTools.thumbnail(data, points: max(width, side)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.tint(dish.displayTint)
                    .overlay {
                        Text(dish.emoji ?? "🍽️")
                            .font(.system(size: min(width, side) * 0.46))
                    }
            }
        }
        .frame(width: width, height: side)
        .clipShape(RoundedRectangle(cornerRadius: FoodThumb.radius(for: min(width, side)), style: .continuous))
        .accessibilityHidden(true)
    }
}

/// How sure a dish's calories are: a ring filled to its accuracy with the number inside, in
/// the color of its tier.
struct AccuracyGauge: View {
    let consensus: Consensus
    var size: CGFloat = 40

    var body: some View {
        let line = size * 0.09
        ZStack {
            Circle()
                .strokeBorder(Theme.track, lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: CGFloat(consensus.accuracy) / 100)
                .stroke(consensus.tier.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(consensus.accuracy)")
                .font(.number(size * 0.33))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: consensus.accuracy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(consensus.accuracy) percent accurate")
    }
}

/// The head of a dish's estimates: the gauge, its tier in words and what it rests on. Tapping
/// it explains how it is worked out.
struct AccuracyRow: View {
    let consensus: Consensus
    /// The one estimate so far is yours: it asks others, not you, to add theirs.
    var onlyYours = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AccuracyGauge(consensus: consensus)
                VStack(alignment: .leading, spacing: 2) {
                    Text(consensus.tier.title)
                        .font(.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.ui(13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("How the accuracy is worked out")
    }

    private var detail: String {
        if consensus.estimates <= 1 {
            return onlyYours
                ? String(localized: "Only your estimate so far. Each one people add firms it up.")
                : String(localized: "One estimate so far. Add yours to firm it up.")
        }
        return String(localized: "\(consensus.estimates) estimates within \(consensus.spreadPercent)%, agreed by \(consensus.agrees)")
    }
}

/// Who made an estimate, with how: a sparkle when Claude read their plate, a pencil when they
/// typed it in. The badge sits on the avatar's corner.
struct EstimateAvatar: View {
    let estimate: DishEstimate

    var body: some View {
        Group {
            if estimate.isMine {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text(verbatim: estimate.initials)
                    .font(.ui(11, .semibold))
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 32, height: 32)
        .background(Theme.tint(estimate.tint), in: Circle())
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: estimate.source == .ai ? "sparkles" : "pencil")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(estimate.source == .ai ? Theme.accurate : Theme.entered, in: Circle())
                .overlay { Circle().stroke(Theme.card, lineWidth: 2) }
                .offset(x: 5, y: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(estimate.source == .ai ? Text("Scanned with AI") : Text("Entered by hand"))
    }
}

/// The people who say a count matches their plate, and the button to say so too.
struct AgreeButton: View {
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                Text(verbatim: count.formatted())
                    .font(.ui(13, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
            .foregroundStyle(isOn ? Theme.accurate : Theme.ink)
            .padding(.leading, 11)
            .padding(.trailing, 12)
            .frame(minWidth: 58)
            .frame(height: 30)
            .background(isOn ? Theme.accurate.opacity(0.12) : Theme.fill, in: Capsule())
            .animation(.snappy, value: isOn)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .sensoryFeedback(trigger: isOn) { _, on in on ? Feel.click : nil }
        .accessibilityLabel("\(count) people agree")
        .accessibilityHint(isOn ? "Takes back your agreement" : "Says this count matches your plate")
    }
}

/// One person's estimate: who, how, how many calories, and how many agree.
struct EstimateRow: View {
    let estimate: DishEstimate
    let onAgree: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            EstimateAvatar(estimate: estimate)
            Text(estimate.isMine ? String(localized: "You") : estimate.author)
                .font(.ui(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(estimate.kcal.kcalText) kcal")
                .font(.number(15))
                .foregroundStyle(Theme.ink)
                .fixedSize()
            if estimate.isMine {
                Text(estimate.shareState == .shared ? LocalizedStringKey("Shared") : LocalizedStringKey("Yours"))
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
                    .frame(minWidth: 58)
            } else {
                AgreeButton(count: estimate.agrees, isOn: estimate.agreedByMe, action: onAgree)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

/// Five stars to rate a dish, in one tap.
struct StarRating: View {
    let rating: Int?
    let onRate: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onRate(star)
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(star <= (rating ?? 0) ? Theme.energy : Theme.track)
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .accessibilityLabel("\(star) stars")
            }
        }
        .sensoryFeedback(Feel.tick, trigger: rating)
    }
}

/// What the accuracy means and how it is worked out, one tap away from every dish.
struct AccuracyExplainer: View {
    let consensus: Consensus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        AccuracyGauge(consensus: consensus, size: 64)
                        Text(consensus.tier.title)
                            .font(.ui(22, .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Text("Every estimate counts once, and once more for each person who agreed with it. The calories are the average of all that. Accuracy is how close the estimates sit to each other, times how many people stand behind them, so three close estimates and a few agreements reach 90.")
                        .font(.ui(15))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 12) {
                        tierRow(.veryAccurate, range: "90 to 100")
                        tierRow(.accurate, range: "70 to 89")
                        tierRow(.rough, range: "50 to 69")
                        tierRow(.needsMore, range: "Under 50")
                    }
                }
                .padding(Theme.margin)
            }
            .background(Theme.card.ignoresSafeArea())
            .navigationTitle("Accuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tierRow(_ tier: Consensus.Tier, range: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tier.color)
                .frame(width: 10, height: 10)
            Text(tier.title)
                .font(.ui(15, .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(range)
                .font(.ui(15))
                .foregroundStyle(Theme.secondary)
        }
    }
}
