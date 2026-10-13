import Foundation
import HealthKit

/// A day's movement: the same steps and Move calories the Fitness app shows.
struct DayActivity: Equatable {
    var steps: Double
    var activeKcal: Double
}

/// One weighing from Apple Health.
struct WeightPoint: Equatable {
    var date: Date
    var kilograms: Double
}

/// What Apple Health knows of you for working out a goal; each part nil when it does not.
struct BodyFacts: Equatable {
    var sex: Sex?
    var age: Int?
    var heightCm: Double?
    var weightKg: Double?

    var isEmpty: Bool { sex == nil && age == nil && heightCm == nil && weightKg == nil }
}

/// Reads steps, active energy and weight from Apple Health. Saving meals, when you turn it
/// on, is `HealthMeals`.
@MainActor
final class HealthActivity {
    static let shared = HealthActivity()

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet. True once Health has asked; false when there is no
    /// Health or it would not ask, as in a copy of Bite signed without the Health capability.
    /// Health never tells an app whether reading was allowed, so after this we simply read, and
    /// a refusal reads as zero.
    @discardableResult
    func requestAccess() async -> Bool {
        guard Self.isAvailable else { return false }
        // Asked together, once: what Today shows, and what fills in the goal.
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.bodyMass), HKQuantityType(.height),
        ]
        if let birth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(birth) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            return true
        } catch {
            return false
        }
    }

    func activity(on day: Date) async -> DayActivity {
        let steps = await total(.stepCount, unit: .count(), on: day)
        let active = await total(.activeEnergyBurned, unit: .kilocalorie(), on: day)
        return DayActivity(steps: steps, activeKcal: active)
    }

    /// Your weighings over the last days, oldest first. Empty when there are none or reading
    /// weight was not allowed.
    func weights(days: Int = 30) async -> [WeightPoint] {
        guard Self.isAvailable,
              let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        guard let samples = try? await query.result(for: store) else { return [] }
        return samples.map { WeightPoint(date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    /// Your sex, age, height and latest weight, for the goal. Whatever Health does not know,
    /// or was not allowed to share, stays nil.
    func bodyFacts(now: Date = .now) async -> BodyFacts {
        guard Self.isAvailable else { return BodyFacts() }
        var facts = BodyFacts()
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: facts.sex = .female
        case .male: facts.sex = .male
        default: break
        }
        if let birth = try? store.dateOfBirthComponents(), let date = Calendar.current.date(from: birth) {
            facts.age = Calendar.current.dateComponents([.year], from: date, to: now).year
        }
        facts.heightCm = await latest(.height, unit: .meterUnit(with: .centi))
        facts.weightKg = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        return facts
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await query.result(for: store).first else { return nil }
        let value = sample.quantity.doubleValue(for: unit)
        return value > 0 ? value : nil
    }

    /// The day's sum, with Health merging iPhone and Apple Watch so nothing counts twice.
    private func total(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, on day: Date) async -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum
        )
        guard let statistics = try? await query.result(for: store) else { return 0 }
        return statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
    }
}
