import AVFoundation
import CoreMotion
import Foundation
import Observation
import UIKit
import Vision

// Your mirror's camera: the back camera on your reflection when you hold the phone up to a
// mirror, the front camera when the phone stands on a sink. Every frame it sees is measured on
// the phone (Vision's body pose) and the numbers are kept only in memory; nothing about a body
// is ever written but where it stood in a photo you kept.

/// A photo's light, so the next photo of the same rig is held to it: two photos in the same
/// bathroom under the same lamp then match, and a change you see is a change in you.
struct MirrorLight: Equatable, Sendable {
    var iso: Double
    var exposureSeconds: Double
    var red: Double
    var green: Double
    var blue: Double
}

/// Finds the person in a frame and measures where they stand.
enum MirrorMeasure {
    /// A live frame, already turned the way the screen shows it. `previous` is where the last
    /// frame's person stood, to keep following the same one.
    static func reading(in buffer: CVPixelBuffer, previous: inout CGPoint?) -> MirrorReading {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .nobody
        }
        let measured = measure(request.results ?? [], previous: &previous)
        var reading = measured.reading
        if let box = measured.box { reading.luma = luma(of: buffer, in: box) }
        return reading
    }

    /// A kept photo, upright: where the body sits in it, for lining up a pair.
    static func placement(in image: CGImage) -> MirrorPlacement? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        var previous: CGPoint?
        guard let body = measure(request.results ?? [], previous: &previous).reading.body else { return nil }
        return MirrorPlacement(centerX: body.centerX, shoulderY: body.shoulderY, spanTorso: body.spanTorso)
    }

    /// The person to guide: the biggest one, then the same one frame after frame, nearest to
    /// where they were. Vision measures from the bottom left; this from the top left.
    private static func measure(_ observations: [VNHumanBodyPoseObservation], previous: inout CGPoint?) -> (reading: MirrorReading, box: CGRect?) {
        struct Person {
            var points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
            var box: CGRect
            var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
        }
        let people: [Person] = observations.compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let seen = points.values.filter { $0.confidence > 0.1 }
            guard !seen.isEmpty else { return nil }
            let xs = seen.map { Double($0.location.x) }
            let ys = seen.map { 1 - Double($0.location.y) }
            let box = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
            return Person(points: points, box: box)
        }
        guard let biggest = people.max(by: { $0.box.width * $0.box.height < $1.box.width * $1.box.height }) else {
            previous = nil
            return (.nobody, nil)
        }
        var person = biggest
        if let previous {
            let area = biggest.box.width * biggest.box.height
            let near = people
                .filter { $0.box.width * $0.box.height > area * 0.5 }
                .min { hypot($0.center.x - previous.x, $0.center.y - previous.y) < hypot($1.center.x - previous.x, $1.center.y - previous.y) }
            if let near { person = near }
        }
        previous = person.center

        func point(_ joint: VNHumanBodyPoseObservation.JointName, _ minimum: Float) -> CGPoint? {
            guard let found = person.points[joint], found.confidence >= minimum else { return nil }
            return CGPoint(x: found.location.x, y: 1 - found.location.y)
        }
        let height = min(max(person.box.height, 0), 1)
        guard let leftShoulder = point(.leftShoulder, 0.3), let rightShoulder = point(.rightShoulder, 0.3) else {
            return (MirrorReading(body: nil, tooClose: false, height: height, luma: nil), person.box)
        }
        guard let leftHip = point(.leftHip, 0.3), let rightHip = point(.rightHip, 0.3) else {
            // The shoulders but not the hips: too close for the body to fit.
            return (MirrorReading(body: nil, tooClose: true, height: height, luma: nil), person.box)
        }
        let shoulderY = Double(leftShoulder.y + rightShoulder.y) / 2
        let hipY = Double(leftHip.y + rightHip.y) / 2
        let centerX = Double(leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4
        var ankleY: Double?
        if let left = point(.leftAnkle, 0.2), let right = point(.rightAnkle, 0.2) {
            ankleY = Double(left.y + right.y) / 2
        }
        let head = [VNHumanBodyPoseObservation.JointName.nose, .leftEye, .rightEye, .leftEar, .rightEar]
            .compactMap { point($0, 0.2)?.y }
            .min()
        let top = head.map { Double($0) - (hipY - shoulderY) * 0.25 } ?? shoulderY - (hipY - shoulderY) * 0.6
        let bottom = ankleY ?? Double(person.box.maxY)
        let body = MirrorBody(shoulderY: shoulderY, hipY: hipY, ankleY: ankleY, centerX: centerX, top: top)
        return (MirrorReading(body: body, tooClose: false, height: min(max(bottom - top, 0), 1), luma: nil), person.box)
    }

    /// How bright the person is, from a grid of pixels inside them: enough to tell a lamp that
    /// changed, and cheap enough for every frame.
    private static func luma(of buffer: CVPixelBuffer, in box: CGRect) -> Double? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        var count = 0.0
        for gridY in 0..<16 {
            for gridX in 0..<16 {
                let x = Int((box.minX + box.width * (Double(gridX) + 0.5) / 16) * Double(width))
                let y = Int((box.minY + box.height * (Double(gridY) + 0.5) / 16) * Double(height))
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let offset = y * row + x * 4
                let blue = Double(pixels[offset])
                let green = Double(pixels[offset + 1])
                let red = Double(pixels[offset + 2])
                total += (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                count += 1
            }
        }
        return count > 0 ? total / count : nil
    }
}

/// Keeping a photo: upright, a small tilt straightened, sized to keep.
enum MirrorDevelop {
    struct Kept: Sendable {
        let jpeg: Data
        let width: Int
        let height: Int
        let placement: MirrorPlacement?
    }

    /// A photo from the camera. Tilts up to six degrees are straightened and cut back to the
    /// photo's own shape; past that it is kept as it was taken.
    static func keep(_ data: Data, roll: Double) -> Kept? {
        guard let photo = UIImage(data: data) else { return nil }
        let longest = max(photo.size.width, photo.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, MirrorVault.photoPixels / longest)
        let drawn = CGSize(width: (photo.size.width * scale).rounded(), height: (photo.size.height * scale).rounded())
        let degrees = abs(roll) <= MirrorLevel.maxDegrees ? roll : 0
        let share = MirrorLevel.keptShare(width: drawn.width, height: drawn.height, degrees: degrees)
        let size = CGSize(width: (drawn.width * share).rounded(), height: (drawn.height * share).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // The phone turned clockwise turns the picture the other way: turning it back
            // clockwise by the same angle levels it.
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: degrees * .pi / 180)
            photo.draw(in: CGRect(x: -drawn.width / 2, y: -drawn.height / 2, width: drawn.width, height: drawn.height))
        }
        return finish(image)
    }

    /// A photo picked from the library, kept as it is.
    static func keep(picked data: Data) -> Kept? {
        guard let image = ImageTools.downsample(data, maxPixel: MirrorVault.photoPixels) else { return nil }
        return finish(image)
    }

    private static func finish(_ image: UIImage) -> Kept? {
        guard let jpeg = image.jpegData(compressionQuality: 0.9), let cgImage = image.cgImage else { return nil }
        return Kept(jpeg: jpeg, width: cgImage.width, height: cgImage.height, placement: MirrorMeasure.placement(in: cgImage))
    }
}

/// The capture session, its outputs and the frames, all on their own queues.
final class MirrorCapture: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "bite.mirror.session")
    private let frameQueue = DispatchQueue(label: "bite.mirror.frames")
    private let photoOutput = AVCapturePhotoOutput()
    private let frameOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var frames = 0
    private var previous: CGPoint?
    private var shutters: [Int64: MirrorShutter] = [:]

    /// The camera in use; read on the main thread once configuring is done.
    private(set) var device: AVCaptureDevice?
    /// Each measured frame, about ten a second, with the frame's width over its height.
    var onReading: (@Sendable (MirrorReading, Double) -> Void)?

    /// The back camera for a mirror, the front one for a propped phone. False when there is no
    /// camera, as on the simulator.
    func configure(front: Bool, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            session.beginConfiguration()
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            if let input { session.removeInput(input) }
            input = nil
            device = nil
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
                  let newInput = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(newInput) else {
                session.commitConfiguration()
                completion(false)
                return
            }
            session.addInput(newInput)
            input = newInput
            device = camera
            if !session.outputs.contains(frameOutput), session.canAddOutput(frameOutput) {
                frameOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                frameOutput.alwaysDiscardsLateVideoFrames = true
                frameOutput.setSampleBufferDelegate(self, queue: frameQueue)
                session.addOutput(frameOutput)
            }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
            // The front camera's photo and frames are mirrored like its preview, so a propped
            // photo reads the same way round as one taken in a mirror, and the marks match.
            for connection in [frameOutput.connection(with: .video), photoOutput.connection(with: .video)].compactMap({ $0 }) where connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
            session.commitConfiguration()
            previous = nil
            if !session.isRunning { session.startRunning() }
            completion(true)
        }
    }

    func start() {
        queue.async { [self] in
            if input != nil, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Frames turned like the screen, so what is measured is what you see.
    func setFrameAngle(_ angle: CGFloat) {
        queue.async { [self] in
            if let connection = frameOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    /// The kept photo turned the way the phone is held.
    func setPhotoAngle(_ angle: CGFloat) {
        queue.async { [self] in
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    /// Holds the light to the first photo's: its exposure and its white balance, within what
    /// this camera can do.
    func holdLight(_ light: MirrorLight) {
        queue.async { [self] in
            guard let device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.custom) {
                let format = device.activeFormat
                let iso = min(max(Float(light.iso), format.minISO), format.maxISO)
                let longest = min(format.maxExposureDuration.seconds, 1.0 / 15)
                let seconds = min(max(light.exposureSeconds, format.minExposureDuration.seconds), longest)
                device.setExposureModeCustom(duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000_000), iso: iso, completionHandler: nil)
            }
            if device.isWhiteBalanceModeSupported(.locked) {
                let top = device.maxWhiteBalanceGain
                func gain(_ value: Double) -> Float { min(max(Float(value), 1), top) }
                let gains = AVCaptureDevice.WhiteBalanceGains(redGain: gain(light.red), greenGain: gain(light.green), blueGain: gain(light.blue))
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
        }
    }

    /// Back to the camera's own light, when the room is too far from the first photo's.
    func releaseLight() {
        queue.async { [self] in
            guard let device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
    }

    /// The light right now, to keep with a photo.
    func readLight(_ completion: @escaping @Sendable (MirrorLight?) -> Void) {
        queue.async { [self] in
            guard let device else {
                completion(nil)
                return
            }
            let gains = device.deviceWhiteBalanceGains
            completion(MirrorLight(
                iso: Double(device.iso),
                exposureSeconds: device.exposureDuration.seconds,
                red: Double(gains.redGain),
                green: Double(gains.greenGain),
                blue: Double(gains.blueGain)
            ))
        }
    }

    /// Takes the photo, with the camera's own processing (night, detail, noise) and its sound.
    func capture(_ completion: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            guard input != nil, session.isRunning else {
                completion(nil)
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            let id = settings.uniqueID
            let shutter = MirrorShutter { [weak self] data in
                completion(data)
                self?.queue.async { self?.shutters[id] = nil }
            }
            // The output doesn't keep its delegate: kept here until the photo is done.
            shutters[id] = shutter
            photoOutput.capturePhoto(with: settings, delegate: shutter)
        }
    }
}

extension MirrorCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frames += 1
        // About ten frames a second is plenty to guide a person standing still; half that in
        // Low Power Mode.
        let every = ProcessInfo.processInfo.isLowPowerModeEnabled ? 6 : 3
        guard frames % every == 0, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let reading = MirrorMeasure.reading(in: buffer, previous: &previous)
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(max(CVPixelBufferGetHeight(buffer), 1))
        onReading?(reading, aspect)
    }
}

/// Waits for one photo, and answers exactly once: with the photo, or with nothing when the
/// capture ended without one, so the shutter is never left waiting.
private final class MirrorShutter: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let done: @Sendable (Data?) -> Void
    private let lock = NSLock()
    private var answered = false

    init(done: @escaping @Sendable (Data?) -> Void) {
        self.done = done
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        answer(error == nil ? photo.fileDataRepresentation() : nil)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        answer(nil)
    }

    private func answer(_ data: Data?) {
        lock.lock()
        let first = !answered
        answered = true
        lock.unlock()
        if first { done(data) }
    }
}

/// The voice of the propped camera: the phone's own voice in your language, ducking any music,
/// and no permission to ask for, since it only speaks.
@MainActor
final class MirrorVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private var active = false

    func say(_ words: String) {
        if !active {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? session.setActive(true)
            active = true
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.language)
        synthesizer.speak(utterance)
    }

    func finish() {
        synthesizer.stopSpeaking(at: .immediate)
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        active = false
    }

    private static var language: String {
        switch AppLanguage.current {
        case "fr": "fr-FR"
        case "es": "es-ES"
        default: "en-GB"
        }
    }
}

/// The camera as the screen sees it: whether it runs, the latest frame's measures, the roll.
@MainActor
@Observable
final class MirrorRig {
    enum Status: Equatable {
        case starting
        case running
        case denied
        case unavailable
    }

    private(set) var status: Status = .starting
    private(set) var reading = MirrorReading.nobody
    /// Bumps with every measured frame, for the guide to follow.
    private(set) var frameNumber = 0
    /// The frames' width over their height.
    private(set) var frameAspect = 0.75
    /// The phone's turn in degrees: 0 upright, positive turned clockwise.
    private(set) var roll = 0.0

    @ObservationIgnored let capture = MirrorCapture()
    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var angleObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var preview: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private let motion = CMMotionManager()

    init() {
        capture.onReading = { [weak self] reading, aspect in
            Task { @MainActor in
                guard let self else { return }
                self.reading = reading
                self.frameAspect = aspect
                self.frameNumber &+= 1
            }
        }
    }

    /// Asks for the camera the first time, then starts the one this rig needs.
    func start(front: Bool) async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        status = .starting
        reading = .nobody
        let ready = await withCheckedContinuation { continuation in
            capture.configure(front: front) { continuation.resume(returning: $0) }
        }
        guard ready else {
            status = .unavailable
            return
        }
        status = .running
        followRotation()
        startMotion()
    }

    func stop() {
        capture.stop()
        motion.stopDeviceMotionUpdates()
    }

    func resume() {
        guard status == .running else { return }
        capture.start()
        startMotion()
    }

    /// The preview layer the screen draws, so the rotation can follow it.
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        preview = layer
        followRotation()
    }

    func takePhoto() async -> Data? {
        await withCheckedContinuation { continuation in
            capture.capture { continuation.resume(returning: $0) }
        }
    }

    func light() async -> MirrorLight? {
        await withCheckedContinuation { continuation in
            capture.readLight { continuation.resume(returning: $0) }
        }
    }

    /// The preview, the frames and the photo turned the way the phone's camera asks, never a
    /// guessed angle: front cameras are mounted differently from one iPhone to the next.
    private func followRotation() {
        guard let device = capture.device, let preview else { return }
        angleObservers = []
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        self.coordinator = coordinator
        angleObservers.append(coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.applyPreview(angle) }
        })
        angleObservers.append(coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            Task { @MainActor in self?.capture.setPhotoAngle(angle) }
        })
    }

    private func applyPreview(_ angle: CGFloat) {
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        capture.setFrameAngle(angle)
    }

    /// The roll, from gravity: 0 upright, positive when the phone turns clockwise.
    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] data, _ in
            guard let gravity = data?.gravity else { return }
            let roll = atan2(gravity.x, -gravity.y) * 180 / .pi
            MainActor.assumeIsolated { self?.roll = roll }
        }
    }
}
