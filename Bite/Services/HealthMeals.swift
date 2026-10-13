import Foundation
import HealthKit

/// Writes your meals to Apple Health when you turn it on: one food correlation per food you
/// logged, each nutrient a sample inside it, every object with a sync identifier so an edit
/// replaces the old copy instead of adding a second one.
final class HealthMeals: @unchecked Sendable {
    static let shared = HealthMeals()

    private let store = HKHealthStore()
    private let foodType = HKObjectType.correlationType(forIdentifier: .food)!
    /// Bite's own key: what Health shows for the meal, to tell when it changed.
    private static let signatureKey = "BiteSignature"

    private static func type(_ nutrient: HealthMeal.Nutrient) -> (HKQuantityType, HKUnit) {
        switch nutrient {
        case .energy: (HKQuantityType(.dietaryEnergyConsumed), .kilocalorie())
        case .protein: (HKQuantityType(.dietaryProtein), .gram())
        case .carbs: (HKQuantityType(.dietaryCarbohydrates), .gram())
        case .fat: (HKQuantityType(.dietaryFatTotal), .gram())
        case .fiber: (HKQuantityType(.dietaryFiber), .gram())
        case .sugar: (HKQuantityType(.dietarySugar), .gram())
        case .saturatedFat: (HKQuantityType(.dietaryFatSaturated), .gram())
        case .sodium: (HKQuantityType(.dietarySodium), .gramUnit(with: .milli))
        }
    }

    private static var shareTypes: Set<HKSampleType> {
        Set(HealthMeal.Nutrient.allCases.map { type($0).0 })
    }

    /// Whether Health lets Bite save meals. Health tells writing apart, never reading.
    var isAllowed: Bool {
        HealthActivity.isAvailable && store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingAuthorized
    }

    /// Turned off in the Health app after it was allowed once.
    var isTurnedOff: Bool {
        HealthActivity.isAvailable && store.authorizationStatus(for: HKQuantityType(.dietaryEnergyConsumed)) == .sharingDenied
    }

    /// Shows Health's sheet for the types not decided yet. True when saving is allowed after it.
    func requestAccess() async -> Bool {
        guard HealthActivity.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: [])
        } catch {
            return false
        }
        return isAllowed
    }

    /// The meals Bite wrote between two dates. An app always sees what it wrote itself, even
    /// without the right to read. Nil when Health could not be read, as on a locked phone.
    func written(from start: Date, to end: Date) async -> [HealthWritten]? {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end),
            HKQuery.predicateForObjects(from: HKSource.default()),
        ])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: foodType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let written = (samples ?? []).compactMap { sample -> HealthWritten? in
                    guard let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String, id.hasPrefix(HealthMeal.prefix) else { return nil }
                    let version = (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0
                    let signature = sample.metadata?[Self.signatureKey] as? String ?? ""
                    return HealthWritten(syncID: id, version: version, signature: signature)
                }
                continuation.resume(returning: written)
            }
            store.execute(query)
        }
    }

    /// Makes Health match the plan: deletes first, then saves in small batches.
    func apply(_ plan: HealthPlan) async {
        if !plan.deletes.isEmpty {
            await delete(foodType, HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: plan.deletes))
            let sampleIDs = plan.deletes.flatMap { id in HealthMeal.Nutrient.allCases.map { "\(id).\($0.rawValue)" } }
            let samples = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: sampleIDs)
            for nutrient in HealthMeal.Nutrient.allCases {
                await delete(Self.type(nutrient).0, samples)
            }
        }
        let objects = plan.saves.map(correlation)
        var start = 0
        while start < objects.count {
            let batch = Array(objects[start..<min(start + 8, objects.count)])
            _ = await save(batch)
            start += 8
        }
    }

    /// Takes every meal Bite wrote back out of Health.
    func removeAll() async {
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        await delete(foodType, mine)
        for nutrient in HealthMeal.Nutrient.allCases {
            await delete(Self.type(nutrient).0, mine)
        }
    }

    private func correlation(_ save: HealthPlan.Save) -> HKCorrelation {
        let meal = save.meal
        let samples = Set(meal.samples.map { sample -> HKSample in
            let (type, unit) = Self.type(sample.nutrient)
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: sample.value),
                start: meal.date,
                end: meal.date,
                metadata: [
                    HKMetadataKeySyncIdentifier: "\(meal.syncID).\(sample.nutrient.rawValue)",
                    HKMetadataKeySyncVersion: save.version,
                ]
            )
        })
        return HKCorrelation(
            type: foodType,
            start: meal.date,
            end: meal.date,
            objects: samples,
            metadata: [
                HKMetadataKeyFoodType: meal.name,
                HKMetadataKeySyncIdentifier: meal.syncID,
                HKMetadataKeySyncVersion: save.version,
                Self.signatureKey: meal.signature,
            ]
        )
    }

    private func save(_ objects: [HKObject]) async -> Bool {
        await withCheckedContinuation { continuation in
            store.save(objects) { success, _ in continuation.resume(returning: success) }
        }
    }

    private func delete(_ type: HKObjectType, _ predicate: NSPredicate) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.deleteObjects(of: type, predicate: predicate) { _, _, _ in continuation.resume() }
        }
    }
}
