import SwiftUI

/// Nutri-Score as a chip: the grade's letter on its official color, then the name. The chip is
/// green for A and B, quiet for C, warm for D and E.
struct NutriScoreChip: View {
    let grade: String

    private static let hexes: [String: UInt32] = [
        "A": 0x038141, "B": 0x85BB2F, "C": 0xFECB02, "D": 0xEE8100, "E": 0xE63E11,
    ]

    var body: some View {
        let letter = grade.uppercased()
        let hex = Self.hexes[letter] ?? 0x9A9890
        HStack(spacing: 6) {
            Text(verbatim: letter)
                .font(.ui(13, .semibold))
                .foregroundStyle(letter == "C" ? Color.black.opacity(0.7) : Color.white)
                .frame(width: 24, height: 24)
                .background(Color(lightHex: hex, darkHex: hex), in: Circle())
            Text("Nutri-Score")
                .font(.ui(13, .medium))
                .foregroundStyle(style.text)
        }
        .padding(.leading, 4)
        .padding(.trailing, 11)
        .frame(height: 32)
        .background(style.fill, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nutri-Score \(letter)")
    }

    private var style: (text: Color, fill: Color) {
        switch grade.uppercased() {
        case "A", "B": (text: Theme.goodText, fill: Theme.goodFill)
        case "D", "E": (text: Theme.watchText, fill: Theme.watchFill)
        default: (text: Theme.ink, fill: Theme.fill)
        }
    }
}
