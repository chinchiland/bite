import SwiftUI
import AVFoundation
import PhotosUI
import UIKit
import VisionKit

/// What the camera is looking for.
enum ScanMode: String, CaseIterable, Identifiable {
    case food
    case barcode
    case label

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .food: "Scan food"
        case .barcode: "Barcode"
        case .label: "Food label"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .barcode: "barcode.viewfinder"
        case .label: "tag"
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .food: "Fit your plate in the frame"
        case .barcode: "Point at a barcode"
        case .label: "Fit the nutrition label in the frame"
        }
    }

    var takesPhoto: Bool { self != .barcode }
}

/// Full screen camera. A barcode opens its product; a photo of a plate or a label goes to
/// Claude for an estimate. Both end in one tap to add.
struct ScannerView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("scan.mode") private var modeRaw = ScanMode.barcode.rawValue

    @State private var camera: CameraState = .checking
    @State private var phase: Phase = .scanning
    @State private var found: Food?
    @State private var quickAdd: QuickAddDraft?
    @State private var photo: CapturedPhoto?
    @State private var typing = false
    @State private var typedCode = ""
    @State private var torchOn = false
    @State private var lastCode = ""
    @State private var resumedAt = Date.distantPast
    @State private var scans = 0
    @State private var capturing = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var control = ScannerControl()

    enum CameraState {
        case checking
        case ready
        case denied
        case unavailable
    }

    enum Phase: Equatable {
        case scanning
        case looking(String)
        case notFound(String)
        case noNutrition(code: String, name: String)
        case failed(String)
    }

    /// A photo on its way to Claude.
    struct CapturedPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let isLabel: Bool
        /// When a photo picked from the library was taken, so lunch logged tonight stays lunch.
        var takenAt: Date? = nil
    }

    private var mode: ScanMode { ScanMode(rawValue: modeRaw) ?? .barcode }

    private var isScanning: Bool {
        mode == .barcode && phase == .scanning && found == nil && quickAdd == nil && photo == nil && !typing
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera == .ready {
                BarcodeScanner(
                    isScanning: isScanning || (mode.takesPhoto && photo == nil),
                    control: control,
                    onCode: { code in
                        if mode == .barcode { lookUp(code) }
                    },
                    onFailure: { camera = .unavailable }
                )
                .ignoresSafeArea()
            }
            Viewfinder(mode: mode)
            VStack(spacing: 14) {
                topBar
                Spacer()
                statusPill
                modeTiles
                controls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .environment(\.colorScheme, .dark)
        }
        .task { camera = await CameraState.check() }
        .onDisappear { if torchOn { setTorch(false) } }
        .sensoryFeedback(Feel.click, trigger: scans)
        .onChange(of: pickedPhoto) { _, item in
            Task { await usePicked(item) }
        }
        .sheet(item: $found, onDismiss: resume) { food in
            NavigationStack {
                FoodDetailView(food: food, day: day) { dismiss() }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $quickAdd, onDismiss: resume) { draft in
            NavigationStack {
                QuickAddView(draft: draft, day: day) { dismiss() }
            }
        }
        .fullScreenCover(item: $photo) { captured in
            EstimateView(image: captured.image, isLabel: captured.isLabel, day: day, takenAt: captured.takenAt) { dismiss() }
        }
        .alert("Type the barcode", isPresented: $typing) {
            TextField("Barcode", text: $typedCode)
                .keyboardType(.numberPad)
            Button("Look up") { lookUp(typedCode, typed: true) }
            Button("Cancel", role: .cancel) {}
        }
        #if DEBUG
        .onAppear(perform: openDemoState)
        #endif
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(FloatingIconStyle())
            .accessibilityLabel("Close")
            Spacer()
            Text("Scan")
                .font(.ui(17, .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                torchOn.toggle()
                setTorch(torchOn)
            } label: {
                Image(systemName: torchOn ? "bolt.fill" : "bolt.slash")
            }
            .buttonStyle(FloatingIconStyle())
            .opacity(camera == .ready && Self.hasTorch ? 1 : 0)
            .disabled(!(camera == .ready && Self.hasTorch))
            .accessibilityLabel(torchOn ? "Turn the light off" : "Turn the light on")
        }
    }

    /// One short line about what is happening, on frosted glass.
    @ViewBuilder private var statusPill: some View {
        switch (camera, phase) {
        case (.denied, .scanning):
            pillMessage("Bite needs the camera. Allow it in Settings.", action: ("Open Settings", openSettings))
        case (.unavailable, .scanning):
            pillMessage(mode == .barcode ? "No camera here. Type the barcode instead." : "No camera here. Pick a photo instead.", action: nil)
        case (_, .scanning):
            pillMessage(capturing ? "Taking the photo" : mode.hint, action: nil)
        case (_, .looking(let code)):
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking up \(code)")
            }
            .font(.ui(15, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(.ultraThinMaterial, in: Capsule())
        case (_, .notFound(let code)):
            resultPanel(
                "\(code) isn't in Open Food Facts yet.",
                primary: ("Snap the label", snapLabel),
                secondary: ("Type it in", { quickAdd = QuickAddDraft(barcode: code) })
            )
        case (_, .noNutrition(let code, let name)):
            resultPanel(
                "\(name) has no nutrition facts yet.",
                primary: ("Snap the label", snapLabel),
                secondary: ("Type it in", { quickAdd = QuickAddDraft(name: name, barcode: code) })
            )
        case (_, .failed(let code)):
            resultPanel("Couldn't reach Open Food Facts.", primary: ("Try again", {
                phase = .scanning
                lookUp(code, typed: true)
            }))
        }
    }

    private func pillMessage(_ text: LocalizedStringKey, action: (LocalizedStringKey, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.ui(15, .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .font(.ui(15, .semibold))
                    .foregroundStyle(.white)
                    .underline()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// What happened, the best next step in ink, the other one quiet, and Scan again under them.
    private func resultPanel(
        _ text: LocalizedStringKey,
        primary: (LocalizedStringKey, () -> Void),
        secondary: (LocalizedStringKey, () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.ui(17, .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                if let secondary {
                    Button(secondary.0, action: secondary.1)
                        .buttonStyle(SoftButtonStyle(tint: .white))
                }
                Button(primary.0, action: primary.1)
                    .buttonStyle(PrimaryButtonStyle(height: 44))
            }
            Button("Scan again", action: resume)
                .font(.ui(15, .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// No data for this barcode: read the nutrition label off the pack instead.
    private func snapLabel() {
        withAnimation(.snappy) {
            modeRaw = ScanMode.label.rawValue
            phase = .scanning
        }
    }

    /// Scan food, Barcode, Food label: glass tiles, the chosen one white.
    private var modeTiles: some View {
        HStack(spacing: 8) {
            ForEach(ScanMode.allCases) { option in
                let selected = option == mode
                Button {
                    withAnimation(.snappy) {
                        modeRaw = option.rawValue
                        phase = .scanning
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 21, weight: .regular))
                        Text(option.title)
                            .font(.ui(13, .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 6)
                    }
                    .foregroundStyle(selected ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial))
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Gallery on the left, the shutter in the middle (typing for barcodes), nothing on the right.
    private var controls: some View {
        HStack {
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
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
            .opacity(mode.takesPhoto ? 1 : 0)
            .disabled(!mode.takesPhoto)
            .frame(width: 72)

            Spacer()

            if mode.takesPhoto {
                Button(action: capture) {
                    Circle()
                        .fill(.white)
                        .frame(width: 66, height: 66)
                        .padding(5)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                        .opacity(capturing || camera != .ready ? 0.4 : 1)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .disabled(capturing || camera != .ready)
                .accessibilityLabel("Take photo")
            } else {
                Button {
                    typedCode = ""
                    typing = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Type the barcode")
            }

            Spacer()

            Color.clear.frame(width: 72, height: 1)
        }
        .padding(.top, 4)
    }

    // MARK: Actions

    private func capture() {
        guard !capturing else { return }
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            if let image = try? await control.capturePhoto() {
                scans += 1
                photo = CapturedPhoto(image: ImageTools.fitted(image, maxPixel: 2048), isLabel: mode == .label)
            }
        }
    }

    private func usePicked(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = ImageTools.downsample(data, maxPixel: 2048) else { return }
        pickedPhoto = nil
        // Last night's dinner picked this morning goes on today, at today's time.
        let takenAt = ImageTools.captureDate(of: data).flatMap { Calendar.current.isDate($0, inSameDayAs: day) ? $0 : nil }
        photo = CapturedPhoto(image: image, isLabel: mode == .label, takenAt: takenAt)
    }

    private func lookUp(_ raw: String, typed: Bool = false) {
        let code = raw.filter(\.isNumber)
        guard !code.isEmpty else { return }
        if case .looking = phase { return }
        // The camera sees the same barcode again right after a sheet closes. Ignore it briefly.
        if !typed, code == lastCode, Date.now.timeIntervalSince(resumedAt) < 2 { return }

        lastCode = code
        if !typed { scans += 1 }
        phase = .looking(code)
        Task { @MainActor in
            do {
                if let food = try await OpenFoodFacts.shared.product(barcode: code) {
                    if food.hasNutrition {
                        phase = .scanning
                        found = food
                    } else {
                        Feel.play(.snag)
                        phase = .noNutrition(code: code, name: food.name)
                    }
                } else {
                    Feel.play(.snag)
                    phase = .notFound(code)
                }
            } catch {
                Feel.play(.failed)
                phase = .failed(code)
            }
        }
    }

    private func resume() {
        resumedAt = .now
        phase = .scanning
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            torchOn = false
        }
    }

    #if DEBUG
    /// `-screen photo` opens on the food mode; `-screen estimate` jumps to a demo estimate.
    private func openDemoState() {
        switch UserDefaults.standard.string(forKey: "screen") {
        case "photo":
            modeRaw = ScanMode.food.rawValue
        case "estimate":
            photo = CapturedPhoto(image: DemoData.plateImage(), isLabel: false)
        default:
            break
        }
    }
    #endif
}

extension ScannerView.CameraState {
    @MainActor static func check() async -> Self {
        guard DataScannerViewController.isSupported else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default:
            return .denied
        }
    }
}

/// Dims the camera around the window to aim with, with white corners and, for barcodes, the
/// red laser. A plate gets a square, a barcode a wide strip, a label a tall card.
private struct Viewfinder: View {
    let mode: ScanMode

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 56, 340)
            let height = Self.height(for: mode, width: width)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.4)
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .frame(width: width, height: height)
                            .position(center)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                ScanCorners(length: 0.18)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height)
                    .position(center)
                if mode == .barcode {
                    LaserLine()
                        .frame(width: width - 40, height: height - 40)
                        .position(center)
                }
            }
            .animation(.snappy, value: mode)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    static func height(for mode: ScanMode, width: CGFloat) -> CGFloat {
        switch mode {
        case .barcode: 170
        case .food: width
        case .label: width * 1.2
        }
    }
}

/// The red line that sweeps over a barcode.
private struct LaserLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var down = false

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Theme.laser)
                .frame(height: 2.5)
                .shadow(color: Theme.laser, radius: 6)
                .offset(y: down ? geometry.size.height : 0)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { down = true }
        }
    }
}

/// A round glass button that floats on the camera.
struct FloatingIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
