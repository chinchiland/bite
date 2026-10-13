import Foundation
import SwiftData
import WidgetKit

/// Keeps the widgets drawing today the way the app does: it mirrors the settings they need into
/// the App Group, keeps today's burned calories there when Health is read, and asks for a redraw
/// a second after the log or the settings change.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private var watching: [Task<Void, Never>] = []
    private var pending: Task<Void, Never>?

    func start() {
        // Bite Demo's widgets draw the demo's sample day; its log is in memory.
        guard watching.isEmpty, !BiteStore.isDemo, AppGroup.container != nil else { return }
        publishSettings()
        watching.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.soon()
            }
        })
        watching.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.soon()
            }
        })
    }

    /// One redraw a second after the last change, so a burst of edits redraws once.
    func soon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.publishSettings()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The goal, the split, No target, the water goal and whether burned calories count,
    /// copied into the group. Only what changed is written, so this never wakes itself.
    func publishSettings() {
        let standard = UserDefaults.standard
        let group = AppGroup.defaults
        set(standard.object(forKey: AppGroup.Key.goal) as? Int ?? 2000, AppGroup.Key.goal, in: group)
        set(standard.string(forKey: AppGroup.Key.split) ?? MacroSplit.balanced.rawValue, AppGroup.Key.split, in: group)
        set(standard.bool(forKey: AppGroup.Key.noTarget), AppGroup.Key.noTarget, in: group)
        set(standard.object(forKey: AppGroup.Key.waterGoal) as? Int ?? 8, AppGroup.Key.waterGoal, in: group)
        set(standard.bool(forKey: AppGroup.Key.addBurned), AppGroup.Key.addBurned, in: group)
    }

    /// Today's burned calories as Health gave them, for a goal that adds them.
    func publishBurned(_ kcal: Double, on day: Date) {
        guard AppGroup.container != nil else { return }
        let start = Calendar.current.startOfDay(for: day).timeIntervalSince1970
        set(kcal.rounded(), AppGroup.Key.burned, in: AppGroup.defaults)
        set(start, AppGroup.Key.burnedDay, in: AppGroup.defaults)
    }

    private func set<Value: Equatable>(_ value: Value, _ key: String, in defaults: UserDefaults) {
        guard defaults.object(forKey: key) as? Value != value else { return }
        defaults.set(value, forKey: key)
    }
}
