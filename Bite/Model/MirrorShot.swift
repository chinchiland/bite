import Foundation
import SwiftData

/// One photo in your mirror. The pixels are never here: they sit encrypted in files of their
/// own (`MirrorFiles`), and this keeps when it was taken, how, and where the body stood, so the
/// next photo can be lined up before a single photo is opened. It lives under `Bite/`, never
/// `Shared/`: the widgets compile `Shared/`, and they must have no way to these photos.
@Model
final class MirrorShot {
    /// Names the photo's two files.
    var photoID = UUID()
    var takenAt = Date.now
    /// One pose for now, the front; here so a side and a back photo are only new rows later.
    var poseRaw = MirrorPose.front.rawValue
    /// Propped on a sink or a shelf, with the front camera, rather than held up to a mirror.
    var proppedUp = false
    /// Picked from the photo library: lined up by what was found in it, never a target.
    var imported = false
    var widthPx = 0
    var heightPx = 0
    /// Your latest weighing from Apple Health when the photo was taken.
    var weightKg: Double?

    // Where you stood, as the live frame measured it the moment the photo was kept (0 to 1 from
    // the top left), so the next photo is aimed before its first frame arrives.
    var rigShoulderY: Double?
    var rigHipY: Double?
    var rigAnkleY: Double?
    var rigCenterX: Double?
    var rollDegrees = 0.0

    // Where the body sits in the kept photo itself, found after it was straightened: what a
    // pair is lined up by.
    var bodyCenterX: Double?
    var bodyShoulderY: Double?
    var bodySpan: Double?

    // The light, so the next photo of the same rig matches it exactly.
    var iso: Double?
    var exposureSeconds: Double?
    var whiteRed: Double?
    var whiteGreen: Double?
    var whiteBlue: Double?
    /// The light could not be held to the first photo's: the room was darker or brighter.
    var lockFailed = false
    /// Brighter (above 0) or darker (below 0) than the first photo when the light couldn't be held.
    var lightDifference = 0.0

    init(photoID: UUID = UUID(), takenAt: Date = .now, proppedUp: Bool = false) {
        self.photoID = photoID
        self.takenAt = takenAt
        self.proppedUp = proppedUp
    }

    var mode: MirrorGuide.Mode { proppedUp ? .propped : .mirror }

    /// The live frame's measures, for lining the next photo up.
    var target: MirrorTarget? {
        guard let rigShoulderY, let rigHipY, let rigCenterX, rigHipY > rigShoulderY else { return nil }
        return MirrorTarget(shoulderY: rigShoulderY, hipY: rigHipY, ankleY: rigAnkleY, centerX: rigCenterX)
    }

    /// Where the body sits in this photo, for lining a pair up.
    var placement: MirrorPlacement? {
        guard let bodyCenterX, let bodyShoulderY, let bodySpan, bodySpan > 0 else { return nil }
        return MirrorPlacement(centerX: bodyCenterX, shoulderY: bodyShoulderY, spanTorso: bodySpan)
    }

    var aspect: Double {
        heightPx > 0 ? Double(widthPx) / Double(heightPx) : 0.75
    }
}

enum MirrorPose: String, Codable {
    case front
}

extension Array where Element == MirrorShot {
    /// The photo every other is lined up with: the oldest of the same rig taken with the camera,
    /// else the oldest of any. Delete a bad first photo and the next one takes its place.
    func anchor(for mode: MirrorGuide.Mode) -> MirrorShot? {
        let sameRig = filter { $0.mode == mode && !$0.imported && $0.target != nil }
        return sameRig.min { $0.takenAt < $1.takenAt }
    }

    /// The oldest photo of all, for a pair.
    var oldest: MirrorShot? { self.min { $0.takenAt < $1.takenAt } }
}
