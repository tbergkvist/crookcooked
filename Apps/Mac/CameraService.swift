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
    /// Set from the main actor, read for every frame on the sample queue.
    var movementDetectionEnabled: Bool {
        get { sampleQueue.sync { movementDetection } }
        set {
            sampleQueue.async {
                // A fresh reference each time watching starts, from wherever the Mac now sits.
                if newValue && !self.movementDetection { self.resetMotionState() }
                self.movementDetection = newValue
            }
        }
    }
    var streamingEnabled: Bool {
        get { sampleQueue.sync { streaming } }
        set { sampleQueue.async { self.streaming = newValue } }
    }
    var latestFrame: Data? {
        sampleQueue.sync { evidenceFrameCache.latestFrame }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.crookcooked.camera.session")
    private let sampleQueue = DispatchQueue(label: "app.crookcooked.camera.samples")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let movieOutput = AVCaptureMovieFileOutput()
    private var configured = false
    private var movementDetection = true
    private var streaming = false
    private static let motionAnalysisSize = CGSize(width: 192, height: 144)
    private var motionReference: (left: CGImage, right: CGImage)?
    private var motionWarmup = 0
    private var motionDetector = CameraMotionDetector()
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
                self.resetMotionState()
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
                .appendingPathComponent("crookcooked/Evidence", isDirectory: true)
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

        if movementDetection, now.timeIntervalSince(lastAnalysis) >= 0.7 {
            lastAnalysis = now
            analyzeMovement(pixelBuffer)
        }

        if attentionDetectionEnabled, now.timeIntervalSince(lastAttentionAnalysis) >= 0.8 {
            lastAttentionAnalysis = now
            analyzeAttention(pixelBuffer)
        }

        let frameDisposition = EvidenceFramePolicy.disposition(
            streamingEnabled: streaming,
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

    /// Compares side strips of the frame with the reference; see `CameraMotionDetector`.
    private func analyzeMovement(_ buffer: CVPixelBuffer) {
        let image = CIImage(cvPixelBuffer: buffer)
        let size = Self.motionAnalysisSize
        let scaled = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width, y: size.height / image.extent.height))
        let stripWidth = (size.width * 0.3).rounded()
        guard let left = context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: stripWidth, height: size.height)),
              let right = context.createCGImage(scaled, from: CGRect(x: size.width - stripWidth, y: 0, width: stripWidth, height: size.height))
        else { return }

        // Let exposure and focus settle before choosing the reference.
        motionWarmup += 1
        guard motionWarmup > 2 else { return }
        guard let reference = motionReference else {
            motionReference = (left, right)
            return
        }

        let moved = motionDetector.observe(
            left: displacement(of: left, from: reference.left, frame: size),
            right: displacement(of: right, from: reference.right, frame: size)
        )
        if moved {
            motionReference = (left, right)
            onMovement?()
        }
    }

    private func displacement(of strip: CGImage, from reference: CGImage, frame: CGSize) -> CameraMotionDetector.Shift? {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: strip)
        guard (try? VNImageRequestHandler(cgImage: reference).perform([request])) != nil,
              let transform = request.results?.first?.alignmentTransform
        else { return nil }
        return .init(x: Double(transform.tx / frame.width), y: Double(transform.ty / frame.height))
    }

    private func resetMotionState() {
        motionReference = nil
        motionWarmup = 0
        motionDetector.reset()
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
