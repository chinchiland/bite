import Foundation

/// One fact about a food worth a glance, like "High protein" or "High sugar".
struct Highlight: Hashable, Identifiable {
    enum Kind: Hashable {
        case good
        case watch
    }

    let title: String
    let kind: Kind

    var id: String { title }
}

extension Food {
    /// Up to three highlights, good news first. Thresholds are per 100 g or 100 ml and follow
    /// the EU nutrition claims rules (Regulation 1924/2006) and the UK traffic light labels,
    /// so they match what shoppers in Europe already see on packs.
    var highlights: [Highlight] {
        guard hasNutrition, unit != .serving, per > 0 else { return [] }
        let n = nutrients.scaled(by: 100 / per)
        let drink = unit == .milliliter

        var good: [Highlight] = []
        // "High protein" needs 20% of the energy from protein, and enough protein to matter.
        if n.kcal > 0, n.protein * 4 >= n.kcal * 0.2, n.protein >= (drink ? 5 : 8) {
            good.append(Highlight(title: "High protein", kind: .good))
        }
        if let fiber = n.fiber, fiber >= 6 {
            good.append(Highlight(title: "High fiber", kind: .good))
        }
        if n.kcal <= (drink ? 20 : 40) {
            good.append(Highlight(title: "Low calorie", kind: .good))
        }

        var watch: [Highlight] = []
        if let sugar = n.sugar, sugar > (drink ? 11.25 : 22.5) {
            watch.append(Highlight(title: "High sugar", kind: .watch))
        }
        if let saturated = n.saturatedFat {
            if saturated > (drink ? 2.5 : 5) {
                watch.append(Highlight(title: "High saturated fat", kind: .watch))
            }
        } else if n.fat > (drink ? 8.75 : 17.5) {
            watch.append(Highlight(title: "High fat", kind: .watch))
        }
        if let salt = n.salt, salt > (drink ? 0.75 : 1.5) {
            watch.append(Highlight(title: "High salt", kind: .watch))
        }

        return Array((good + watch).prefix(3))
    }

    /// The NOVA group in words. Only the two ends of the scale are worth a mark.
    var processingLabel: (title: String, kind: Highlight.Kind?)? {
        switch novaGroup {
        case 1: return (title: "Unprocessed", kind: .good)
        case 2: return (title: "Culinary ingredient", kind: nil)
        case 3: return (title: "Processed", kind: nil)
        case 4: return (title: "Ultra-processed", kind: .watch)
        default: return nil
        }
    }
}
