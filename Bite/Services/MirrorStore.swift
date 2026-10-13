import Foundation
import Observation
import SwiftData

/// Your mirror's own store, apart from the food log: the log is shared with the widgets, Siri
/// and Shortcuts through the App Group, and this must never be. It lives in the app's own
/// Library/Application Support/Mirror, out of the backups, never in iCloud, and holds dates and
/// measures only; the photos are encrypted files beside it. Opened the first time it is needed.
enum MirrorStore {
    /// The folder for the store and the photo files.
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Mirror", directoryHint: .isDirectory)
    }()

    static var storeURL: URL { folder.appending(path: "Mirror.store") }

    /// True when the store on the phone could not be opened: your mirror runs empty in memory
    /// this session and leaves the real one for a build that can open it.
    private(set) static var failedToOpen = false

    /// Whether a store exists yet, so Today can know there is no photo without creating one.
    static var exists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false))
    }

    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: MirrorSchemaV1.self)
        if BiteStore.isDemo {
            return memory(schema)
        }
        prepareFolder()
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: MirrorMigrationPlan.self, configurations: configuration)
        } catch {
            if let plain = try? ModelContainer(for: schema, configurations: configuration) {
                return plain
            }
            failedToOpen = true
            return memory(schema)
        }
    }()

    private static func memory(_ schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        } catch {
            fatalError("Could not open even an empty mirror: \(error)")
        }
    }

    /// The folder before the store: SwiftData fails on a missing parent. Its files stay readable
    /// while open when the phone locks (a store closed under full protection would fail), out of
    /// backups; each photo file gets full protection of its own when it is written.
    static func prepareFolder() {
        let manager = FileManager.default
        let path = folder.path(percentEncoded: false)
        if !manager.fileExists(atPath: path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [
                .protectionKey: FileProtectionType.completeUnlessOpen,
            ])
        }
        var folderURL = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folderURL.setResourceValues(values)
    }
}

/// The mirror's shape, versioned from the start: a later change bigger than a new optional
/// field gets a stage in `MirrorMigrationPlan` and touches nothing else in the app.
enum MirrorSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MirrorShot.self]
    }
}

enum MirrorMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MirrorSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// What Today needs to know to ask for a photo: how many there are and when the last was taken.
/// Dates only, never a photo, so nothing on Today ever needs Face ID.
@MainActor
@Observable
final class MirrorLog {
    static let shared = MirrorLog()

    private(set) var count = 0
    private(set) var newest: Date?

    /// Reads the dates again: on coming back to the app, and after a photo is kept or deleted.
    func refresh() {
        // No store yet means no photo yet; opening one here would make an empty store for
        // everyone who never uses the mirror.
        guard BiteStore.isDemo || MirrorStore.exists else {
            count = 0
            newest = nil
            return
        }
        let context = MirrorStore.container.mainContext
        let shots = (try? context.fetch(FetchDescriptor<MirrorShot>(sortBy: [SortDescriptor(\.takenAt, order: .reverse)]))) ?? []
        count = shots.count
        newest = shots.first?.takenAt
    }
}
