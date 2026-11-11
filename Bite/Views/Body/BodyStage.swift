import MetalKit
import SwiftUI
import UIKit

/// A body built for the stage, with the key of the numbers it was built from, so the stage can
/// tell whether it still shows the right one.
struct BuiltBody {
    let key: String
    let shape: BodyShape
}

/// One still body to draw: its build as MakeHuman's two sliders, in steps of a 400th so that
/// numbers a hair apart share a picture, its skin and its size in points.
struct BodyPicture: Hashable {
    let sex: Sex
    let muscle: Int
    let weight: Int
    let tone: UInt32
    let width: Int
    let height: Int

    init(frame: BodyFrame, body: BodyNumbers, tone: UInt32, width: CGFloat, height: CGFloat) {
        let sliders = frame.sliders(body)
        sex = frame.sex
        muscle = Int((sliders.muscle * 400).rounded())
        weight = Int((sliders.weight * 400).rounded())
        self.tone = tone
        self.width = Int(width.rounded())
        self.height = Int(height.rounded())
    }
}

/// Everything the screen draws off the main thread: Metal and the body, loaded once; the stage's
/// two bodies, newest numbers first; the still pictures, one at a time, those on screen before
/// the chart's.
@Observable final class BodyStudio {
    enum Phase {
        case loading
        case ready
        /// No Metal or no body in the bundle: flat figures stand in.
        case missing
    }

    enum Lane: Int, CaseIterable {
        case now, goal, chart
    }

    private(set) var phase = Phase.loading
    private(set) var gpu: BodyGPU?
    private(set) var images: [BodyPicture: UIImage] = [:]
    private(set) var failed: Set<BodyPicture> = []
    private(set) var stage: [BuiltBody?] = [nil, nil]

    @ObservationIgnored private var wanted: [[BodyPicture]] = Array(repeating: [], count: Lane.allCases.count)
    @ObservationIgnored private var drawing = false
    private let queue = DispatchQueue(label: "bite.body.pictures", qos: .userInitiated)
    /// Touched only on `queue`.
    @ObservationIgnored private var snapshotter: BodySnapshotter?
    @ObservationIgnored private var stageWanted: [(key: String, sex: Sex, muscle: Double, weight: Double, bare: Double)?] = [nil, nil]
    @ObservationIgnored private var stageBusy = [false, false]
    @ObservationIgnored private var started = false
    @ObservationIgnored var scale: CGFloat = 3

    func start() {
        guard !started else { return }
        started = true
        DispatchQueue.global(qos: .userInitiated).async {
            let gpu = BodyGPU.shared
            DispatchQueue.main.async {
                self.gpu = gpu
                self.phase = gpu == nil ? .missing : .ready
                self.pump()
                for index in self.stage.indices { self.build(index) }
            }
        }
    }

    /// The pictures one part of the screen shows now; the ones it showed before and no longer
    /// does are dropped from the queue.
    func want(_ pictures: [BodyPicture], in lane: Lane) {
        wanted[lane.rawValue] = pictures
        pump()
    }

    /// The stage's bodies: each one is rebuilt only when its numbers changed, and while one is
    /// being built only the newest numbers wait, so a slider dragged fast never piles up work.
    func show(_ bodies: [(key: String, frame: BodyFrame, body: BodyNumbers)]) {
        for (index, item) in bodies.enumerated() where index < stageWanted.count {
            let sliders = item.frame.sliders(item.body)
            stageWanted[index] = (item.key, item.frame.sex, sliders.muscle, sliders.weight, sliders.bare)
            build(index)
        }
    }

    private func build(_ index: Int) {
        guard let gpu, !stageBusy[index], let want = stageWanted[index], stage[index]?.key != want.key else { return }
        stageBusy[index] = true
        DispatchQueue.global(qos: .userInitiated).async {
            let shape = BodyShape(mesh: gpu.mesh, sex: want.sex, muscle: want.muscle, weight: want.weight, bare: want.bare)
            DispatchQueue.main.async {
                self.stage[index] = BuiltBody(key: want.key, shape: shape)
                self.stageBusy[index] = false
                self.build(index)
            }
        }
    }

    private func pump() {
        guard !drawing, let gpu else { return }
        guard let next = wanted.joined().first(where: { images[$0] == nil && !failed.contains($0) }) else {
            trim()
            return
        }
        drawing = true
        let scale = scale
        queue.async {
            if self.snapshotter == nil { self.snapshotter = BodySnapshotter(gpu: gpu) }
            let shape = BodyShape(mesh: gpu.mesh, sex: next.sex, muscle: Double(next.muscle) / 400, weight: Double(next.weight) / 400, bare: nil)
            let image = self.snapshotter?.image(of: shape, tone: next.tone, size: CGSize(width: next.width, height: next.height), scale: scale)
            DispatchQueue.main.async {
                if let image { self.images[next] = image } else { self.failed.insert(next) }
                self.drawing = false
                self.pump()
            }
        }
    }

    /// Keeps the pictures in memory to a few screens' worth.
    private func trim() {
        guard images.count > 160 else { return }
        let keep = Set(wanted.joined())
        for key in images.keys where !keep.contains(key) { images[key] = nil }
    }
}

/// One still body: its picture once drawn, a flat figure where Metal is missing, nothing while it
/// draws. A build no one reaches naturally is dimmed.
struct BodyThumb: View {
    let picture: BodyPicture
    let studio: BodyStudio
    let bmi: Double
    var dim = false

    var body: some View {
        let image = studio.images[picture]
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            } else if studio.phase == .missing || studio.failed.contains(picture) {
                BodyFigureShape(build: BodyFigure.build(bmi: bmi), female: picture.sex == .female)
                    .fill(Theme.ink.opacity(0.55))
                    .aspectRatio(BodyFigure.grid.width / BodyFigure.grid.height, contentMode: .fit)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: CGFloat(picture.width), height: CGFloat(picture.height))
        .opacity(dim ? 0.35 : 1)
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .accessibilityHidden(true)
    }
}

/// The live stage in SwiftUI: an MTKView the renderer draws into, turned by a sideways drag (one
/// up or down still scrolls the page) and faced front again by a double tap.
struct BodyStageView: UIViewRepresentable {
    let gpu: BodyGPU
    let bodies: [BuiltBody?]
    let outfit: BodyOutfit
    let tone: UInt32
    let move: BodyMove
    /// On screen, with the app in front.
    let running: Bool
    /// Reduce Motion: one pose held, drawn only when something changes.
    let still: Bool
    var onTurn: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: BodyStageRenderer(gpu: gpu))
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: gpu.device)
        view.colorPixelFormat = BodyGPU.pixelFormat
        view.depthStencilPixelFormat = BodyGPU.depthFormat
        view.sampleCount = BodyGPU.samples
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator.renderer
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.faceFront(_:)))
        tap.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator, renderer = coordinator.renderer
        coordinator.onTurn = onTurn
        for (index, body) in bodies.enumerated() where index < coordinator.keys.count {
            guard let body, coordinator.keys[index] != body.key else { continue }
            renderer.set(body.shape, at: index)
            coordinator.keys[index] = body.key
        }
        renderer.outfit = outfit
        renderer.tone = tone
        if renderer.director.move != move { renderer.director.set(move) }
        renderer.still = still
        view.enableSetNeedsDisplay = still
        view.isPaused = still || !running
        if still { view.setNeedsDisplay() }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let renderer: BodyStageRenderer
        var keys: [String?] = [nil, nil]
        var onTurn: () -> Void = {}
        weak var view: MTKView?
        private var from: Float = 0

        init(renderer: BodyStageRenderer) {
            self.renderer = renderer
        }

        @objc func pan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                from = renderer.yaw
            case .changed:
                let dx = Float(pan.translation(in: pan.view).x)
                renderer.turn(to: from + dx * 0.9, eased: false)
                if abs(dx) > 8 { onTurn() }
                if renderer.still { view?.setNeedsDisplay() }
            default:
                break
            }
        }

        @objc func faceFront(_ tap: UITapGestureRecognizer) {
            renderer.turn(to: 0, eased: true)
            if renderer.still { view?.setNeedsDisplay() }
        }

        /// Only a sideways drag turns the bodies, so the page still scrolls under a finger.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        /// The page's own scrolling waits for the turn to fail, so a sideways drag never scrolls it.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            recognizer is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

/// The body fat slider: a track with the fats that need more muscle than nature builds striped,
/// a white knob, a tick under the finger at each percent.
struct FatSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Below this body fat a body of this weight carries more muscle than nature builds.
    let natural: Double
    let label: Text

    private static let inset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let inset = Self.inset, width = max(proxy.size.width - inset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, 1)
            let x = { (v: Double) in inset + width * CGFloat(min(max((v - range.lowerBound) / span, 0), 1)) }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Theme.track)
                    .frame(width: width, height: 4)
                    .offset(x: inset, y: 13)
                Stripes()
                    .fill(Theme.ink.opacity(0.32))
                    .frame(width: max(x(natural) - inset, 0), height: 4)
                    .clipShape(Capsule())
                    .offset(x: inset, y: 13)
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                    .offset(x: x(value) - 14, y: 1)
            }
            .frame(width: proxy.size.width, height: 30, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = Double((drag.location.x - inset) / width)
                        let next = (range.lowerBound + fraction * span).rounded()
                        let clamped = min(max(next, range.lowerBound), range.upperBound)
                        if clamped != value { value = clamped }
                    }
            )
        }
        .frame(height: 30)
        .sensoryFeedback(Feel.tick, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: (value / 100).formatted(.percent.precision(.fractionLength(0)))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    /// Thin diagonal stripes, like a hatched part of a ruler.
    private struct Stripes: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                path.move(to: CGPoint(x: x, y: rect.maxY))
                path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                path.addLine(to: CGPoint(x: x + rect.height + 2, y: rect.minY))
                path.addLine(to: CGPoint(x: x + 2, y: rect.maxY))
                path.closeSubpath()
                x += 5
            }
            return path
        }
    }
}
