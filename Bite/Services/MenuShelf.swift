import Foundation
import Observation

/// The menus you photographed, kept on this phone so the next visit is one tap: each menu's
/// dishes in one small JSON file and its photo beside it, in Application Support/Menus.
/// Newest first, the 40 latest. The demo keeps its own in memory.
@MainActor
@Observable
final class MenuShelf {
    static let shared = MenuShelf()

    private(set) var menus: [MenuScan] = []
    /// The photos read so far, so a list of menus doesn't read a file each time it draws; the
    /// demo's live only here.
    @ObservationIgnored private var photos: [UUID: Data] = [:]

    private static let limit = 40

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Menus", directoryHint: .isDirectory)
    }()

    private static var listURL: URL { folder.appending(path: "menus.json") }

    private static func photoURL(_ id: UUID) -> URL {
        folder.appending(path: "\(id.uuidString).jpg")
    }

    init() {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            for (menu, photo) in DemoData.menus() {
                menus.append(menu)
                photos[menu.id] = photo
            }
            return
        }
        #endif
        if let data = try? Data(contentsOf: Self.listURL),
           let saved = try? JSONDecoder().decode([MenuScan].self, from: data) {
            menus = saved
        }
    }

    func menu(_ id: UUID) -> MenuScan? {
        menus.first { $0.id == id }
    }

    func photo(of id: UUID) -> Data? {
        if let photo = photos[id] { return photo }
        guard !BiteStore.isDemo, let photo = try? Data(contentsOf: Self.photoURL(id)) else { return nil }
        photos[id] = photo
        return photo
    }

    /// A menu just read, first on the shelf, with its photo.
    func add(_ menu: MenuScan, photo: Data?) {
        menus.removeAll { $0.id == menu.id }
        menus.insert(menu, at: 0)
        photos[menu.id] = photo
        if !BiteStore.isDemo, let photo {
            prepareFolder()
            try? photo.write(to: Self.photoURL(menu.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        for dropped in menus.dropFirst(Self.limit) { removePhoto(dropped.id) }
        menus = Array(menus.prefix(Self.limit))
        save()
    }

    /// A change you made, the place you set: the menu keeps its spot.
    func update(_ menu: MenuScan) {
        guard let index = menus.firstIndex(where: { $0.id == menu.id }) else { return }
        menus[index] = menu
        save()
    }

    func remove(_ id: UUID) {
        menus.removeAll { $0.id == id }
        removePhoto(id)
        save()
    }

    /// Dishes on your menus whose name or description holds every word typed: the newest menu's
    /// first.
    func dishes(matching query: String, limit: Int = 5) -> [MenuMatch] {
        var found: [MenuMatch] = []
        for menu in menus {
            for dish in menu.dishes(matching: query) {
                found.append(MenuMatch(menu: menu, dish: dish))
                if found.count == limit { return found }
            }
        }
        return found
    }

    private func removePhoto(_ id: UUID) {
        photos[id] = nil
        if !BiteStore.isDemo {
            try? FileManager.default.removeItem(at: Self.photoURL(id))
        }
    }

    private func save() {
        guard !BiteStore.isDemo, let data = try? JSONEncoder().encode(menus) else { return }
        prepareFolder()
        try? data.write(to: Self.listURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func prepareFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
    }
}

/// A dish on one of your menus, found in search.
struct MenuMatch: Identifiable {
    let menu: MenuScan
    let dish: MenuScan.Dish

    var id: String { "\(menu.id.uuidString)|\(dish.id)" }
}

/// Dishes estimated from what was typed in search, so the same words answer at once next time
/// and show their calories in search before you open them. The 80 latest, by language and words.
@MainActor
enum DishMemory {
    private struct Entry: Codable {
        var key: String
        var dish: TypicalDish
    }

    private static let storeKey = "dish.memory"
    private static var entries: [Entry] = load()

    static func key(_ words: String, language: String) -> String {
        "\(language)|" + SearchText.words(in: words).joined(separator: " ")
    }

    static func dish(for words: String, language: String) -> TypicalDish? {
        let key = key(words, language: language)
        return entries.first { $0.key == key }?.dish
    }

    static func remember(_ dish: TypicalDish, for words: String, language: String) {
        let key = key(words, language: language)
        entries.removeAll { $0.key == key }
        entries.insert(Entry(key: key, dish: dish), at: 0)
        entries = Array(entries.prefix(80))
        guard !BiteStore.isDemo, let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private static func load() -> [Entry] {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo {
            return [Entry(key: key("shawarma", language: PhotoEstimator.language), dish: DemoData.typicalDish(for: "shawarma"))]
        }
        #endif
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
