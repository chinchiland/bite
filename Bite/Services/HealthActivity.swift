import Foundation
import HealthKit

/// A day's movement: the same steps and Move calories the Fitness app shows.
struct DayActivity: Equatable {
    var steps: Double
    var activeKcal: Double
}

/// Reads steps and active energy from Apple Health. Read only, nothing is written.
@MainActor
final class HealthActivity {
    static let shared = HealthActivity()

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet. Health never tells an app whether reading was allowed,
    /// so after this we simply read, and a refusal reads as zero.
    func requestAccess() async {
        guard Self.isAvailable else { return }
        let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: [], read: types)
    }

    func activity(on day: Date) async -> DayActivity {
        let steps = await total(.stepCount, unit: .count(), on: day)
        let active = await total(.activeEnergyBurned, unit: .kilocalorie(), on: day)
        return DayActivity(steps: steps, activeKcal: active)
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
