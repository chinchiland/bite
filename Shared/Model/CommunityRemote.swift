import Foundation

/// The community server's answers and requests, as plain values: decoded and encoded here,
/// merged into the log's dishes by the app. Foundation only, so they are tested on Linux.
enum CommunityRemote {
    /// A dish near you, with its place and everyone's visible estimates.
    struct Dish: Decodable, Equatable {
        let id: String
        let name: String
        let emoji: String?
        let ratingSum: Int
        let ratingCount: Int
        let myRating: Int?
        let place: Place
        let estimates: [Estimate]
    }

    struct Place: Decodable, Equatable {
        let id: String
        let name: String
        let area: String?
        let category: String?
        let latitude: Double
        let longitude: Double
    }

    struct Estimate: Decodable, Equatable {
        let id: String
        let authorId: String
        let author: String
        let source: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let agrees: Int
        let agreedByMe: Bool
        let isMine: Bool
    }

    /// The server writes snake_case.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func dishes(from data: Data) throws -> [Dish] {
        try decoder.decode([Dish].self, from: data)
    }

    /// What sharing one estimate sends: the place, the dish and the numbers. Ids are made on the
    /// phone, so trying again never makes a second copy.
    struct Share: Encodable, Equatable {
        struct Place: Encodable, Equatable {
            let id: String
            let mapkitId: String?
            let name: String
            let area: String?
            let category: String?
            let latitude: Double
            let longitude: Double
        }

        struct Dish: Encodable, Equatable {
            let id: String
            let name: String
            let emoji: String?
        }

        struct Estimate: Encodable, Equatable {
            let id: String
            let source: String
            let kcal: Double
            let protein: Double
            let carbs: Double
            let fat: Double
        }

        let pPlace: Place
        let pDish: Dish
        let pEstimate: Estimate
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    /// The server's ids for what was shared: the dish may be one someone else already added.
    struct Shared: Decodable, Equatable {
        let placeId: String
        let dishId: String
        let estimateId: String
    }

    /// The name people see for you: your first name and the initial of your last, "Dylan T.";
    /// at most 30 letters. Empty when Apple gave no name.
    static func shortName(given: String?, family: String?) -> String {
        let first = (given ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = (family ?? "").trimmingCharacters(in: .whitespacesAndNewlines).first.map { " \($0)." } ?? ""
        return String((first + initial).trimmingCharacters(in: .whitespaces).prefix(30))
    }
}
