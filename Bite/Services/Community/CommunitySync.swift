import CoreLocation
import Foundation
import SwiftData

/// Between the dishes on this phone and the community server: your estimate shared when you
/// say so, the dishes around you read in, and your agrees and stars sent along. Nothing runs
/// while the server is not set up.
@MainActor
enum CommunitySync {
    /// Shares your estimate of a dish. The dish takes the server's id, which may be one someone
    /// else already added at that place under the same name.
    static func share(_ estimate: DishEstimate, of dish: CommunityDish, context: ModelContext) async throws {
        let token = try await CommunityAccount.shared.validToken()
        let place = dish.place
        let estimateID = estimate.remoteID ?? UUID().uuidString
        estimate.remoteID = estimateID
        estimate.shareState = .sharing
        try? context.save()
        let share = CommunityRemote.Share(
            pPlace: .init(
                id: UUID().uuidString,
                mapkitId: nil,
                name: place.name,
                area: place.area,
                category: place.category?.rawValue,
                latitude: place.latitude ?? 0,
                longitude: place.longitude ?? 0
            ),
            pDish: .init(id: dish.dishID, name: dish.name, emoji: dish.emoji),
            pEstimate: .init(
                id: estimateID,
                source: estimate.source.rawValue,
                kcal: estimate.kcal,
                protein: estimate.protein,
                carbs: estimate.carbs,
                fat: estimate.fat
            )
        )
        do {
            let shared = try await CommunityClient().share(share, token: token)
            dish.dishID = shared.dishId
            estimate.remoteID = shared.estimateId
            estimate.authorID = CommunityAccount.shared.session?.userID
            estimate.shareState = .shared
        } catch {
            estimate.shareState = .local
            try? context.save()
            throw error
        }
        try? context.save()
    }

    /// Reads the dishes people counted around you into the phone's dishes, at most once every
    /// few minutes.
    static func pullNear(_ location: CLLocation, context: ModelContext) async {
        guard CommunityServer.isConfigured, Date.now.timeIntervalSince(lastPull) > 300 else { return }
        lastPull = .now
        let token = CommunityAccount.shared.isSignedIn ? try? await CommunityAccount.shared.validToken() : nil
        guard let dishes = try? await CommunityClient().dishesNear(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            token: token
        ) else { return }
        for remote in dishes {
            merge(remote, into: context)
        }
        try? context.save()
    }

    private static var lastPull = Date.distantPast

    /// One dish from the server into the phone: added when new, its counts brought up to date.
    /// Your own estimates stay as you keep them on the phone.
    static func merge(_ remote: CommunityRemote.Dish, into context: ModelContext) {
        let id = remote.id
        let dish: CommunityDish
        if let found = try? context.fetch(FetchDescriptor<CommunityDish>(predicate: #Predicate { $0.dishID == id })).first {
            dish = found
        } else {
            let place = MealPlace(
                name: remote.place.name,
                area: remote.place.area,
                latitude: remote.place.latitude,
                longitude: remote.place.longitude,
                category: remote.place.category.flatMap(MealPlace.Category.init(rawValue:))
            )
            dish = CommunityDish(name: remote.name, emoji: remote.emoji, photo: nil, place: place)
            dish.dishID = remote.id
            context.insert(dish)
        }
        // The phone keeps your stars apart from everyone else's.
        dish.myRating = remote.myRating
        dish.ratingSum = Double(remote.ratingSum - (remote.myRating ?? 0))
        dish.ratingCount = remote.ratingCount - (remote.myRating == nil ? 0 : 1)

        for counted in remote.estimates where !counted.isMine {
            let nutrients = Nutrients(kcal: counted.kcal, protein: counted.protein, carbs: counted.carbs, fat: counted.fat)
            let estimate: DishEstimate
            if let found = dish.estimates.first(where: { $0.remoteID == counted.id }) {
                estimate = found
                estimate.kcal = counted.kcal
                estimate.protein = counted.protein
                estimate.carbs = counted.carbs
                estimate.fat = counted.fat
                estimate.author = counted.author
            } else {
                estimate = DishEstimate(
                    author: counted.author,
                    source: EstimateSource(rawValue: counted.source) ?? .entered,
                    nutrients: nutrients,
                    agrees: counted.agrees
                )
                estimate.remoteID = counted.id
                dish.estimates.append(estimate)
            }
            estimate.authorID = counted.authorId
            estimate.agrees = counted.agrees
            estimate.agreedByMe = counted.agreedByMe
        }
    }

    /// Your agree, sent along when the estimate is on the server and you are signed in.
    static func agree(_ estimate: DishEstimate) {
        guard CommunityServer.isConfigured, let id = estimate.remoteID, CommunityAccount.shared.isSignedIn else { return }
        let agree = estimate.agreedByMe
        Task {
            guard let token = try? await CommunityAccount.shared.validToken() else { return }
            try? await CommunityClient().setAgree(estimateID: id, agree: agree, token: token)
        }
    }

    /// Your stars, sent along when the dish came from or went to the server.
    static func rate(_ dish: CommunityDish) {
        guard CommunityServer.isConfigured, CommunityAccount.shared.isSignedIn,
              dish.estimates.contains(where: { $0.remoteID != nil }) else { return }
        let id = dish.dishID
        let stars = dish.myRating
        Task {
            guard let token = try? await CommunityAccount.shared.validToken() else { return }
            try? await CommunityClient().rate(dishID: id, stars: stars, token: token)
        }
    }

    static func report(_ estimate: DishEstimate) async throws {
        let token = try await CommunityAccount.shared.validToken()
        try await CommunityClient().report(dishID: nil, estimateID: estimate.remoteID, reason: "", token: token)
    }

    /// Hides a person's counts: on the server for good, and from this phone now.
    static func hide(authorOf estimate: DishEstimate, context: ModelContext) async throws {
        guard let author = estimate.authorID else { return }
        let token = try await CommunityAccount.shared.validToken()
        try await CommunityClient().hide(authorID: author, token: token)
        let wanted: String? = author
        let theirs = (try? context.fetch(FetchDescriptor<DishEstimate>(predicate: #Predicate { $0.authorID == wanted }))) ?? []
        for item in theirs {
            context.delete(item)
        }
        try? context.save()
    }
}
