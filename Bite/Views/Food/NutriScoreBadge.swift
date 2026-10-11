import SwiftUI

/// The Nutri-Score strip shoppers in Europe know from the front of the pack: five grades,
/// the product's own grade raised out of the line.
struct NutriScoreBadge: View {
    let grade: String

    private static let letters = ["A", "B", "C", "D", "E"]
    private static let hexes: [UInt32] = [0x038141, 0x85BB2F, 0xFECB02, 0xEE8100, 0xE63E11]
    private static let colors: [Color] = hexes.map { Color(lightHex: $0, darkHex: $0) }
    private static let cell: CGFloat = 17

    var body: some View {
        let selected = Self.letters.firstIndex(of: grade.uppercased())
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    Text(Self.letters[index])
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: Self.cell, height: 20)
                        .background(Self.colors[index])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if let selected {
                Text(Self.letters[selected])
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 30)
                    .background(Self.colors[selected], in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.page, lineWidth: 2)
                    }
                    .offset(x: CGFloat(selected - 2) * Self.cell)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nutri-Score \(grade.uppercased())")
    }
}
