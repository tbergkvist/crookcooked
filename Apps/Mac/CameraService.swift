@preconcurrency import AVFoundation
import AppKit
import CoreImage
import Foundation
import CrookcookedCore
import Vision

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    var onMovement: (() -> Void)?
    var onFrame: ((Data) -> Void)?
    var onEvidenceClip: ((Data) -> Void)?
    var onAttentionChange: ((Bool, Data?) -> Void)?
    var movementDetectionEnabled = true
    var streamingEnabled = false
    var latestFrame: Data? {
        sampleQueue.sync { evidenceFrameCache.latestFrame }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.crookcooked.camera.session")
    private let sampleQueue = DispatchQueue(label: "app.crookcooked.camera.samples")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let movieOutput = AVCaptureMovieFileOutput()
    private var configured = false
    private var previousSignature: [UInt8]?
    private var movementStreak = 0
    private var lastAnalysis = Date.distantPast
    private var evidenceFrameCache = EvidenceFrameCache()
    private var lastSample = Date.distantPast
    private var attentionDetectionEnabled = false
    private var lastAttentionAnalysis = Date.distantPast
    private var attentionPositiveStreak = 0
    private var attentionNegativeStreak = 0
    private var attentionActive = false

    func requestAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: completion(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        default: completion(false)
        }
    }

    func start() {
        requestAccess { [weak self] granted in
            guard granted else { return }
            self?.sessionQueue.async {
                self?.configureIfNeeded()
                guard let self, !self.session.isRunning else { return }
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
            self.sampleQueue.sync {
                self.previousSignature = nil
                self.movementStreak = 0
                self.lastSample = .distantPast
                self.evidenceFrameCache.reset()
            }
        }
    }

    func setAttentionDetectionEnabled(_ enabled: Bool) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            self.attentionDetectionEnabled = enabled
            if !enabled { self.resetAttentionState(notify: true) }
        }
    }

    func recordEvidenceClip(seconds: TimeInterval = 12) {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning, !self.movieOutput.isRecording else { return }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Crookcooked/Evidence", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let name = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".mov"
            self.movieOutput.startRecording(to: directory.appendingPathComponent(name), recordingDelegate: self)
            self.sessionQueue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                if self?.movieOutput.isRecording == true { self?.movieOutput.stopRecording() }
            }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Date()
        lastSample = now

        if movementDetectionEnabled, now.timeIntervalSince(lastAnalysis) >= 0.7 {
            lastAnalysis = now
            analyzeMovement(pixelBuffer)
        }


        if attentionDetectionEnabled, now.timeIntervalSince(lastAttentionAnalysis) >= 0.8 {
            lastAttentionAnalysis = now
            analyzeAttention(pixelBuffer)
        }

        let frameDisposition = EvidenceFramePolicy.disposition(
            streamingEnabled: streamingEnabled,
            secondsSinceLastRefresh: now.timeIntervalSince(evidenceFrameCache.refreshedAt)
        )
        if frameDisposition.refreshSnapshot, let jpeg = makeJPEG(pixelBuffer) {
            evidenceFrameCache.store(jpeg, at: now)
            if frameDisposition.publishToLiveStream { onFrame?(jpeg) }
        }
    }

    private func analyzeAttention(_ buffer: CVPixelBuffer) {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .upMirrored)
        let appearsAttentive: Bool
        do {
            try handler.perform([request])
            appearsAttentive = (request.results ?? []).contains { face in
                let box = face.boundingBox
                let largeEnough = box.width >= 0.11 && box.height >= 0.14
                let yaw = abs(face.yaw?.doubleValue ?? 0)
                let pitch = abs(face.pitch?.doubleValue ?? 0)
                let hasEyes = face.landmarks?.leftEye != nil && face.landmarks?.rightEye != nil
                return face.confidence >= 0.5 && largeEnough && yaw <= 0.48 && pitch <= 0.42 && hasEyes
            }
        } catch {
            appearsAttentive = false
        }

        if appearsAttentive {
            attentionPositiveStreak += 1
            attentionNegativeStreak = 0
            if attentionPositiveStreak >= 2 && !attentionActive {
                attentionActive = true
                onAttentionChange?(true, makeJPEG(buffer))
            }
        } else {
            attentionPositiveStreak = 0
            attentionNegativeStreak += 1
            if attentionNegativeStreak >= 5 && attentionActive {
                attentionActive = false
                onAttentionChange?(false, nil)
            }
        }
    }

    private func resetAttentionState(notify: Bool) {
        attentionPositiveStreak = 0
        attentionNegativeStreak = 0
        lastAttentionAnalysis = .distantPast
        if attentionActive {
            attentionActive = false
            if notify { onAttentionChange?(false, nil) }
        }
    }

    func hasRecentFrames(within interval: TimeInterval = 2) -> Bool {
        sampleQueue.sync { Date().timeIntervalSince(lastSample) <= interval }
    }

    private func analyzeMovement(_ buffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        let scaled = image.transformed(by: CGAffineTransform(scaleX: 16 / extent.width, y: 12 / extent.height))
        var pixels = [UInt8](repeating: 0, count: 16 * 12 * 4)
        context.render(scaled, toBitmap: &pixels, rowBytes: 16 * 4, bounds: CGRect(x: 0, y: 0, width: 16, height: 12), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let signature = stride(from: 0, to: pixels.count, by: 4).map { index -> UInt8 in
            let total = Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            return UInt8(total / 3)
        }
        defer { previousSignature = signature }
        guard let previousSignature, previousSignature.count == signature.count else { return }
        let averageDifference = zip(signature, previousSignature).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) } / signature.count
        movementStreak = averageDifference > 24 ? movementStreak + 1 : 0
        if movementStreak >= 2 {
            movementStreak = 0
            onMovement?()
        }
    }

    private func makeJPEG(_ buffer: CVPixelBuffer) -> Data? {
        var image = CIImage(cvPixelBuffer: buffer)
        let width = image.extent.width
        if width > 640 {
            let scale = 640 / width
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil, let data = try? Data(contentsOf: outputFileURL) else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        onEvidenceClip?(data)
    }
}
