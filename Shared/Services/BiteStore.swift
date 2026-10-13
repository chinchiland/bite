import Foundation
import SwiftData

/// The one food log, shared by the app, its widgets, and its Siri and Shortcuts actions.
enum BiteStore {
    /// The seeded log in memory: Debug builds launched with `-demo` (the screenshots), and
    /// Bite Demo, the app built with BITE_DEMO, which always opens on it.
    static let isDemo: Bool = {
        #if BITE_DEMO
        return true
        #elseif DEBUG
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        return false
        #endif
    }()

    /// True when the log on the phone could not be opened: Bite runs on an empty one in memory
    /// for this session, and leaves the real one untouched for a build that can open it.
    private(set) static var failedToOpen = false

    static let container: ModelContainer = {
        let schema = Schema(versionedSchema: BiteSchemaV1.self)
        let configuration = BiteStore.configuration(for: schema)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: BiteMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            if let plain = try? ModelContainer(for: schema, configurations: configuration) {
                return plain
            }
            failedToOpen = true
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            } catch {
                fatalError("Could not open even an empty log: \(error)")
            }
        }
    }()
}

extension BiteStore {
    /// Where the log lives: in the App Group, so the widgets read and write the same one,
    /// moved there once from the app's own folder; in memory for the demo; in the app's own
    /// folder in a copy signed without the group. Never mirrored to iCloud.
    static func configuration(for schema: Schema) -> ModelConfiguration {
        if isDemo { return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true) }
        guard let url = AppGroup.storeURL else {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        StoreMove.moveIfNeeded(to: url)
        return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }
}

/// The log's shape, versioned from the first install on: a later change that is more than a new
/// optional field gets a migration stage here, instead of a crash at launch.
enum BiteSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FoodEntry.self, SavedFood.self, WaterDay.self, CommunityDish.self, DishEstimate.self]
    }
}

enum BiteMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BiteSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
