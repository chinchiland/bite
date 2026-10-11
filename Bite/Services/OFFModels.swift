import Foundation

/// `GET /api/v2/product/{barcode}`
struct OFFProductResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

/// `GET search.openfoodfacts.org/search`
struct OFFSearchResponse: Decodable {
    let hits: [OFFProduct]
}

/// A product as Open Food Facts sends it. Contributors type the data in by hand, so numbers
/// sometimes arrive as strings and brands as either a string or a list. Decoding never fails
/// on one odd field.
struct OFFProduct: Decodable {
    var code: String?
    var names: [String: String] = [:]
    var genericName: String?
    var brands: String?
    var imageSmall: String?
    var image: String?
    var nutriments: [String: Double] = [:]
    var nutriScore: String?
    var novaGroup: Int?
    var servingSize: String?
    var servingQuantity: Double?
    var productQuantity: Double?
    var productQuantityUnit: String?
    var allergenTags: [String] = []
    /// How many people scanned it: a good sign it is the one on your shelf.
    var uniqueScans: Double?

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)

        func lenient(_ key: String) -> Lenient? {
            try? container.decodeIfPresent(Lenient.self, forKey: Key(key))
        }

        code = lenient("code")?.text
        for key in container.allKeys where key.stringValue == "product_name" || key.stringValue.hasPrefix("product_name_") {
            if let name = lenient(key.stringValue)?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                names[key.stringValue] = name
            }
        }
        genericName = lenient("generic_name")?.text
        brands = lenient("brands")?.text
        imageSmall = lenient("image_front_small_url")?.text
        image = lenient("image_front_url")?.text
        nutriScore = lenient("nutriscore_grade")?.text
        novaGroup = lenient("nova_group")?.number.map { Int($0) }
        servingSize = lenient("serving_size")?.text
        servingQuantity = lenient("serving_quantity")?.number
        productQuantity = lenient("product_quantity")?.number
        productQuantityUnit = lenient("product_quantity_unit")?.text
        allergenTags = lenient("allergens_tags")?.list ?? []
        uniqueScans = lenient("unique_scans_n")?.number

        if let raw = try? container.decodeIfPresent([String: Lenient].self, forKey: Key("nutriments")) {
            nutriments = raw.compactMapValues { $0.number }
        }
    }
}

/// A JSON value that may be a number, a numeric string, a string, or a list of strings.
struct Lenient: Decodable {
    var number: Double?
    var text: String?
    var list: [String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let value = try? container.decode(Double.self) {
            number = value
            text = value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        } else if let value = try? container.decode(String.self) {
            text = value
            number = Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        } else if let values = try? container.decode([String].self) {
            list = values
            text = values.joined(separator: ", ")
        }
    }
}

extension OFFProduct {
    /// Turns the raw product into a `Food`, or nil when it has no barcode or no name at all.
    func food(languages: [String] = OpenFoodFacts.languages) -> Food? {
        guard let code, !code.isEmpty, let name = displayName(languages: languages) else { return nil }

        let kcal = nutriments["energy-kcal_100g"]
            ?? nutriments["energy-kj_100g"].map { $0 / 4.184 }
            ?? nutriments["energy_100g"].map { $0 / 4.184 }
        let unit: FoodUnit = isLiquid ? .milliliter : .gram

        return Food(
            id: "off:\(code)",
            name: name,
            brand: firstBrand,
            barcode: code,
            imageURL: (imageSmall ?? image).flatMap { URL(string: $0) },
            source: .openFoodFacts,
            unit: unit,
            per: 100,
            nutrients: Nutrients(
                kcal: kcal ?? 0,
                protein: nutriments["proteins_100g"] ?? 0,
                carbs: nutriments["carbohydrates_100g"] ?? 0,
                fat: nutriments["fat_100g"] ?? 0,
                sugar: nutriments["sugars_100g"],
                fiber: nutriments["fiber_100g"],
                saturatedFat: nutriments["saturated-fat_100g"],
                salt: nutriments["salt_100g"]
            ),
            portions: portions(unit: unit),
            nutriScore: grade,
            novaGroup: novaGroup.flatMap { (1...4).contains($0) ? $0 : nil },
            // Only the canonical English tags are real allergens; others are unparsed label text.
            allergens: allergenTags.filter { $0.hasPrefix("en:") }.map(Self.allergenName),
            hasNutrition: kcal != nil
        )
    }

    /// The name in the reader's language when the product has one.
    func displayName(languages: [String]) -> String? {
        for language in languages {
            if let name = names["product_name_\(language)"] { return name }
        }
        if let name = names["product_name"] { return name }
        if let name = names["product_name_en"] { return name }
        if let name = names.sorted(by: { $0.key < $1.key }).first?.value { return name }
        if let genericName, !genericName.isEmpty { return genericName }
        return nil
    }

    var firstBrand: String? {
        guard let brands else { return nil }
        let first = brands.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return (first?.isEmpty ?? true) ? nil : first
    }

    var isLiquid: Bool {
        guard let unit = productQuantityUnit?.lowercased() else { return false }
        return ["ml", "cl", "dl", "l"].contains(unit)
    }

    var grade: String? {
        guard let grade = nutriScore?.lowercased(), ["a", "b", "c", "d", "e"].contains(grade) else { return nil }
        return grade
    }

    /// Serving first when the pack names one, then 100 g, then the whole pack.
    func portions(unit: FoodUnit) -> [Portion] {
        var result: [Portion] = []
        if let serving = servingQuantity, serving > 0, abs(serving - 100) > 0.01 {
            result.append(Portion(label: Self.servingLabel(servingSize), amount: serving))
        }
        result.append(Portion(label: "100 \(unit.symbol)", amount: 100))
        if let pack = productQuantity, pack > 0, pack <= 2000,
           !result.contains(where: { abs($0.amount - pack) < 0.5 }) {
            result.append(Portion(label: "Whole pack", amount: pack))
        }
        return result
    }

    /// "1 biscuit (12 g)" becomes "1 biscuit". A bare quantity like "30 g" becomes "1 serving".
    static func servingLabel(_ text: String?) -> String {
        guard var label = text?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return "1 serving"
        }
        if let parenthesis = label.firstIndex(of: "(") {
            label = String(label[..<parenthesis]).trimmingCharacters(in: .whitespaces)
        }
        let bareQuantity = #"^[\d.,\s]*(g|gr|gram|grams|grammes|ml|cl|l|oz)?$"#
        if label.isEmpty || label.range(of: bareQuantity, options: [.regularExpression, .caseInsensitive]) != nil {
            return "1 serving"
        }
        return label.count <= 22 ? label : "1 serving"
    }

    /// "en:milk" becomes "Milk".
    static func allergenName(_ tag: String) -> String {
        let name = tag.split(separator: ":").last.map(String.init) ?? tag
        let words = name.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
