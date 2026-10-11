import Foundation

/// The soft color behind a food's emoji. Pastel and low in saturation, so a shelf of foods
/// feels friendly without shouting. The colors themselves live in `Theme`.
enum FoodTint: String, CaseIterable, Identifiable {
    case sand
    case peach
    case butter
    case mint
    case sky
    case lilac
    case blush

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// A tint that fits the food: fruit warm, vegetables green, grains golden, dairy and drinks
    /// blue, meat and fish pink, sweets lilac, the rest sand.
    static func suggested(for emoji: String?) -> FoodTint {
        guard let emoji, !emoji.isEmpty else { return .sand }
        for (tint, set) in groups where set.contains(emoji) { return tint }
        return .sand
    }

    private static let groups: [(FoodTint, Set<String>)] = [
        (.peach, ["🍎", "🍏", "🍌", "🍊", "🍋", "🍐", "🍓", "🫐", "🍇", "🥝", "🥭", "🍍", "🍉", "🍑", "🍒", "🍈", "🥥"]),
        (.mint, ["🥦", "🥕", "🍅", "🥒", "🥬", "🫑", "🧅", "🧄", "🍄", "🫛", "🍠", "🥔", "🌽", "🫒", "🥗", "🥑", "🌶️"]),
        (.butter, ["🍚", "🍝", "🥣", "🍞", "🥖", "🥐", "🥯", "🫓", "🍕", "🌾", "🥞", "🧇", "🍜", "🍛", "🌮", "🌯", "🥪", "🍔", "🍟"]),
        (.sky, ["🥛", "🧀", "🧈", "☕", "🧃", "🍺", "🍷", "🥂", "🥤", "🍵", "🧋", "💧"]),
        (.blush, ["🥚", "🍳", "🍗", "🥩", "🐟", "🦐", "🍖", "🥓", "🦃", "🍣", "🍤", "🌭"]),
        (.lilac, ["🍯", "🍬", "🍫", "🫙", "🍪", "🍦", "🍰", "🧁", "🍩", "🍮", "🍭", "🎂"]),
    ]
}
