import Foundation
import SwiftData
import UIKit
import UserNotifications

/// The mealtime nudge, when you said yes to it: planned three days ahead each time Bite opens or
/// the log changes, skipped on a day the meal is already in, and its Add logs yesterday's meal
/// from the Lock Screen without opening Bite.
@MainActor
enum Reminders {
    static let category = "meal.nudge"
    static let addAction = "add"
    private static let storageKey = "reminder"
    private static let answeredKey = "reminder.answered"
    private static let prefix = "meal.nudge."

    /// The nudge you turned on; nil when off.
    static var current: MealReminder? {
        get {
            UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONDecoder().decode(MealReminder.self, from: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: storageKey)
        }
    }

    /// The offer was answered, either way: it never comes back on its own.
    static var answered: Bool {
        get { UserDefaults.standard.bool(forKey: answeredKey) }
        set { UserDefaults.standard.set(newValue, forKey: answeredKey) }
    }

    /// Asks iOS once, then plans the nudge. False when notifications were refused.
    static func turnOn(_ reminder: MealReminder, context: ModelContext) async -> Bool {
        answered = true
        let center = UNUserNotificationCenter.current()
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard allowed else { return false }
        current = reminder
        registerCategory()
        await reschedule(context: context)
        return true
    }

    static func turnOff() {
        current = nil
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static var watching: Task<Void, Never>?
    private static var pending: Task<Void, Never>?

    /// Plans again a second after the log changes, so a meal logged early takes today's nudge away.
    static func start(_ container: ModelContainer) {
        guard watching == nil else { return }
        watching = Task {
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard current != nil else { continue }
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await reschedule(context: container.mainContext)
                }
            }
        }
    }

    /// The next three nudges, replacing the last plan.
    static func reschedule(context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard let reminder = current, !BiteStore.isDemo else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let meal = reminder.mealRaw
        let descriptor = FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.date >= today && $0.date < tomorrow && $0.mealRaw == meal })
        let loggedToday = ((try? context.fetchCount(descriptor)) ?? 0) > 0

        for date in reminder.fireDates(now: now, loggedToday: loggedToday, calendar: calendar) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = tr("Add the same as last time in one tap, or open Bite.")
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["meal": meal]
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = prefix + String(Int(date.timeIntervalSince1970))
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func registerCategory() {
        let add = UNNotificationAction(identifier: addAction, title: tr("Add"), options: [])
        let nudge = UNNotificationCategory(identifier: category, actions: [add], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([nudge])
    }

    /// The nudge's Add: the last day's foods of that meal, logged now, as Today's usual does.
    static func addLast(_ meal: Meal, context: ModelContext, now: Date = .now) {
        let raw = meal.rawValue
        let today = Calendar.current.startOfDay(for: now)
        var descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date < today && $0.mealRaw == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        guard let entries = try? context.fetch(descriptor), let last = entries.first else { return }
        let lastDay = Calendar.current.startOfDay(for: last.date)
        let foods = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: lastDay) }
        for item in foods.reversed() {
            context.insert(FoodEntry(food: item.food, amount: item.amount, meal: meal, date: now))
        }
        try? context.save()
        // Bite reads the log afresh when it next opens, and the widgets redraw.
        LogStore.wrote(added: nil)
    }
}

/// Answers a nudge's Add in the background, and shows nudges that arrive while Bite is open.
final class BiteAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in Reminders.registerCategory() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Reminders.addAction,
              let raw = response.notification.request.content.userInfo["meal"] as? String,
              let meal = Meal(rawValue: raw) else { return }
        await MainActor.run {
            let context = BiteStore.container.mainContext
            Reminders.addLast(meal, context: context)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
