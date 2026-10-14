import CryptoKit
import Foundation
import Observation
import StoreKit
import SwiftData

// Your mirror, kept forever: $4.99 once, and an encrypted copy of every photo waits on Bite's
// server for your next iPhone. The photo files travel exactly as they are on the phone, sealed
// to the mirror's key; that key and the one that signs for your shelf live in iCloud Keychain,
// end-to-end encrypted by Apple. Bite holds only ciphertext it can never open, and needs no
// account: a new iPhone on the same Apple Account finds its shelf with the synced key.

/// One photo's row, for the backup's list: everything but the pixels, sealed like a photo.
struct MirrorRecord: Codable {
    var photoID: UUID
    var takenAt: Date
    var proppedUp: Bool
    var imported: Bool
    var widthPx: Int
    var heightPx: Int
    var weightKg: Double?
    var rigShoulderY: Double?
    var rigHipY: Double?
    var rigAnkleY: Double?
    var rigCenterX: Double?
    var rollDegrees: Double
    var bodyCenterX: Double?
    var bodyShoulderY: Double?
    var bodySpan: Double?
    var iso: Double?
    var exposureSeconds: Double?
    var whiteRed: Double?
    var whiteGreen: Double?
    var whiteBlue: Double?
    var lockFailed: Bool
    var lightDifference: Double

    init(_ shot: MirrorShot) {
        photoID = shot.photoID
        takenAt = shot.takenAt
        proppedUp = shot.proppedUp
        imported = shot.imported
        widthPx = shot.widthPx
        heightPx = shot.heightPx
        weightKg = shot.weightKg
        rigShoulderY = shot.rigShoulderY
        rigHipY = shot.rigHipY
        rigAnkleY = shot.rigAnkleY
        rigCenterX = shot.rigCenterX
        rollDegrees = shot.rollDegrees
        bodyCenterX = shot.bodyCenterX
        bodyShoulderY = shot.bodyShoulderY
        bodySpan = shot.bodySpan
        iso = shot.iso
        exposureSeconds = shot.exposureSeconds
        whiteRed = shot.whiteRed
        whiteGreen = shot.whiteGreen
        whiteBlue = shot.whiteBlue
        lockFailed = shot.lockFailed
        lightDifference = shot.lightDifference
    }

    var shot: MirrorShot {
        let shot = MirrorShot(photoID: photoID, takenAt: takenAt, proppedUp: proppedUp)
        shot.imported = imported
        shot.widthPx = widthPx
        shot.heightPx = heightPx
        shot.weightKg = weightKg
        shot.rigShoulderY = rigShoulderY
        shot.rigHipY = rigHipY
        shot.rigAnkleY = rigAnkleY
        shot.rigCenterX = rigCenterX
        shot.rollDegrees = rollDegrees
        shot.bodyCenterX = bodyCenterX
        shot.bodyShoulderY = bodyShoulderY
        shot.bodySpan = bodySpan
        shot.iso = iso
        shot.exposureSeconds = exposureSeconds
        shot.whiteRed = whiteRed
        shot.whiteGreen = whiteGreen
        shot.whiteBlue = whiteBlue
        shot.lockFailed = lockFailed
        shot.lightDifference = lightDifference
        return shot
    }
}

/// Your shelf on Bite's server: every request signed with your key, so only your phones can
/// read or change it.
struct MirrorShelf {
    enum Failure: Error {
        case offline
        case refused(Int)
    }

    let signing: P256.Signing.PrivateKey

    static let manifest = "manifest.bite"

    func list() async throws -> [String] {
        let data = try await send("list", name: "")
        struct Names: Decodable { let names: [String] }
        return try JSONDecoder().decode(Names.self, from: data).names
    }

    func get(_ name: String) async throws -> Data {
        try await send("get", name: name)
    }

    func put(_ name: String, _ body: Data) async throws {
        _ = try await send("put", name: name, body: body)
    }

    func delete(_ name: String) async throws {
        _ = try await send("delete", name: name)
    }

    private func send(_ op: String, name: String, body: Data = Data()) async throws -> Data {
        guard let base = CommunityServer.url,
              var parts = URLComponents(url: base.appending(path: "functions/v1/mirror-backup"), resolvingAgainstBaseURL: false) else { throw Failure.offline }
        parts.queryItems = [URLQueryItem(name: "op", value: op), URLQueryItem(name: "name", value: name)]
        guard let url = parts.url else { throw Failure.offline }
        let time = String(Int(Date.now.timeIntervalSince1970))
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let message = Data("\(op)\n\(name)\n\(time)\n\(digest)".utf8)
        let signature = try signing.signature(for: message)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(CommunityServer.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(signing.publicKey.x963Representation.base64EncodedString(), forHTTPHeaderField: "x-mirror-key")
        request.setValue(time, forHTTPHeaderField: "x-mirror-time")
        request.setValue(signature.rawRepresentation.base64EncodedString(), forHTTPHeaderField: "x-mirror-signature")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.refused(status) }
        return data
    }
}

/// Keep forever: the purchase, and the copy kept in step with your mirror.
@MainActor
@Observable
final class MirrorKeep {
    static let shared = MirrorKeep()
    static let productID = "com.dylan.bite.mirror.forever"

    enum Status: Equatable {
        case idle
        case saving
        case saved(Date)
        case failed
        case restoring
    }

    private(set) var product: Product?
    /// Bought, here or on another iPhone, or a shelf found in iCloud Keychain.
    private(set) var owned = UserDefaults.standard.bool(forKey: "mirror.keep.owned")
    private(set) var status: Status = .idle
    private(set) var buying = false

    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var syncing = false

    private static let syncedPrivate = "mirror.sync.private"
    private static let syncedSigning = "mirror.sync.signing"

    /// The price as the App Store shows it here, or the dollar price until it loads.
    var price: String { product?.displayPrice ?? "$4.99" }

    /// Listens for purchases (a family member's, a refund, Ask to Buy) and loads the product.
    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshOwned()
                }
            }
        }
        Task {
            product = try? await Product.products(for: [Self.productID]).first
            await refreshOwned()
        }
    }

    func refreshOwned() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                markOwned()
            }
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "mirror.keep") { markOwned() }
        #endif
    }

    /// $4.99 once. True when it went through.
    func buy() async -> Bool {
        guard let product, !buying else { return false }
        buying = true
        defer { buying = false }
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            markOwned()
            return true
        default:
            return false
        }
    }

    /// Restore Purchases, for a new iPhone or after deleting Bite.
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshOwned()
    }

    private func markOwned() {
        owned = true
        UserDefaults.standard.set(true, forKey: "mirror.keep.owned")
    }

    // MARK: The copy

    /// Your shelf, with the keys put in iCloud Keychain the first time: the signing key made
    /// once, the photos' key copied while the mirror is open. Nil until both are there.
    private func shelf() -> MirrorShelf? {
        var signingRaw = Keychain.syncedData(for: Self.syncedSigning)
        if signingRaw == nil {
            let key = P256.Signing.PrivateKey()
            if Keychain.setSyncedData(key.rawRepresentation, for: Self.syncedSigning) { signingRaw = key.rawRepresentation }
        }
        if Keychain.syncedData(for: Self.syncedPrivate) == nil {
            guard let raw = MirrorVault.shared.privateKeyData(), Keychain.setSyncedData(raw, for: Self.syncedPrivate) else { return nil }
        }
        guard let signingRaw, let key = try? P256.Signing.PrivateKey(rawRepresentation: signingRaw) else { return nil }
        return MirrorShelf(signing: key)
    }

    /// Brings the shelf in step with your mirror: the photos it doesn't have yet, the ones you
    /// deleted taken off, and the list last, so it never names a photo the shelf doesn't hold.
    func sync() async {
        guard owned, !syncing, let shelf = shelf() else { return }
        syncing = true
        defer { syncing = false }
        status = .saving
        do {
            let context = MirrorStore.container.mainContext
            let shots = try context.fetch(FetchDescriptor<MirrorShot>())
            var files: [String: (id: UUID, thumbnail: Bool)] = [:]
            for shot in shots {
                files["\(shot.photoID.uuidString).bite"] = (shot.photoID, false)
                files["\(shot.photoID.uuidString)-t.bite"] = (shot.photoID, true)
            }
            let remote = Set(try await shelf.list())
            for (name, file) in files where !remote.contains(name) {
                let data = await Task.detached(priority: .utility) {
                    MirrorVault.shared.sealedFile(file.id, thumbnail: file.thumbnail)
                }.value
                if let data { try await shelf.put(name, data) }
            }
            for name in remote where files[name] == nil && name != MirrorShelf.manifest {
                try await shelf.delete(name)
            }
            let list = try JSONEncoder().encode(shots.map(MirrorRecord.init))
            try await shelf.put(MirrorShelf.manifest, try MirrorVault.shared.sealed(list))
            status = .saved(.now)
        } catch {
            status = .failed
        }
    }

    /// Photos kept from another iPhone, found through iCloud Keychain: how many, or nil.
    func findKept() async -> Int? {
        guard Keychain.syncedData(for: Self.syncedPrivate) != nil,
              let signingRaw = Keychain.syncedData(for: Self.syncedSigning),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: signingRaw),
              let names = try? await MirrorShelf(signing: key).list(),
              names.contains(MirrorShelf.manifest) else { return nil }
        return names.filter { $0.hasSuffix(".bite") && !$0.hasSuffix("-t.bite") && $0 != MirrorShelf.manifest }.count
    }

    /// Brings every kept photo back onto this iPhone: the keys from iCloud Keychain, the list,
    /// then the files exactly as they were sealed.
    func restore(protected: Bool) async -> Bool {
        guard let privateRaw = Keychain.syncedData(for: Self.syncedPrivate),
              let signingRaw = Keychain.syncedData(for: Self.syncedSigning),
              let key = try? P256.Signing.PrivateKey(rawRepresentation: signingRaw) else { return false }
        status = .restoring
        let shelf = MirrorShelf(signing: key)
        let adopted = await Task.detached(priority: .userInitiated) {
            MirrorVault.shared.adoptKeys(privateRaw: privateRaw, protected: protected)
        }.value
        guard adopted else {
            status = .failed
            return false
        }
        do {
            let sealedList = try await shelf.get(MirrorShelf.manifest)
            let records = try JSONDecoder().decode([MirrorRecord].self, from: try MirrorVault.open(sealedList, privateRaw: privateRaw))
            let context = MirrorStore.container.mainContext
            let here = Set(try context.fetch(FetchDescriptor<MirrorShot>()).map(\.photoID))
            for record in records where !here.contains(record.photoID) {
                for thumbnail in [false, true] {
                    let name = "\(record.photoID.uuidString)\(thumbnail ? "-t" : "").bite"
                    let data = try await shelf.get(name)
                    try MirrorVault.shared.writeSealed(data, id: record.photoID, thumbnail: thumbnail)
                }
                context.insert(record.shot)
            }
            try context.save()
            markOwned()
            MirrorLog.shared.refresh()
            status = .saved(.now)
            return true
        } catch {
            status = .failed
            return false
        }
    }

    /// Delete all your photos: the shelf too, and the keys in iCloud Keychain.
    func eraseShelf() async {
        if let signingRaw = Keychain.syncedData(for: Self.syncedSigning),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: signingRaw) {
            let shelf = MirrorShelf(signing: key)
            if let names = try? await shelf.list() {
                for name in names { try? await shelf.delete(name) }
            }
        }
        Keychain.setSyncedData(nil, for: Self.syncedPrivate)
        Keychain.setSyncedData(nil, for: Self.syncedSigning)
        status = .idle
    }
}
