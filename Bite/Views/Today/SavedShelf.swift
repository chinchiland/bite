import SwiftUI

/// Your saved foods in a row. One tap adds to today; press and hold to edit or remove.
struct SavedShelf: View {
    let saved: [SavedFood]
    let onAdd: (SavedFood) -> Void
    let onEdit: (SavedFood) -> Void
    let onDelete: (SavedFood) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Saved", detail: saved.isEmpty ? nil : "Tap to add")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(saved) { item in
                        SavedTile(item: item) { onAdd(item) }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { onEdit(item) }
                                Button("Remove", systemImage: "trash", role: .destructive) { onDelete(item) }
                            }
                    }
                    NewSavedTile(isFirst: saved.isEmpty, action: onNew)
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.horizontal, -Theme.margin)
        }
    }
}

private struct SavedTile: View {
    let item: SavedFood
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            VStack(spacing: 6) {
                FoodThumb(food: item.food, size: 60)
                    .padding(.bottom, 1)
                Text(item.name)
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .top)
                Text("\(item.totals.kcal.kcalText) kcal")
                    .font(.ui(13))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 102)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .sensoryFeedback(.success, trigger: taps)
        .accessibilityLabel("Add \(item.name), \(item.totals.kcal.kcalText) calories")
    }
}

private struct NewSavedTile: View {
    let isFirst: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: isFirst ? "bookmark" : "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .padding(.bottom, 1)
                Text(isFirst ? "Save a food" : "New")
                    .font(.ui(15, .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(height: 38, alignment: .top)
                Text(isFirst ? "one tap to add" : " ")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(width: 102)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(isFirst ? "Save a food for one tap adding" : "New saved food")
    }
}
