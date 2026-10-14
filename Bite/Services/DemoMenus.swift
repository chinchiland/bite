#if DEBUG || BITE_DEMO
import Foundation
import UIKit

/// The demo's menus: El Beirout's, read this lunchtime, and a pizzeria's from last week. The
/// dishes keep the names the menus print; their photos are drawn here, so nothing is borrowed.
extension DemoData {
    static let beirout = MealPlace(name: "El Beirout", area: "Parc de Milan", latitude: 46.51492, longitude: 6.62268, category: .restaurant)

    private typealias Line = (name: String, description: String, price: String, emoji: String, grams: Double, kcal: Double, protein: Double, carbs: Double, fat: Double, fiber: Double, sugar: Double)

    private static func dishes(_ lines: [Line]) -> [MenuScan.Dish] {
        lines.map { line in
            MenuScan.Dish(
                name: line.name,
                description: line.description,
                price: line.price,
                dish: TypicalDish(title: line.name, emoji: line.emoji, grams: line.grams, kcal: line.kcal, protein: line.protein, carbs: line.carbs, fat: line.fat, fiber: line.fiber, sugar: line.sugar)
            )
        }
    }

    /// The menus, newest first, with their photos.
    static func menus() -> [(MenuScan, Data)] {
        let beiroutLines: [Line] = [
            ("Shawarma poulet", tr("Garlic sauce, pickles, Lebanese bread"), "14.50", "🌯", 350, 640, 38, 55, 28, 4, 5),
            ("Shawarma bœuf", tr("Tahini, onions, parsley"), "15.50", "🌯", 350, 690, 36, 52, 35, 4, 4),
            ("Wrap falafel", tr("Tahini, tomatoes, mint"), "12.00", "🧆", 300, 520, 16, 62, 22, 9, 5),
            ("Assiette shawarma, frites", tr("With hummus and salad"), "24.00", "🍟", 600, 1180, 52, 112, 58, 10, 7),
            ("Kafta grillée", tr("Lamb and beef, rice"), "26.00", "🍢", 450, 860, 48, 70, 42, 4, 4),
            ("Houmous", "", "9.00", "🫓", 200, 430, 14, 38, 24, 8, 2),
            ("Taboulé", "", "9.00", "🥗", 180, 240, 5, 24, 14, 5, 3),
            ("Moutabal", tr("Smoked aubergine"), "9.50", "🍆", 180, 260, 5, 14, 21, 6, 6),
            ("Fattouche", "", "10.00", "🥗", 250, 280, 5, 26, 18, 6, 6),
            ("Baklava", "", "6.00", "🍯", 60, 250, 4, 28, 14, 1, 16),
            ("Thé à la menthe", "", "4.50", "🍵", 300, 70, 0, 18, 0, 0, 18),
            ("Ayran", "", "4.00", "🥛", 250, 90, 4, 6, 5, 0, 6),
        ]
        let pizzeriaLines: [Line] = [
            ("Margherita", "", "16.00", "🍕", 330, 820, 34, 100, 30, 5, 8),
            ("Diavola", tr("Spicy salami"), "19.00", "🍕", 350, 940, 40, 100, 42, 5, 8),
            ("Quattro formaggi", "", "20.00", "🍕", 340, 1020, 44, 98, 50, 4, 6),
            ("Lasagne al forno", "", "21.00", "🍝", 400, 640, 34, 52, 32, 4, 10),
            ("Tiramisù", "", "9.00", "🍰", 120, 380, 7, 36, 23, 1, 26),
        ]
        let calendar = Calendar.current
        let lunch = calendar.date(bySettingHour: 12, minute: 31, second: 0, of: .now) ?? .now
        let lastWeek = calendar.date(byAdding: .day, value: -6, to: calendar.date(bySettingHour: 20, minute: 5, second: 0, of: .now) ?? .now) ?? .now
        let beirout = MenuScan(takenAt: lunch, restaurant: "El Beirout", dishes: dishes(beiroutLines), place: Self.beirout)
        let pizzeria = MenuScan(takenAt: lastWeek, restaurant: "Pizzeria Bella", dishes: dishes(pizzeriaLines))
        return [
            (beirout, ImageTools.jpeg(menuPhoto(title: "EL BEIROUT", subtitle: "Cuisine libanaise", sections: [
                ("Sandwichs", Array(beiroutLines[0..<3])),
                ("Assiettes", Array(beiroutLines[3..<5])),
                ("Mezzés", Array(beiroutLines[5..<9])),
                ("Douceurs et boissons", Array(beiroutLines[9...])),
            ], paper: UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1), ink: UIColor(red: 0.16, green: 0.20, blue: 0.17, alpha: 1)), maxSide: 1400, quality: 0.75) ?? Data()),
            (pizzeria, ImageTools.jpeg(menuPhoto(title: "Pizzeria Bella", subtitle: "Forno a legna", sections: [
                ("Pizze", Array(pizzeriaLines[0..<3])),
                ("Cucina", [pizzeriaLines[3]]),
                ("Dolci", [pizzeriaLines[4]]),
            ], paper: UIColor(red: 0.13, green: 0.14, blue: 0.13, alpha: 1), ink: UIColor(white: 0.94, alpha: 1)), maxSide: 1400, quality: 0.75) ?? Data()),
        ]
    }

    /// The demo's answer for a dish typed in search: the shawarma for its words, a plain plate
    /// for anything else.
    static func typicalDish(for words: String) -> TypicalDish {
        if SearchText.words(in: words).contains(where: { $0.hasPrefix("shaw") || $0.hasPrefix("chawar") }) {
            return TypicalDish(title: tr("Chicken shawarma"), emoji: "🌯", grams: 350, kcal: 640, protein: 38, carbs: 55, fat: 28, fiber: 4, sugar: 5)
        }
        let title = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return TypicalDish(title: title.prefix(1).uppercased() + title.dropFirst(), emoji: "🍽️", grams: 300, kcal: 520, protein: 24, carbs: 50, fat: 24, fiber: 5, sugar: 6)
    }

    /// A menu as a phone sees it on the table: the paper a little turned on dark wood, the
    /// house's name, and its dishes with their prices.
    private static func menuPhoto(title: String, subtitle: String, sections: [(String, [Line])], paper: UIColor, ink: UIColor) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            UIColor(red: 0.27, green: 0.19, blue: 0.13, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            // Grain in the wood.
            for row in stride(from: 0, to: size.height, by: 9) {
                UIColor(white: 0, alpha: row.truncatingRemainder(dividingBy: 27) == 0 ? 0.12 : 0.05).setFill()
                cg.fill(CGRect(x: 0, y: row, width: size.width, height: 3))
            }
            cg.saveGState()
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -0.025)
            let sheet = CGRect(x: -500, y: -720, width: 1000, height: 1440)
            cg.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: UIColor(white: 0, alpha: 0.45).cgColor)
            paper.setFill()
            cg.fill(sheet)
            cg.setShadow(offset: .zero, blur: 0)

            let serif = UIFont.systemFont(ofSize: 74, weight: .semibold).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 74) } ?? .systemFont(ofSize: 74)
            let serifSmall = UIFont.systemFont(ofSize: 30, weight: .regular).fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: 30) } ?? .systemFont(ofSize: 30)
            let center = NSMutableParagraphStyle()
            center.alignment = .center
            NSAttributedString(string: title, attributes: [.font: serif, .foregroundColor: ink, .paragraphStyle: center, .kern: 6])
                .draw(in: CGRect(x: sheet.minX, y: sheet.minY + 90, width: sheet.width, height: 100))
            NSAttributedString(string: subtitle, attributes: [.font: serifSmall, .foregroundColor: ink.withAlphaComponent(0.7), .paragraphStyle: center])
                .draw(in: CGRect(x: sheet.minX, y: sheet.minY + 192, width: sheet.width, height: 44))

            var y = sheet.minY + 300
            let left = sheet.minX + 90, right = sheet.maxX - 90
            for (header, lines) in sections {
                NSAttributedString(string: header.uppercased(), attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.65), .kern: 5])
                    .draw(at: CGPoint(x: left, y: y))
                y += 56
                for line in lines {
                    let name = NSAttributedString(string: line.name, attributes: [.font: UIFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: ink])
                    let price = NSAttributedString(string: line.price, attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .regular), .foregroundColor: ink])
                    name.draw(at: CGPoint(x: left, y: y))
                    price.draw(at: CGPoint(x: right - price.size().width, y: y + 2))
                    // The dots between a dish and its price.
                    ink.withAlphaComponent(0.35).setFill()
                    var dot = left + name.size().width + 18
                    while dot < right - price.size().width - 18 {
                        cg.fillEllipse(in: CGRect(x: dot, y: y + 28, width: 4, height: 4))
                        dot += 14
                    }
                    y += 62
                }
                y += 34
            }
            cg.restoreGState()
        }
    }
}
#endif
