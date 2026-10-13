import SwiftUI

/// Bite asking for a photo, one row on Today under the chips: on screen at seven in the morning
/// without scrolling, when you are in the bathroom anyway. Before the first photo, a quiet row;
/// every four weeks after, "Same spot?" with how long it has been and Take it. Never a photo of
/// you in it, so Today never needs Face ID. Hold it for Not now.
struct MirrorMoment: View {
    /// Its id on the page, for scrolling to it.
    static let anchor = "mirror"

    enum Kind: Equatable {
        case first
        case next(MirrorGap)
    }

    let kind: Kind
    /// Your mirror, to look.
    let onOpen: () -> Void
    /// The camera.
    let onTake: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        Group {
            switch kind {
            case .first: first
            case .next(let gap): next(gap)
            }
        }
        .contextMenu {
            Button("Take it", systemImage: "camera", action: onTake)
            Button("Not now", systemImage: "xmark", action: onNotNow)
        }
        .accessibilityAction(named: Text("Not now"), onNotNow)
    }

    /// Shaped like Add your weight: a tile, one line, a chevron.
    private var first: some View {
        Button(action: onTake) {
            HStack(spacing: 10) {
                SymbolTile(systemImage: "person.crop.rectangle", color: Theme.ink, glyph: Theme.ink)
                Text("Take one photo to see the change later")
                    .font(.ui(15))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Shaped like your usual meal: the question, how long it has been, and the ink button.
    private func next(_ gap: MirrorGap) -> some View {
        HStack(spacing: 12) {
            SymbolTile(systemImage: "person.crop.rectangle", color: Theme.ink, glyph: Theme.ink, size: 40)
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Same spot?")
                        .font(.ui(15, .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    MirrorGapText(gap: gap)
                        .font(.ui(13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your mirror")

            Button(action: onTake) {
                Label("Take it", systemImage: "camera")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(Theme.page)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .fixedSize()
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// "6 weeks": how long between two photos, in the unit people say it in.
struct MirrorGapText: View {
    let gap: MirrorGap

    var body: some View {
        switch gap {
        case .days(let days) where days == 0:
            Text("Same day")
        case .days(let days):
            Text("\(days) days")
        case .weeks(let weeks):
            Text("\(weeks) weeks")
        case .months(let months):
            Text("\(months) months")
        case .years(let years):
            Text("\(years) years")
        }
    }
}
