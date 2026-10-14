import AVFoundation
import PhotosUI
import QuartzCore
import SwiftData
import SwiftUI
import UIKit

/// Your mirror's camera. Held up to a mirror (the back camera on your reflection) or propped on
/// a sink (the front camera, two meters away, speaking). From the second photo on, six marks at
/// the edges show where the first photo's shoulders, hips and middle were, each going solid when
/// you match it; one line says the one thing to do; the light is held to the first photo's; and
/// the photo takes itself once you're lined up and still. The shutter works at any moment.
struct MirrorCamera: View {
    /// Your photos so far, newest first, to line the next one up with the first of its rig.
    let shots: [MirrorShot]
    /// The camera closed; true when a photo was kept.
    let onClose: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AppStorage("mirror.speak") private var speaks = true
    @AppStorage("mirror.history") private var historyData = Data()
    @AppStorage("health.asked") private var healthAsked = false
    @AppStorage("health.weightAsked") private var weightAsked = false

    @State private var rig = MirrorRig()
    @State private var mode: MirrorGuide.Mode
    @State private var guide: MirrorGuide
    @State private var output: MirrorGuide.Output
    @State private var keptCount = 0
    @State private var taking = false
    @State private var flash = false
    @State private var picked: PhotosPickerItem?
    @State private var voice = MirrorVoice()
    @State private var lightHeld = false
    @State private var lightFailed = false
    @State private var lightDirection = 0.0
    @State private var lightOffSince: Double?
    @State private var announcedAt = 0.0
    #if DEBUG
    private let fixture = MirrorFixture.camera
    #endif

    init(shots: [MirrorShot], onClose: @escaping (Bool) -> Void) {
        self.shots = shots
        self.onClose = onClose
        // The rig you used last time; on the first photo, the one you chose before.
        var mode: MirrorGuide.Mode = UserDefaults.standard.string(forKey: "mirror.mode") == "propped" ? .propped : .mirror
        if let newest = shots.first(where: { !$0.imported }) { mode = newest.mode }
        #if DEBUG
        if let fixture = MirrorFixture.camera { mode = fixture.mode }
        #endif
        let guide = MirrorGuide(mode: mode, target: shots.anchor(for: mode)?.target)
        _mode = State(initialValue: mode)
        _guide = State(initialValue: guide)
        _output = State(initialValue: MirrorGuide.Output(line: mode == .propped ? .setUp : .fitIn, level: false, marks: MirrorMarks(), countdown: nil, fire: false))
    }

    private var anchor: MirrorShot? { shots.anchor(for: mode) }
    private var target: MirrorTarget? {
        #if DEBUG
        if let fixture { return fixture.target }
        #endif
        return anchor?.target
    }
    private var shownOutput: MirrorGuide.Output {
        #if DEBUG
        if let fixture { return fixture.output }
        #endif
        return output
    }
    private var roll: Double {
        #if DEBUG
        if let fixture { return fixture.roll }
        #endif
        return rig.roll
    }
    private var isLive: Bool {
        #if DEBUG
        if fixture != nil { return true }
        #endif
        return rig.status == .running
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { proxy in
                ZStack {
                    scene
                    guides(in: proxy.size)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if mode == .mirror || !isLive {
                    linePill
                        .padding(.bottom, 24)
                }
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if mode == .propped, isLive {
                proppedCenter
            }

            Color.white
                .opacity(flash ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .task { await startCamera() }
        .onChange(of: rig.frameNumber) { _, _ in tick() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rig.resume() } else { rig.stop() }
        }
        .onChange(of: picked) { _, item in
            Task { await importPicked(item) }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            // The screen may dim and lock again, and nothing keeps listening.
            UIApplication.shared.isIdleTimerDisabled = false
            rig.stop()
            voice.finish()
        }
        .sensoryFeedback(trigger: shownOutput.level) { _, level in level ? Feel.tick : nil }
    }

    // MARK: What is drawn on the camera

    @ViewBuilder private var scene: some View {
        #if DEBUG
        if let fixture {
            MirrorFixtureScene(figure: fixture.figure)
        } else {
            MirrorPreview(rig: rig)
        }
        #else
        MirrorPreview(rig: rig)
        #endif
    }

    /// Four things and nothing else: the first photo's marks (or, before the first photo, the
    /// pose to stand in), the level line, and the one line, drawn elsewhere.
    @ViewBuilder private func guides(in size: CGSize) -> some View {
        if isLive {
            if let target {
                MirrorMarksView(target: target, marks: shownOutput.marks, aspect: rig.frameAspect, size: size)
                    .transition(.opacity)
            } else {
                MirrorFigureShape()
                    .stroke(Color.black.opacity(0.18), lineWidth: 3)
                    .overlay {
                        MirrorFigureShape()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    }
                    .frame(width: size.width * 0.62, height: size.height * 0.66)
                    .position(x: size.width / 2, y: size.height * 0.48)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            MirrorLevelLine(roll: roll, isLevel: shownOutput.level)
                .position(x: size.width / 2, y: size.height / 2)
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(FloatingIconStyle())
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 2) {
                modeChip(.mirror, title: "Mirror")
                modeChip(.propped, title: "Propped up")
            }
            .padding(3)
            .coverGlass(in: Capsule(), onPhoto: true)
        }
    }

    private func modeChip(_ option: MirrorGuide.Mode, title: LocalizedStringKey) -> some View {
        let selected = option == mode
        return Button {
            guard !selected else { return }
            switchMode(to: option)
        } label: {
            Text(title)
                .font(.ui(14, .medium))
                .foregroundStyle(selected ? Color.black : Color.white)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background {
                    if selected { Capsule().fill(.white) }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The one line, held up to the mirror: on dark glass where your eyes already are.
    @ViewBuilder private var linePill: some View {
        switch rig.status {
        case .denied where !isLive:
            HStack(spacing: 10) {
                Text("Bite needs the camera. Allow it in Settings.")
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.ui(15, .semibold))
                .underline()
            }
            .font(.ui(15, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .coverGlass(in: Capsule(), onPhoto: true)
        case .unavailable where !isLive:
            Text("No camera here. Pick a photo instead.")
                .font(.ui(15, .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .coverGlass(in: Capsule(), onPhoto: true)
        default:
            if isLive {
                Text(Self.text(for: shownOutput.line))
                    .font(.ui(17, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .coverGlass(in: Capsule(), onPhoto: true)
                    .contentTransition(.opacity)
                    .animation(Motion.respond, value: shownOutput.line)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// Propped, two meters away: the line in big type in the middle, and the countdown bigger.
    private var proppedCenter: some View {
        Group {
            if let count = shownOutput.countdown {
                Text(verbatim: "\(count)")
                    .font(.number(120, .medium))
                    .foregroundStyle(.white)
                    .frame(width: 190, height: 190)
                    .coverGlass(in: Circle(), onPhoto: true)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Motion.respond, value: count)
            } else {
                Text(Self.text(for: shownOutput.line))
                    .font(.number(34, .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .coverGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), onPhoto: true)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
                    .animation(Motion.respond, value: shownOutput.line)
            }
        }
        .allowsHitTesting(false)
    }

    /// Your photos on the left, the shutter in the middle, the voice on the right when propped.
    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $picked, matching: .images) {
                VStack(spacing: 5) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19, weight: .regular))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                    Text("Gallery")
                        .font(.ui(12, .medium))
                }
                .foregroundStyle(.white)
            }
            .frame(width: 72)
            .accessibilityLabel("Choose a photo")

            Spacer()

            Button {
                take(byItself: false)
            } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 66, height: 66)
                    .padding(5)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                    .opacity(taking || !isLive ? 0.4 : 1)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .disabled(taking || !isLive)
            .accessibilityLabel("Take the photo")

            Spacer()

            Group {
                if mode == .propped {
                    Button {
                        speaks.toggle()
                        if !speaks { voice.finish() }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: speaks ? "speaker.wave.2.fill" : "speaker.slash")
                                .font(.system(size: 18, weight: .regular))
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                                .contentTransition(.symbolEffect(.replace))
                            Text("Voice")
                                .font(.ui(12, .medium))
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .accessibilityLabel("Speak the guidance")
                    .accessibilityValue(speaks ? Text("On") : Text("Off"))
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(width: 72)
        }
        .padding(.top, 4)
        // Propped, nobody reaches these from two meters away: they step back.
        .opacity(mode == .propped && shownOutput.countdown != nil ? 0.4 : 1)
    }

    // MARK: The guide

    static func text(for line: MirrorLine) -> String {
        switch line {
        case .setUp: String(localized: "Stand it up and step back")
        case .fitIn: String(localized: "Fit yourself in the frame")
        case .stepBack: String(localized: "Step back")
        case .stepCloser: String(localized: "Step closer")
        case .yourSpot: String(localized: "This is your spot")
        case .level: String(localized: "Level the phone")
        case .holdStill: String(localized: "Hold still")
        case .ready: String(localized: "Ready")
        case .takingNow: String(localized: "Taking it now")
        case .kept: String(localized: "Kept. Take another?")
        }
    }

    private func startCamera() async {
        #if DEBUG
        if fixture != nil { return }
        #endif
        await rig.start(front: mode == .propped)
        holdLight()
    }

    private func switchMode(to option: MirrorGuide.Mode) {
        withAnimation(Motion.respond) { mode = option }
        UserDefaults.standard.set(option == .propped ? "propped" : "mirror", forKey: "mirror.mode")
        guide = MirrorGuide(mode: option, target: shots.anchor(for: option)?.target)
        output = MirrorGuide.Output(line: option == .propped ? .setUp : .fitIn, level: false, marks: MirrorMarks(), countdown: nil, fire: false)
        lightHeld = false
        lightFailed = false
        lightOffSince = nil
        voice.finish()
        Task {
            await rig.start(front: option == .propped)
            holdLight()
        }
    }

    /// Holds the light to the first photo's, when it was kept from this rig.
    private func holdLight() {
        guard rig.status == .running, let anchor, let iso = anchor.iso, let seconds = anchor.exposureSeconds,
              let red = anchor.whiteRed, let green = anchor.whiteGreen, let blue = anchor.whiteBlue else { return }
        rig.capture.holdLight(MirrorLight(iso: iso, exposureSeconds: seconds, red: red, green: green, blue: blue))
        lightHeld = true
    }

    /// Each measured frame: the guide's line, the voice and the photo when it says so.
    private func tick() {
        let now = CACurrentMediaTime()
        let next = guide.update(rig.reading, roll: rig.roll, now: now)
        watchLight(now: now)
        if next.line != output.line || next.countdown != output.countdown {
            say(next, previous: output, now: now)
        }
        output = next
        if next.fire { take(byItself: true) }
    }

    /// The first photo's light, until the room is too far from it: a person too dark or too
    /// bright for two seconds lets the camera find its own light, and the photo remembers it.
    private func watchLight(now: Double) {
        guard lightHeld, let luma = rig.reading.luma else { return }
        guard luma < 0.10 || luma > 0.90 else {
            lightOffSince = nil
            return
        }
        let since = lightOffSince ?? now
        lightOffSince = since
        guard now - since >= 2 else { return }
        rig.capture.releaseLight()
        lightHeld = false
        lightFailed = true
        lightDirection = luma < 0.10 ? -1 : 1
    }

    /// Propped, the line out loud when it changes, and three, two, one; VoiceOver hears the line
    /// held, the guide being the whole screen.
    private func say(_ next: MirrorGuide.Output, previous: MirrorGuide.Output, now: Double) {
        let words: String
        if let count = next.countdown {
            words = "\(count)"
        } else {
            words = Self.text(for: next.line)
        }
        if mode == .propped, speaks {
            voice.say(words)
        }
        if UIAccessibility.isVoiceOverRunning, now - announcedAt >= 1.5 {
            announcedAt = now
            AccessibilityNotification.Announcement(words).post()
        }
    }

    // MARK: Keeping a photo

    /// Takes and keeps a photo: no Keep or Retake to stand in front of, it is kept, and the
    /// line says so. Delete with Undo is in your mirror.
    private func take(byItself: Bool) {
        guard !taking, isLive else { return }
        #if DEBUG
        if fixture != nil { return }
        #endif
        taking = true
        if !byItself { guide.kept(now: CACurrentMediaTime()) }
        let roll = rig.roll
        let body = rig.reading.body
        let failed = lightFailed
        let direction = lightDirection
        let propped = mode == .propped
        pulse()
        Task {
            let light = await rig.light()
            guard let data = await rig.takePhoto() else {
                failedToKeep()
                return
            }
            let weight = await latestWeight()
            let developed = await Task.detached(priority: .userInitiated) {
                MirrorDevelop.keep(data, roll: roll)
            }.value
            guard let developed else {
                failedToKeep()
                return
            }
            let shot = MirrorShot(proppedUp: propped)
            shot.rigShoulderY = body?.shoulderY
            shot.rigHipY = body?.hipY
            shot.rigAnkleY = body?.ankleY
            shot.rigCenterX = body?.centerX
            shot.rollDegrees = roll
            shot.iso = light?.iso
            shot.exposureSeconds = light?.exposureSeconds
            shot.whiteRed = light?.red
            shot.whiteGreen = light?.green
            shot.whiteBlue = light?.blue
            shot.lockFailed = failed
            shot.lightDifference = direction
            guard await keep(developed, as: shot, weight: weight) else {
                failedToKeep()
                return
            }
            if propped, speaks { voice.say(String(localized: "Kept")) } else { Feel.play(.click) }
            taking = false
        }
    }

    /// The photo didn't come, or couldn't be kept: nothing says Kept, and the guide starts over
    /// so the next photo can still take itself.
    private func failedToKeep() {
        taking = false
        Feel.play(.failed)
        guide = MirrorGuide(mode: mode, target: shots.anchor(for: mode)?.target)
        output = MirrorGuide.Output(line: mode == .propped ? .setUp : .fitIn, level: false, marks: MirrorMarks(), countdown: nil, fire: false)
    }

    /// A photo picked from the library: kept as it is, on the day it was taken.
    private func importPicked(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        picked = nil
        taking = true
        let date = ImageTools.originalDate(of: data) ?? .now
        let developed = await Task.detached(priority: .userInitiated) {
            MirrorDevelop.keep(picked: data)
        }.value
        guard let developed else {
            taking = false
            Feel.play(.failed)
            return
        }
        let shot = MirrorShot(takenAt: date, proppedUp: mode == .propped)
        shot.imported = true
        let kept = await keep(developed, as: shot, weight: nil)
        if kept { Feel.play(.click) }
        taking = false
    }

    /// Writes the photo's files, then its row. False when the files couldn't be written.
    private func keep(_ developed: MirrorDevelop.Kept, as shot: MirrorShot, weight: Double?) async -> Bool {
        let id = shot.photoID
        do {
            try await Task.detached(priority: .userInitiated) {
                try MirrorVault.shared.write(jpeg: developed.jpeg, id: id)
            }.value
        } catch {
            Feel.play(.failed)
            return false
        }
        shot.widthPx = developed.width
        shot.heightPx = developed.height
        shot.bodyCenterX = developed.placement?.centerX
        shot.bodyShoulderY = developed.placement?.shoulderY
        shot.bodySpan = developed.placement?.spanTorso
        shot.weightKg = weight
        context.insert(shot)
        try? context.save()
        keptCount += 1
        var history = (try? JSONDecoder().decode(MirrorHistory.self, from: historyData)) ?? MirrorHistory()
        history.took()
        historyData = (try? JSONEncoder().encode(history)) ?? Data()
        MirrorLog.shared.refresh()
        Task { await MirrorKeep.shared.sync() }
        return true
    }

    /// Your latest weighing from Apple Health, for the line under the photo.
    private func latestWeight() async -> Double? {
        #if DEBUG || BITE_DEMO
        if BiteStore.isDemo { return DemoData.weights().last?.kilograms }
        #endif
        guard healthAsked, weightAsked, HealthActivity.isAvailable else { return nil }
        return await HealthActivity.shared.weights(days: 3).last?.kilograms
    }

    /// A soft white flash with the shutter's sound: at two meters, the sign it happened.
    private func pulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeIn(duration: 0.3)) { flash = false }
        }
    }

    private func close() {
        rig.stop()
        voice.finish()
        onClose(keptCount > 0)
    }
}

/// The camera's own picture, filling the screen.
private struct MirrorPreview: UIViewRepresentable {
    let rig: MirrorRig

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = rig.capture.session
        view.previewLayer.videoGravity = .resizeAspectFill
        rig.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class above makes this always true.
            layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
        }
    }
}

/// Where the first photo's shoulders, hips and ankles were, as short marks at both edges of the
/// screen: readable at arm's length and from two meters, and nothing an arm or a phone in the
/// picture can break. Each grows and goes solid when you match it. Left and right need no mark:
/// the comparison lines the two photos up sideways on its own.
struct MirrorMarksView: View {
    let target: MirrorTarget
    let marks: MirrorMarks
    /// The camera frame's width over its height, filled to the screen.
    let aspect: Double
    let size: CGSize

    var body: some View {
        ZStack {
            row(target.shoulderY, solid: marks.shoulders)
            row(target.hipY, solid: marks.hips)
            if let ankle = target.ankleY {
                row(ankle, solid: marks.ankles)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(Motion.respond, value: marks)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ y: Double, solid: Bool) -> some View {
        let screenY = point(0.5, y).y
        return ZStack {
            MirrorTick(solid: solid)
                .frame(width: 60, alignment: .leading)
                .position(x: 30, y: screenY)
            MirrorTick(solid: solid)
                .frame(width: 60, alignment: .trailing)
                .position(x: size.width - 30, y: screenY)
        }
    }

    /// A point of the camera frame on the screen, which shows the frame filled to its edges.
    private func point(_ x: Double, _ y: Double) -> CGPoint {
        guard size.height > 0, aspect > 0 else { return CGPoint(x: x * size.width, y: y * size.height) }
        let screen = size.width / size.height
        if aspect > screen {
            let shown = size.height * aspect
            return CGPoint(x: x * shown - (shown - size.width) / 2, y: y * size.height)
        }
        let shown = size.width / aspect
        return CGPoint(x: x * size.width, y: y * shown - (shown - size.height) / 2)
    }
}

/// One mark: a fine white line over a soft dark one, so it reads on a white bathroom wall.
/// Matched, it grows from the edge and goes solid, a change of shape and not only of light.
private struct MirrorTick: View {
    let solid: Bool

    var body: some View {
        let length: CGFloat = solid ? 52 : 30
        let weight: CGFloat = solid ? 3 : 2
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.25))
                .frame(width: length + 2, height: weight + 2)
            Capsule()
                .fill(Color.white.opacity(solid ? 1 : 0.6))
                .frame(width: length, height: weight)
        }
    }
}

/// The level, Apple's own way: a short line at each side and the horizon between them, which
/// turns with the phone and joins them, solid, when the phone is level.
struct MirrorLevelLine: View {
    let roll: Double
    let isLevel: Bool

    var body: some View {
        HStack(spacing: 0) {
            Capsule().frame(width: 24, height: 1.5)
            Color.clear.frame(width: 8, height: 1)
            Capsule()
                .frame(width: 40, height: 1.5)
                .rotationEffect(.degrees(isLevel ? 0 : -roll))
            Color.clear.frame(width: 8, height: 1)
            Capsule().frame(width: 24, height: 1.5)
        }
        .foregroundStyle(Color.white.opacity(isLevel ? 1 : 0.45))
        .background {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 108, height: 4)
                .opacity(isLevel ? 1 : 0)
        }
        .animation(Motion.respond, value: isLevel)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(isLevel ? Text("Level") : Text("Not level"))
    }
}
