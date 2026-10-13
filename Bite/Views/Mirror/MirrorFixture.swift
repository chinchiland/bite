#if DEBUG
import SwiftData
import SwiftUI
import UIKit

/// Your mirror for the simulator's screenshots, which have no camera and no body: the camera's
/// guide set by `-mirror.guide back|ready|first|propped`, and drawn stand-ins for the photos,
/// a figure on a wall, never a photo of anyone. Debug builds only; Bite Demo keeps no photos.
enum MirrorFixture {
    struct Camera {
        let mode: MirrorGuide.Mode
        let target: MirrorTarget?
        let output: MirrorGuide.Output
        let roll: Double
        /// Where the figure stands in the frame: its middle, and its height from the shoulders
        /// to the ankles as a share of the frame.
        let figure: (x: Double, shoulderY: Double, span: Double)
    }

    /// The first photo's rig the fixtures line up with.
    static let target = MirrorTarget(shoulderY: 0.27, hipY: 0.52, ankleY: nil, centerX: 0.5)

    static let camera: Camera? = {
        guard let guide = UserDefaults.standard.string(forKey: "mirror.guide") else { return nil }
        switch guide {
        case "back":
            return Camera(
                mode: .mirror, target: target,
                output: .init(line: .stepBack, level: false, marks: MirrorMarks(shoulders: true, hips: false, ankles: false, center: false), countdown: nil, fire: false),
                roll: 4, figure: (x: 0.46, shoulderY: 0.25, span: 0.80))
        case "ready":
            return Camera(
                mode: .mirror, target: target,
                output: .init(line: .ready, level: true, marks: MirrorMarks(shoulders: true, hips: true, ankles: false, center: true), countdown: nil, fire: false),
                roll: 0, figure: (x: 0.5, shoulderY: 0.27, span: 0.62))
        case "propped":
            return Camera(
                mode: .propped, target: MirrorTarget(shoulderY: 0.24, hipY: 0.47, ankleY: 0.86, centerX: 0.5),
                output: .init(line: .ready, level: true, marks: MirrorMarks(shoulders: true, hips: true, ankles: true, center: true), countdown: 2, fire: false),
                roll: 0, figure: (x: 0.5, shoulderY: 0.24, span: 0.62))
        default:
            return Camera(
                mode: .mirror, target: nil,
                output: .init(line: .stepBack, level: true, marks: MirrorMarks(), countdown: nil, fire: false),
                roll: 0, figure: (x: 0.5, shoulderY: 0.3, span: 0.7))
        }
    }()

    /// What `-screen` asks of your mirror: `mirror` (four photos), `mirror.pair`, `mirror.empty`,
    /// `mirror.promise`, `mirror.camera` (with `-mirror.guide`) and `mirror.ask` (Today, four
    /// weeks on). Returns the sheet to open, if any.
    @MainActor static func open(_ screen: String) -> HomeSheet? {
        let context = MirrorStore.container.mainContext
        let defaults = UserDefaults.standard
        switch screen {
        case "mirror", "mirror.pair":
            seedShots(context)
            defaults.set(true, forKey: "mirror.consented")
            return .mirror(false)
        case "mirror.empty":
            MirrorVault.shared.useFixtures([:])
            defaults.set(true, forKey: "mirror.consented")
            return .mirror(false)
        case "mirror.promise":
            defaults.set(false, forKey: "mirror.consented")
            return .mirror(false)
        case "mirror.camera":
            MirrorVault.shared.useFixtures([:])
            defaults.set(true, forKey: "mirror.consented")
            return .mirror(true)
        case "mirror.ask":
            seedShots(context, count: 2, newestDaysAgo: 29)
            defaults.set(true, forKey: "mirror.consented")
            MirrorLog.shared.refresh()
            return nil
        default:
            return nil
        }
    }

    /// Photos a few weeks apart, the light and the framing a little different each time, as
    /// drawn stand-ins in the mirror's own store (in memory, as `-demo` is).
    @MainActor static func seedShots(_ context: ModelContext, count: Int = 4, newestDaysAgo: Int = 2) {
        let calendar = Calendar.current
        let torsoShare = Double((MirrorFigure.hipY - MirrorFigure.shoulderY) / (MirrorFigure.ankleY - MirrorFigure.shoulderY))
        var images: [UUID: UIImage] = [:]
        let weights = [71.4, 70.8, 70.2, 69.8]
        let frames: [(x: Double, shoulderY: Double, span: Double, light: Double)] = [
            (0.47, 0.25, 0.66, 0.0), (0.52, 0.27, 0.62, 0.05), (0.5, 0.26, 0.64, -0.04), (0.49, 0.27, 0.63, 0.02),
        ]
        for index in 0..<count {
            let days = (count - 1 - index) * 28 + newestDaysAgo
            let shot = MirrorShot(takenAt: calendar.date(byAdding: .day, value: -days, to: .now) ?? .now, proppedUp: false)
            let frame = frames[index % frames.count]
            shot.widthPx = 1200
            shot.heightPx = 1600
            shot.weightKg = weights[index % weights.count]
            shot.rigShoulderY = 0.27
            shot.rigHipY = 0.52
            shot.rigCenterX = 0.5
            shot.bodyCenterX = frame.x
            shot.bodyShoulderY = frame.shoulderY
            shot.bodySpan = frame.span * torsoShare
            shot.lockFailed = index == count - 1
            shot.lightDifference = -1
            context.insert(shot)
            images[shot.photoID] = photo(x: frame.x, shoulderY: frame.shoulderY, span: frame.span, light: frame.light)
        }
        try? context.save()
        MirrorVault.shared.useFixtures(images)
    }

    /// A drawn stand-in for a photo: a warm wall, a floor, and the figure, filled.
    @MainActor static func photo(x: Double, shoulderY: Double, span: Double, light: Double) -> UIImage {
        let renderer = ImageRenderer(content: MirrorFixtureScene(figure: (x: x, shoulderY: shoulderY, span: span), light: light)
            .frame(width: 600, height: 800))
        renderer.scale = 2
        return renderer.uiImage ?? UIImage()
    }
}

/// The wall, the floor and the figure, standing where a fixture says.
struct MirrorFixtureScene: View {
    let figure: (x: Double, shoulderY: Double, span: Double)
    var light = 0.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The figure's shoulders to ankles fill `span` of the height.
            let gridSpan = MirrorFigure.ankleY - MirrorFigure.shoulderY
            let scale = size.height * CGFloat(figure.span) / gridSpan
            let width = MirrorFigure.grid.width * scale
            let height = MirrorFigure.grid.height * scale
            let top = size.height * CGFloat(figure.shoulderY) - MirrorFigure.shoulderY * scale
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(red: 0.86 + light, green: 0.84 + light, blue: 0.80 + light), Color(red: 0.74 + light, green: 0.71 + light, blue: 0.66 + light)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(Color(red: 0.62 + light, green: 0.58 + light, blue: 0.53 + light))
                    .frame(height: size.height * 0.16)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                MirrorFigureShape()
                    .fill(Color(red: 0.42 + light, green: 0.39 + light, blue: 0.36 + light))
                    .frame(width: width, height: height)
                    .offset(x: size.width * CGFloat(figure.x) - width / 2, y: top)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}
#endif
