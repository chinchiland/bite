import Foundation

/// Where a meal was eaten: a restaurant, a cafe or a bakery picked from the places around you.
struct MealPlace: Hashable, Codable {
    var name: String
    /// The neighborhood or street that tells two places of the same name apart: "Parc de Milan".
    var area: String?
    var latitude: Double?
    var longitude: Double?
    /// What kind of place it is: restaurant, cafe, bakery, bar or market.
    var category: Category?

    enum Category: String, Codable, CaseIterable {
        case restaurant
        case cafe
        case bakery
        case bar
        case market

        var symbol: String {
            switch self {
            case .restaurant: "fork.knife"
            case .cafe: "cup.and.saucer.fill"
            case .bakery: "birthday.cake.fill"
            case .bar: "wineglass.fill"
            case .market: "basket.fill"
            }
        }

        var title: String {
            switch self {
            case .restaurant: tr("Restaurant")
            case .cafe: tr("Cafe")
            case .bakery: tr("Bakery")
            case .bar: tr("Bar")
            case .market: tr("Market")
            }
        }
    }

    init(name: String, area: String? = nil, latitude: Double? = nil, longitude: Double? = nil, category: Category? = nil) {
        self.name = name
        self.area = area
        self.latitude = latitude
        self.longitude = longitude
        self.category = category
    }

    /// "El Beirout · Parc de Milan", or the name alone.
    var line: String {
        guard let area, !area.isEmpty, area != name else { return name }
        return "\(name) · \(area)"
    }

    /// The same place, whatever coordinates two people logged it with.
    var key: String {
        "\(name.lowercased())|\((area ?? "").lowercased())"
    }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// The distance between two points on the Earth, in meters, close enough for "350 m away".
    static func meters(fromLatitude a: Double, longitude b: Double, toLatitude c: Double, longitude d: Double) -> Double {
        let radius = 6_371_000.0
        let dLat = (c - a) * .pi / 180
        let dLon = (d - b) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a * .pi / 180) * cos(c * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    /// How far this place is from a point, when both are known.
    func distance(fromLatitude latitude: Double, longitude: Double) -> Double? {
        guard let ownLatitude = self.latitude, let ownLongitude = self.longitude else { return nil }
        return Self.meters(fromLatitude: latitude, longitude: longitude, toLatitude: ownLatitude, longitude: ownLongitude)
    }
}
