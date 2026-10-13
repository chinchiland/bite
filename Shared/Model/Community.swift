import Foundation
import SwiftData

/// A dish at a place, as people counted it. Its calories are what their estimates add up to,
/// weighted by how many people agreed with each one.
@Model
final class CommunityDish {
    var dishID: String = UUID().uuidString
    var name: String = ""
    var emoji: String?
    @Attribute(.externalStorage) var photo: Data?
    var placeName: String = ""
    var placeArea: String?
    var placeLatitude: Double?
    var placeLongitude: Double?
    var placeCategoryRaw: String?
    /// Everyone else's stars, as a sum and a count. Yours is kept apart so you can change it.
    var ratingSum: Double = 0
    var ratingCount: Int = 0
    var myRating: Int?
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \DishEstimate.dish)
    var estimates: [DishEstimate] = []

    init(name: String, emoji: String?, photo: Data?, place: MealPlace) {
        self.name = name
        self.emoji = emoji
        self.photo = photo
        self.placeName = place.name
        self.placeArea = place.area
        self.placeLatitude = place.latitude
        self.placeLongitude = place.longitude
        self.placeCategoryRaw = place.category?.rawValue
    }
}

/// One person's count of a dish: by Claude from a photo of their plate, or typed in by hand.
@Model
final class DishEstimate {
    var author: String = ""
    var sourceRaw: String = EstimateSource.entered.rawValue
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// People who said this count matches their plate.
    var agrees: Int = 0
    var agreedByMe: Bool = false
    var isMine: Bool = false
    var tintRaw: String = FoodTint.sky.rawValue
    var createdAt: Date = Date.now
    var dish: CommunityDish?
    /// The estimate's id on the community server, once shared there or read from it.
    var remoteID: String?
    /// Who wrote it on the server, for hiding a person's counts.
    var authorID: String?
    /// Yours only: kept on this phone, being shared, or shared.
    var shareStateRaw: String?

    init(author: String, source: EstimateSource, nutrients: Nutrients, agrees: Int = 0, isMine: Bool = false, tint: FoodTint = .sky) {
        self.author = author
        self.sourceRaw = source.rawValue
        self.kcal = nutrients.kcal
        self.protein = nutrients.protein
        self.carbs = nutrients.carbs
        self.fat = nutrients.fat
        self.agrees = agrees
        self.isMine = isMine
        self.tintRaw = tint.rawValue
    }
}

enum EstimateSource: String {
    /// Claude read a photo of the plate.
    case ai
    /// Someone typed it in: from the menu, the pack or their own count.
    case entered
}

extension CommunityDish {
    var place: MealPlace {
        MealPlace(
            name: placeName,
            area: placeArea,
            latitude: placeLatitude,
            longitude: placeLongitude,
            category: placeCategoryRaw.flatMap(MealPlace.Category.init(rawValue:))
        )
    }

    var consensus: Consensus {
        Consensus(estimates.map {
            Consensus.Estimate(kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, agrees: $0.agrees)
        })
    }

    /// The estimates most people stand behind first; yours last when it is new.
    var rankedEstimates: [DishEstimate] {
        estimates.sorted { ($0.agrees, $1.createdAt) > ($1.agrees, $0.createdAt) }
    }

    /// Everyone's stars with yours in: the average and how many people rated.
    var rating: (average: Double, count: Int)? {
        let sum = ratingSum + Double(myRating ?? 0)
        let count = ratingCount + (myRating == nil ? 0 : 1)
        return count > 0 ? (sum / Double(count), count) : nil
    }

    var displayTint: FoodTint { FoodTint.suggested(for: emoji) }

    /// The dish as a food to log: one serving at what the estimates add up to.
    var food: Food {
        Food(
            id: "dish:\(dishID)",
            name: name,
            emoji: emoji ?? "🍽️",
            source: .community,
            unit: .serving,
            per: 1,
            nutrients: consensus.nutrients,
            imageData: photo
        )
    }
}

/// Where your estimate is: on this phone only, on its way, or shared with people eating there.
enum ShareState: String {
    case local
    case sharing
    case shared
}

extension DishEstimate {
    var shareState: ShareState {
        get { shareStateRaw.flatMap(ShareState.init(rawValue:)) ?? .local }
        set { shareStateRaw = newValue.rawValue }
    }

    /// Someone else's estimate that came from the server, so it can be reported or hidden.
    var isRemote: Bool { !isMine && remoteID != nil }

    var source: EstimateSource { EstimateSource(rawValue: sourceRaw) ?? .entered }
    var tint: FoodTint { FoodTint(rawValue: tintRaw) ?? .sky }

    /// "TR" for Tom R., "Y" for you.
    var initials: String {
        let letters = author.split(separator: " ").compactMap(\.first)
        return String(letters.prefix(2)).uppercased()
    }

    var nutrients: Nutrients { Nutrients(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}
