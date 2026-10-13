import SwiftUI

/// Your saved foods in a row of tiles. One tap adds to today; press and hold to edit or remove.
struct SavedShelf: View {
    /// "Fits your 967 kcal left" while there is room today, "Saved" otherwise.
    var title: LocalizedStringKey = "Saved"
    /// One line under the title: what is behind today and what the order does about it.
    var note: String? = nil
    let saved: [SavedFood]
    let onAdd: (SavedFood) -> Void
    let onEdit: (SavedFood) -> Void
    let onDelete: (SavedFood) -> Void
    let onNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(title: title, detail: saved.isEmpty ? nil : "Tap to add", symbol: "bookmark.fill")
                if let note {
                    Text(note)
                        .font(.ui(14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rail(spacing: 10) {
                ForEach(saved) { item in
                    SavedTile(item: item) { onAdd(item) }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { onEdit(item) }
                            Button("Remove", systemImage: "trash", role: .destructive) { onDelete(item) }
                        }
                }
                NewSavedTile(isFirst: saved.isEmpty, action: onNew)
            }
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
            VStack(alignment: .leading, spacing: 0) {
                FoodThumb(food: item.food, size: 76)
                Text(item.name)
                    .font(.ui(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .frame(height: 34, alignment: .topLeading)
                    .padding(.top, 7)
                Text("\(item.totals.kcal.kcalText) kcal")
                    .font(.ui(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
                    .padding(.top, 1)
            }
            .frame(width: 76, alignment: .leading)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .sensoryFeedback(Feel.land, trigger: taps)
        .accessibilityLabel("Add \(item.name), \(item.totals.kcal.kcalText) calories")
    }
}

private struct NewSavedTile: View {
    let isFirst: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: isFirst ? "bookmark" : "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 76, height: 76)
                    .background {
                        RoundedRectangle(cornerRadius: FoodThumb.radius(for: 76), style: .continuous)
                            .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                Text(isFirst ? "Save a food" : "New")
                    .font(.ui(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .frame(height: 34, alignment: .topLeading)
                    .padding(.top, 7)
                Text(isFirst ? "one tap to add" : " ")
                    .font(.ui(12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .frame(width: isFirst ? 120 : 76, alignment: .leading)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(isFirst ? "Save a food for one tap adding" : "New saved food")
    }
}
