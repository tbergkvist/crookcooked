import AVFoundation
import UIKit
import CrookcookedCore
import SwiftUI

/// Camera view that watches for a crookcooked pairing QR code.
///
/// Only pairing links are accepted — any other QR code in frame is ignored rather
/// than half-configuring the phone. The session stops as soon as one is found, so
/// the same code cannot be delivered twice.
struct PairingScannerView: UIViewControllerRepresentable {
    let onFound: (PairingPayload) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFound: onFound)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.coordinator = context.coordinator
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onFound: (PairingPayload) -> Void
        private var hasFound = false

        init(onFound: @escaping (PairingPayload) -> Void) {
            self.onFound = onFound
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasFound else { return }
            let codes = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
            for code in codes {
                guard let value = code.stringValue,
                      let payload = PairingPayload.decode(value)
                else { continue }

                hasFound = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFound(payload)
                return
            }
        }
    }

    final class ScannerViewController: UIViewController {
        var coordinator: Coordinator?
        var onFailure: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private let sessionQueue = DispatchQueue(label: "app.crookcooked.phone.scanner")

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            sessionQueue.async { [session] in
                guard !session.isRunning else { return }
                session.startRunning()
            }
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            sessionQueue.async { [session] in
                guard session.isRunning else { return }
                session.stopRunning()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                onFailure?("No camera available for scanning")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onFailure?("Could not start the QR scanner")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            // Set after the output is attached: available types are empty until then.
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
        }
    }
}
