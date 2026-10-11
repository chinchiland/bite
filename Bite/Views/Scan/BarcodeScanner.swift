import SwiftUI
import UIKit
import Vision
import VisionKit

/// Lets the scanner screen ask the live camera for a photo.
final class ScannerControl {
    weak var scanner: DataScannerViewController?

    @MainActor func capturePhoto() async throws -> UIImage {
        guard let scanner else { throw CocoaError(.featureUnsupported) }
        return try await scanner.capturePhoto()
    }
}

/// The live camera through VisionKit: reports each new barcode once, and can take a photo.
struct BarcodeScanner: UIViewControllerRepresentable {
    var isScanning: Bool
    var control: ScannerControl?
    var onCode: (String) -> Void
    var onFailure: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> ScannerHostController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        control?.scanner = scanner
        let host = ScannerHostController(scanner: scanner)
        host.onFailure = onFailure
        return host
    }

    func updateUIViewController(_ host: ScannerHostController, context: Context) {
        context.coordinator.onCode = onCode
        host.onFailure = onFailure
        host.wantsScanning = isScanning
    }

    static func dismantleUIViewController(_ host: ScannerHostController, coordinator: Coordinator) {
        host.scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onCode(payload)
                    return
                }
            }
        }
    }
}

/// Holds the scanner and starts it only once it is on screen, which is when VisionKit can run.
final class ScannerHostController: UIViewController {
    let scanner: DataScannerViewController
    var onFailure: () -> Void = {}
    private var isVisible = false

    var wantsScanning = true {
        didSet { apply() }
    }

    init(scanner: DataScannerViewController) {
        self.scanner = scanner
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        apply()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        apply()
    }

    private func apply() {
        if wantsScanning && isVisible {
            guard !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                // Report after this update pass; SwiftUI state must not change mid-update.
                let onFailure = self.onFailure
                DispatchQueue.main.async { onFailure() }
            }
        } else if scanner.isScanning {
            scanner.stopScanning()
        }
    }
}
