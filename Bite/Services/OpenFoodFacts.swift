import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Open Food Facts: the free, open database of packaged food, millions of barcodes with strong
/// coverage in Switzerland and France. No account or key needed.
/// API: https://openfoodfacts.github.io/openfoodfacts-server/api/
struct OpenFoodFacts {
    static let shared = OpenFoodFacts()

    /// The reader's languages, so product names come back in French on a French phone.
    static let languages: [String] = {
        var codes: [String] = []
        for identifier in Locale.preferredLanguages {
            let code = String(identifier.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
            if !code.isEmpty, !codes.contains(code) { codes.append(code) }
        }
        if !codes.contains("en") { codes.append("en") }
        return codes
    }()

    static let fields: String = {
        var fields = [
            "code", "product_name", "generic_name", "brands",
            "image_front_small_url", "image_front_url", "nutriments",
            "nutriscore_grade", "nova_group", "serving_size", "serving_quantity",
            "product_quantity", "product_quantity_unit", "allergens_tags", "unique_scans_n",
        ]
        for language in Set(languages + ["en", "fr", "de", "it"]).sorted() {
            fields.append("product_name_\(language)")
        }
        return fields.joined(separator: ",")
    }()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.default
        // Open Food Facts asks every app to say who it is.
        configuration.httpAdditionalHeaders = ["User-Agent": "Bite/1.0 (iOS calorie tracker)"]
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    /// The product behind a barcode, or nil when Open Food Facts does not know it yet.
    func product(barcode: String) async throws -> Food? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        for code in Self.variants(of: digits) {
            guard var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(code)") else {
                continue
            }
            components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
            guard let url = components.url else { continue }

            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 { continue }
            guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }

            let decoded = try JSONDecoder().decode(OFFProductResponse.self, from: data)
            if decoded.status == 1, let food = decoded.product?.food() {
                return food
            }
        }
        return nil
    }

    /// Products matching a query, the ones people scan most first, so the one in your fridge
    /// is near the top.
    func search(_ query: String) async throws -> [Food] {
        guard var components = URLComponents(string: "https://search.openfoodfacts.org/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: "50"),
            URLQueryItem(name: "fields", value: Self.fields),
            URLQueryItem(name: "langs", value: Self.languages.joined(separator: ",")),
        ]
        guard let url = components.url else { return [] }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        return Self.rank(decoded.hits, for: query)
    }

    /// The search API ranks by text relevance, which lets a cereal that lists rice in its
    /// ingredients beat a bag of rice. Sorting by scans alone puts Nutella first for
    /// "chocolat noir". So: keep relevance's candidates, prefer the ones whose name or brand
    /// holds every word typed, and among those put the most scanned first.
    static func rank(_ hits: [OFFProduct], for query: String, languages: [String] = languages, limit: Int = 25) -> [Food] {
        let terms = SearchText.words(in: query)
        var named: [(food: Food, scans: Double, position: Int)] = []
        var others: [Food] = []
        for (position, hit) in hits.enumerated() {
            guard let food = hit.food(languages: languages), food.hasNutrition else { continue }
            let words = SearchText.words(in: "\(food.name) \(hit.brands ?? "")")
            if SearchText.matches(terms, in: words) {
                named.append((food: food, scans: hit.uniqueScans ?? 0, position: position))
            } else {
                others.append(food)
            }
        }
        named.sort { ($0.scans, -$0.position) > ($1.scans, -$1.position) }
        return Array((named.map { $0.food } + others).prefix(limit))
    }

    /// Scanners report UPC-A codes with or without the leading zero of their EAN-13 form.
    static func variants(of code: String) -> [String] {
        var codes = [code]
        if code.count == 12 { codes.append("0" + code) }
        if code.count == 13, code.hasPrefix("0") { codes.append(String(code.dropFirst())) }
        return codes
    }
}
