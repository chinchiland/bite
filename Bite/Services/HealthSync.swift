import Foundation
import SwiftData

/// Keeps Apple Health showing exactly your log once saving meals is on: a second after any
/// change, and each time Bite comes back to the front. Edits, deletes, Undo and logs made from
/// Siri all end up the same way, because it compares the log with what Health holds.
@MainActor
final class HealthSync {
    static let shared = HealthSync()
    nonisolated static let enabledKey = "health.write"
    /// The days a normal run looks at; turning it on looks a month back.
    nonisolated static let window = 14
    nonisolated static let firstWindow = 30

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var container: ModelContainer?
    private var watching: Task<Void, Never>?
    private var pending: Task<Void, Never>?
    /// Set while the sync itself saves new ids, so its own save does not start another run.
    private var savingIDs = false

    func start(_ container: ModelContainer) {
        self.container = container
        guard watching == nil else { return }
        watching = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.soon()
            }
        }
    }

    /// One run a second after the last change, so a burst of edits writes once.
    func soon(days: Int = window) {
        guard isOn, !savingIDs else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.run(days: days)
        }
    }

    func run(days: Int = window) async {
        guard isOn, !BiteStore.isDemo, HealthMeals.shared.isAllowed, let container else { return }
        let context = container.mainContext
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) else { return }
        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= start }))) ?? []
        // Entries from before Health was on get their id the first time they are written.
        var assigned = false
        for entry in entries where entry.entryID == nil {
            entry.entryID = UUID()
            assigned = true
        }
        if assigned {
            savingIDs = true
            try? context.save()
            savingIDs = false
        }
        let desired = entries.compactMap { entry in
            entry.entryID.map { HealthMeal(id: $0, date: entry.date, name: entry.name, nutrients: entry.totals) }
        }
        guard let written = await HealthMeals.shared.written(from: start, to: .now.addingTimeInterval(86_400)) else { return }
        let plan = HealthPlan.make(desired: desired, written: written)
        guard !plan.isEmpty else { return }
        await HealthMeals.shared.apply(plan)
    }
}
