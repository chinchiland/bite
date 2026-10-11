import SwiftUI

/// The full label, in the EU order, for your amount and per 100 g. Rows with no data are left
/// out rather than shown as zero.
struct NutritionTable: View {
    let food: Food
    let amount: Double

    private struct Row: Identifiable {
        let name: String
        let indent: Bool
        let portion: String
        let reference: String
        var id: String { name }
    }

    private var showsReference: Bool { food.unit != .serving }

    private var rows: [Row] {
        let portion = food.nutrients(for: amount)
        let reference = food.nutrients(for: 100)

        func row(_ name: String, indent: Bool = false, unit: String = "g", _ value: (Nutrients) -> Double?) -> Row? {
            guard let mine = value(portion), let base = value(reference) else { return nil }
            return Row(name: name, indent: indent, portion: Self.format(mine, unit), reference: Self.format(base, unit))
        }

        let all: [Row?] = [
            row("Energy", unit: "kcal") { $0.kcal },
            row("Fat") { $0.fat },
            row("Saturated fat", indent: true) { $0.saturatedFat },
            row("Carbohydrates") { $0.carbs },
            row("Sugars", indent: true) { $0.sugar },
            row("Fiber") { $0.fiber },
            row("Protein") { $0.protein },
            row("Salt") { $0.salt },
        ]
        return all.compactMap { $0 }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text(verbatim: "")
                heading(food.unit.format(amount))
                    .gridColumnAlignment(.trailing)
                if showsReference {
                    heading("100 \(food.unit.symbol)")
                        .gridColumnAlignment(.trailing)
                }
            }

            Divider()

            ForEach(rows) { row in
                GridRow {
                    cell(row.name, weight: row.indent ? .regular : .medium, color: row.indent ? Theme.secondary : Theme.ink)
                        .padding(.leading, row.indent ? 12 : 0)
                    cell(row.portion, weight: row.indent ? .regular : .medium, color: Theme.ink)
                    if showsReference {
                        cell(row.reference, weight: .regular, color: Theme.secondary)
                    }
                }
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.ui(13, .medium))
            .foregroundStyle(Theme.secondary)
    }

    private func cell(_ text: String, weight: Font.Weight, color: Color) -> some View {
        Text(text)
            .font(.ui(15, weight))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private static func format(_ value: Double, _ unit: String) -> String {
        if unit == "kcal" { return "\(value.kcalText) kcal" }
        let digits = value < 1 ? 0...2 : 0...1
        return "\(value.formatted(.number.precision(.fractionLength(digits)))) \(unit)"
    }
}
