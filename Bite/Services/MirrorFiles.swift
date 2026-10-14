import CryptoKit
import Foundation
import LocalAuthentication
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Your mirror's photos: encrypted files in the app's own folder, opened only behind Face ID or
// your passcode, never in iCloud, never in the camera roll, never sent anywhere.
//
// Each photo is sealed to a public key, so the camera can keep a photo without asking who you
// are (Face ID can't see someone two meters away); only opening one needs the private key, which
// the Keychain keeps on this phone behind Face ID or your passcode. Deleting the key is deleting
// the photos: what stays in an old backup can never be opened again.
//
// Photos are kept at 1600 pixels, more than the 1000 of a food photo, because a comparison zooms.

/// A photo from your mirror, decoded for the screen. Only this file reaches the image inside,
/// so no other code can hand a body photo to anything that sends pictures away: the photo
/// estimate takes `Data` or a `UIImage`, never this.
struct MirrorPicture {
    fileprivate let ui: UIImage

    var image: Image { Image(uiImage: ui) }
    var aspect: Double { ui.size.height > 0 ? ui.size.width / ui.size.height : 0.75 }
}

/// The keys and the files.
final class MirrorVault: @unchecked Sendable {
    static let shared = MirrorVault()

    enum Failure: Error {
        case noKey
        case locked
        case damaged
    }

    static let photoPixels: CGFloat = 1600
    static let thumbnailPixels: CGFloat = 320

    private static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    private static let info = Data("Bite mirror 1".utf8)
    private static let magic = Data("BM1".utf8)
    private static let privateAccount = "mirror.private"
    private static let publicAccount = "mirror.public"

    private let lock = NSLock()
    private var privateKey: P256.KeyAgreement.PrivateKey?
    private let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()
    #if DEBUG
    /// Drawn stand-ins for the screenshots, which have no camera, no body and no Face ID.
    private var fixtures: [UUID: UIImage] = [:]
    private var fixturesOn = false
    #endif

    // MARK: Keys

    /// Both keys exist: photos can be kept and opened. Removing the phone's passcode makes iOS
    /// delete the private key behind it; asked without a prompt, so it never shows Face ID.
    var hasKeys: Bool {
        #if DEBUG
        if fixturesOn { return true }
        #endif
        return Keychain.data(for: Self.publicAccount) != nil && Keychain.exists(Self.privateAccount)
    }

    var isUnlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
        if fixturesOn { return true }
        #endif
        return privateKey != nil
    }

    /// Makes the pair, the private half behind Face ID or your passcode when `protected`. False
    /// when the Keychain wouldn't keep it; a phone with no passcode keeps it unprotected, and
    /// `protected` comes back false.
    func createKeys(protected: Bool) -> (made: Bool, protected: Bool) {
        let key = P256.KeyAgreement.PrivateKey()
        var isProtected = protected
        var saved = Keychain.setData(key.rawRepresentation, for: Self.privateAccount, protected: protected)
        if !saved && protected {
            saved = Keychain.setData(key.rawRepresentation, for: Self.privateAccount, protected: false)
            isProtected = false
        }
        guard saved, Keychain.setData(key.publicKey.rawRepresentation, for: Self.publicAccount, protected: false) else {
            Keychain.setData(nil, for: Self.privateAccount, protected: false)
            return (false, false)
        }
        lock.lock()
        privateKey = key
        lock.unlock()
        return (true, isProtected)
    }

    /// Opens the private key for this session. Pass the context Face ID was just asked through,
    /// so the Keychain doesn't ask a second time. Never on the main thread: an unanswered prompt
    /// holds the thread until it is answered.
    func unlock(context: LAContext?) -> Bool {
        if isUnlocked { return true }
        guard let raw = Keychain.data(for: Self.privateAccount, context: context),
              let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: raw) else { return false }
        lock.lock()
        privateKey = key
        lock.unlock()
        return true
    }

    /// Forgets the private key and the decoded thumbnails, so opening the mirror asks again.
    func lockNow() {
        lock.lock()
        privateKey = nil
        lock.unlock()
        thumbnails.removeAllObjects()
    }

    /// Moves the private key behind Face ID, or out from behind it. The Keychain can't change an
    /// item's protection in place, so it is read, removed and written again; if writing fails
    /// the old one is put back. Needs the mirror unlocked.
    func setProtected(_ protected: Bool) -> Bool {
        lock.lock()
        let key = privateKey
        lock.unlock()
        guard let key else { return false }
        Keychain.setData(nil, for: Self.privateAccount, protected: false)
        if Keychain.setData(key.rawRepresentation, for: Self.privateAccount, protected: protected) { return true }
        Keychain.setData(key.rawRepresentation, for: Self.privateAccount, protected: !protected)
        return false
    }

    // MARK: Files

    func url(for id: UUID, thumbnail: Bool) -> URL {
        MirrorStore.folder.appending(path: "\(id.uuidString)\(thumbnail ? "-t" : "").bite")
    }

    /// Seals a kept photo and its thumbnail into their files, readable only with the private
    /// key, fully protected while the phone is locked. Needs no unlocking.
    func write(jpeg: Data, id: UUID) throws {
        guard let publicRaw = Keychain.data(for: Self.publicAccount),
              let publicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: publicRaw) else { throw Failure.noKey }
        guard let small = ImageTools.downsample(jpeg, maxPixel: Self.thumbnailPixels),
              let thumbnail = small.jpegData(compressionQuality: 0.8) else { throw Failure.damaged }
        MirrorStore.prepareFolder()
        try Self.seal(jpeg, to: publicKey).write(to: url(for: id, thumbnail: false), options: [.atomic, .completeFileProtection])
        try Self.seal(thumbnail, to: publicKey).write(to: url(for: id, thumbnail: true), options: [.atomic, .completeFileProtection])
    }

    /// A photo decoded at most `maxPixel` on its long side; the thumbnail is cached.
    func picture(_ id: UUID, thumbnail: Bool, maxPixel: CGFloat) -> MirrorPicture? {
        let cacheKey = "\(id.uuidString)-\(thumbnail)-\(Int(maxPixel))" as NSString
        if let cached = thumbnails.object(forKey: cacheKey) { return MirrorPicture(ui: cached) }
        #if DEBUG
        lock.lock()
        let fixture = fixtures[id]
        lock.unlock()
        if let fixture {
            return MirrorPicture(ui: ImageTools.fitted(fixture, maxPixel: maxPixel))
        }
        #endif
        guard let data = try? open(id, thumbnail: thumbnail),
              let image = ImageTools.downsample(data, maxPixel: maxPixel) else { return nil }
        if thumbnail { thumbnails.setObject(image, forKey: cacheKey) }
        return MirrorPicture(ui: image)
    }

    /// The photo's JPEG, opened with the private key.
    private func open(_ id: UUID, thumbnail: Bool) throws -> Data {
        lock.lock()
        let key = privateKey
        lock.unlock()
        guard let key else { throw Failure.locked }
        let sealed = try Data(contentsOf: url(for: id, thumbnail: thumbnail))
        return try Self.open(sealed, with: key)
    }

    /// Both files of a photo, gone.
    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id, thumbnail: false))
        try? FileManager.default.removeItem(at: url(for: id, thumbnail: true))
    }

    /// Every photo file and the key that opens them. From this moment any copy anywhere, in an
    /// old backup or on a worn flash page, is noise. The store's rows go first (`MirrorErase`).
    func eraseAll() {
        lockNow()
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: MirrorStore.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "bite" {
            try? manager.removeItem(at: file)
        }
        Keychain.setData(nil, for: Self.privateAccount, protected: false)
        Keychain.setData(nil, for: Self.publicAccount, protected: false)
        clearExports()
    }

    // MARK: Export

    private static var exportFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Mirror-export", directoryHint: .isDirectory)
    }

    /// A plain copy of one photo for the share sheet, named by its day. It leaves Bite's
    /// protection, so it is written to the temporary folder and cleared when the mirror closes.
    func exportCopy(_ id: UUID, takenAt: Date) throws -> URL {
        let data = try open(id, thumbnail: false)
        let folder = Self.exportFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let day = takenAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let url = folder.appending(path: "Mirror \(day) \(id.uuidString.prefix(4)).jpg")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func clearExports() {
        try? FileManager.default.removeItem(at: Self.exportFolder)
    }

    // MARK: Sealing

    /// "BM1", the length of the one-time key, the key, then the sealed photo.
    private static func seal(_ plain: Data, to recipient: P256.KeyAgreement.PublicKey) throws -> Data {
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: suite, info: info)
        let body = try sender.seal(plain)
        let encapsulated = sender.encapsulatedKey
        var out = magic
        out.append(UInt8(encapsulated.count >> 8))
        out.append(UInt8(encapsulated.count & 0xFF))
        out.append(encapsulated)
        out.append(body)
        return out
    }

    private static func open(_ sealed: Data, with key: P256.KeyAgreement.PrivateKey) throws -> Data {
        let bytes = [UInt8](sealed)
        guard bytes.count > 5, Data(bytes[0..<3]) == magic else { throw Failure.damaged }
        let length = Int(bytes[3]) << 8 | Int(bytes[4])
        guard bytes.count > 5 + length else { throw Failure.damaged }
        let encapsulated = Data(bytes[5..<(5 + length)])
        let body = Data(bytes[(5 + length)...])
        var recipient = try HPKE.Recipient(privateKey: key, ciphersuite: suite, info: info, encapsulatedKey: encapsulated)
        return try recipient.open(body)
    }

    #if DEBUG
    func useFixtures(_ images: [UUID: UIImage]) {
        lock.lock()
        fixtures = images
        fixturesOn = true
        lock.unlock()
    }
    #endif
}

/// Opening your mirror: Face ID or the passcode when you asked for it, then the key, with no
/// second prompt. A phone with no passcode has nothing to ask with, and opens.
enum MirrorLock {
    @MainActor static func open(faceID: Bool) async -> Bool {
        if MirrorVault.shared.isUnlocked { return true }
        var context: LAContext?
        if faceID {
            let auth = LAContext()
            do {
                guard try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Open your mirror")) else { return false }
                context = auth
            } catch let error as LAError where error.code == .passcodeNotSet {
                context = nil
            } catch {
                return false
            }
        }
        let asked = AskedContext(context: context)
        return await Task.detached(priority: .userInitiated) {
            MirrorVault.shared.unlock(context: asked.context)
        }.value
    }

    /// The context Face ID was asked through, handed to the Keychain on another thread.
    private struct AskedContext: @unchecked Sendable {
        let context: LAContext?
    }
}

/// Delete all your photos: the rows, the files and the key, then the mirror starts over with its
/// promise. Kept apart from the vault so the store is never pulled from under an open container.
enum MirrorErase {
    @MainActor static func everything() {
        let context = MirrorStore.container.mainContext
        if let shots = try? context.fetch(FetchDescriptor<MirrorShot>()) {
            for shot in shots { context.delete(shot) }
            try? context.save()
        }
        MirrorVault.shared.eraseAll()
        let defaults = UserDefaults.standard
        for key in ["mirror.consented", "mirror.history", "mirror.longGap"] {
            defaults.removeObject(forKey: key)
        }
        MirrorLog.shared.refresh()
    }
}

/// One photo for the share sheet, decrypted only when the share sheet asks for it.
struct MirrorFile: Transferable {
    let id: UUID
    let takenAt: Date

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { file in
            SentTransferredFile(try MirrorVault.shared.exportCopy(file.id, takenAt: file.takenAt))
        }
    }
}
