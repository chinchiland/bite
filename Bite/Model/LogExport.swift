import Foundation

/// Your whole log as a spreadsheet: one row per food, oldest first, in columns any app reads.
/// Numbers keep a point for the decimal mark in every language, so they stay numbers.
enum LogExport {
    struct Row {
        let date: Date
        let meal: Meal
        let name: String
        let brand: String?
        let amount: Double
        let unit: FoodUnit
        /// What the amount eaten adds up to.
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let place: String?
    }

    static var title: String { tr("Bite log") }
    static var fileName: String { title + ".csv" }

    /// The file to share: UTF-8 with a byte order mark first, so spreadsheet apps read the
    /// accents right.
    static func file(_ rows: [Row], calendar: Calendar = .current) -> Data {
        Data(("\u{FEFF}" + csv(rows, calendar: calendar)).utf8)
    }

    static var header: [String] {
        [tr("Date"), tr("Time"), tr("Meal"), tr("Food"), tr("Brand"), tr("Amount"), tr("Unit"), "kcal",
         tr("Protein (g)"), tr("Carbs (g)"), tr("Fat (g)"), tr("Fiber (g)"), tr("Sugar (g)"), tr("Place")]
    }

    static func csv(_ rows: [Row], calendar: Calendar = .current) -> String {
        var lines = [header.map(field).joined(separator: ",")]
        for row in rows.sorted(by: { $0.date < $1.date }) {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: row.date)
            let values = [
                String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0),
                String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0),
                field(row.meal.title),
                field(row.name),
                field(row.brand ?? ""),
                number(row.amount),
                field(row.unit.symbol),
                number(row.kcal),
                number(row.protein),
                number(row.carbs),
                number(row.fat),
                row.fiber.map(number) ?? "",
                row.sugar.map(number) ?? "",
                field(row.place ?? ""),
            ]
            lines.append(values.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Up to one decimal, written with a point: 12, 12.5.
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// Quoted when it holds a comma, a quote or a line break. A name that starts like a formula
    /// gets an apostrophe first, so a spreadsheet shows it instead of running it.
    static func field(_ text: String) -> String {
        var text = text
        if let first = text.first, "=+-@".contains(first) { text = "'" + text }
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
