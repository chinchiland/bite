import Foundation

/// The App Group Bite and its widgets share: the log's store, and the few settings a widget
/// needs to draw today (the goal, the split, water), which the app mirrors there.
enum AppGroup {
    /// "group." and the app's bundle id, so Bite and Bite Demo each have their own; the widgets,
    /// at "<app id>.widgets", share their app's.
    static let id: String = {
        var bundle = Bundle.main.bundleIdentifier ?? "com.dylan.bite"
        if bundle.hasSuffix(".widgets") { bundle = String(bundle.dropLast(".widgets".count)) }
        return "group." + bundle
    }()

    /// The group's folder; nil in a copy signed without the group, where the log stays in the
    /// app's own folder and the widgets ask to open Bite once.
    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// The log, in the group so a widget reads and writes the same one.
    static var storeURL: URL? {
        container?.appending(path: "Library/Application Support/Bite.store")
    }

    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    /// The keys both sides use.
    enum Key {
        static let goal = "goal.kcal"
        static let split = "goal.split"
        static let noTarget = "goal.noTarget"
        static let waterGoal = "water.goal"
        static let addBurned = "health.addBurned"
        /// Today's burned calories as the app last read them from Health, and the day they are for.
        static let burned = "widget.burned"
        static let burnedDay = "widget.burnedDay"
        /// The last food a widget logged, for its Undo, and when.
        static let lastAddID = "widget.lastAddID"
        static let lastAddAt = "widget.lastAddAt"
        /// When a widget last wrote to the log, so the app knows to read it again.
        static let wroteAt = "widget.wroteAt"
    }
}

/// Moves the log from the app's own folder into the group, once, before anything opens it. The
/// old files stay where they were, so a build without the group still finds them.
enum StoreMove {
    static func moveIfNeeded(to url: URL, fileManager: FileManager = .default) {
        let folder = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: url.path) else { return }
        let old = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fileManager.fileExists(atPath: old.path) else { return }
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(fileURLWithPath: old.path + suffix)
            guard fileManager.fileExists(atPath: from.path) else { continue }
            try? fileManager.copyItem(at: from, to: URL(fileURLWithPath: url.path + suffix))
        }
        // Photos kept outside the database live beside it, in a folder named after the store.
        let photos = old.deletingLastPathComponent().appending(path: ".default_SUPPORT")
        if fileManager.fileExists(atPath: photos.path) {
            try? fileManager.copyItem(at: photos, to: folder.appending(path: ".Bite_SUPPORT"))
        }
    }
}
