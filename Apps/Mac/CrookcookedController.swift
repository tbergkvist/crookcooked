import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import CrookcookedCore

@MainActor
final class CrookcookedController {
    private weak var model: AppModel?
    private var configuration: CrookcookedConfiguration
    private var scorer: ThreatScorer
    private let sensors = SensorHub()
    private let camera = CameraService()
    private let alarm = AlarmService()
    private let relay = RelayClient(role: .mac)
    private let systemLock = SystemLockService()
    private let crookcookedWallpaper = CrookcookedWallpaperService()
    private let displayWake = DisplayWakeService()

    init(model: AppModel, configuration: CrookcookedConfiguration) {
        self.model = model
        self.configuration = configuration
        self.scorer = ThreatScorer(threshold: configuration.triggerThreshold)
        crookcookedWallpaper.setAudibleAlarm(configuration.audibleAlarm)
        crookcookedWallpaper.setShowAvatar(configuration.lockScreenAvatar)
        let wallpaperReady = crookcookedWallpaper.prepare()
        model.securityState = systemLock.nativeServiceAvailable
            ? "Native Apple login service available; lock verification ready"
            : "Native service unavailable; Accessibility shortcut required"
        if !wallpaperReady {
            model.securityState += " • crookcooked lock-screen artwork failed"
        }

        sensors.onEvent = { [weak model] event in
            Task { @MainActor in model?.receiveSensorEvent(event) }
        }
        camera.onMovement = { [weak model] in
            Task { @MainActor in
                model?.receiveSensorEvent(CrookcookedEvent(kind: .cameraMovement, detail: "The camera view changed while armed"))
            }
        }
        camera.onFrame = { [weak self] data in
            Task { @MainActor in self?.relay.sendFrame(data) }
        }
        camera.onEvidenceClip = { [weak self] data in
            Task { @MainActor in self?.relay.sendClip(data) }
        }
        camera.onAttentionChange = { [weak self] detected, mugshot in
            Task { @MainActor in
                guard let self, self.configuration.faceAttentionWarning else { return }
                self.crookcookedWallpaper.setAttentionDetected(detected, mugshot: mugshot)
            }
        }
        relay.onStateChange = { [weak model] value in
            Task { @MainActor in model?.relayState = value }
        }
        relay.onCommand = { [weak model] command in
            Task { @MainActor in model?.handleRemoteCommand(command) }
        }
        systemLock.onUnlock = { [weak self, weak model] in
            self?.crookcookedWallpaper.restore()
            guard let model, model.status == .armed || model.status == .triggered else { return }
            model.disarm()
        }
        connectRelay()
    }

    func apply(_ configuration: CrookcookedConfiguration) {
        let reconnect = configuration.relayURL != self.configuration.relayURL ||
            configuration.pairingSecret != self.configuration.pairingSecret
        self.configuration = configuration
        self.scorer = ThreatScorer(threshold: configuration.triggerThreshold)
        camera.movementDetectionEnabled = configuration.cameraMovementDetection
        crookcookedWallpaper.setAudibleAlarm(configuration.audibleAlarm)
        crookcookedWallpaper.setShowAvatar(configuration.lockScreenAvatar)
        let attentionEnabled = configuration.faceAttentionWarning &&
            (model?.status == .armed || model?.status == .triggered)
        camera.setAttentionDetectionEnabled(attentionEnabled)
        if !configuration.faceAttentionWarning {
            crookcookedWallpaper.setAttentionDetected(false, mugshot: nil)
        }
        if reconnect { connectRelay() }
    }

    /// Reports what is already granted without prompting, so the owner can check
    /// readiness on demand instead of discovering a gap at arming time.
    func refreshPermissionState() {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        model?.cameraState = switch cameraStatus {
        case .authorized: "Camera ready"
        case .notDetermined: "Camera not requested yet"
        case .denied: "Camera permission denied"
        case .restricted: "Camera restricted by policy"
        @unknown default: "Camera state unknown"
        }

        model?.inputMonitoringState = CGPreflightListenEventAccess()
            ? "Input monitoring ready"
            : "Input monitoring permission is required for keyboard/pointer triggers"

        model?.securityState = systemLock.nativeServiceAvailable
            ? "Native Apple login service available; lock verification ready"
            : "Native service unavailable; Accessibility shortcut required"
    }

    func preparePermissions() {
        camera.requestAccess { [weak model] granted in
            Task { @MainActor in
                model?.cameraState = granted ? "Camera ready" : "Camera permission denied"
            }
        }
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let inputReady = CGPreflightListenEventAccess() || SensorHub.requestInputPermission()
        model?.inputMonitoringState = inputReady
            ? "Input monitoring ready"
            : "Input monitoring permission is required for keyboard/pointer triggers"
    }

    func prepareForSystemLock() {
        _ = displayWake.start()
        camera.movementDetectionEnabled = false
        camera.setAttentionDetectionEnabled(false)
        camera.start()
        // Install the HID tap in the active user session before loginwindow takes
        // the screen. Events during `.arming` are intentionally ignored by AppModel.
        sensors.start()
    }

    func lockAndVerify() async throws -> String {
        do {
            try crookcookedWallpaper.activate()
            model?.securityState = "crookcooked lock screen active • Requesting Apple lock screen"
            try? await Task.sleep(for: .milliseconds(900))
        } catch {
            model?.securityState = "Could not set crookcooked wallpaper; Apple lock still required"
        }
        let method = try await systemLock.requestAndVerifyLock { [weak model] in
            model?.securityState = "Press Control–Command–Q now; crookcooked will verify the Apple lock before arming"
        }
        return method.rawValue
    }

    func startArmed() {
        _ = displayWake.start()
        Task { await scorer.reset() }
        sensors.start()
        camera.movementDetectionEnabled = configuration.cameraMovementDetection
        camera.setAttentionDetectionEnabled(configuration.faceAttentionWarning)
        camera.start()
        Task { [weak self, weak model] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let model, model.status == .armed || model.status == .triggered else { return }
            let cameraActive = self.camera.hasRecentFrames()
            model.securityState = cameraActive
                ? "Apple session locked and verified • Camera active behind lock screen"
                : "Apple session locked and verified • Camera has no frames; other sensors remain active"
        }
    }

    func stopArmed() {
        sensors.stop()
        camera.setAttentionDetectionEnabled(false)
        camera.stop()
        displayWake.stop()
        camera.streamingEnabled = false
        alarm.stop()
        crookcookedWallpaper.restore()
        Task { await scorer.reset() }
    }

    func evaluate(_ event: CrookcookedEvent) {
        Task { [weak self] in
            guard let self else { return }
            let result = await scorer.evaluate(event)
            if result.shouldTrigger {
                await MainActor.run { self.model?.trigger(event) }
            }
        }
    }

    func trigger(_ event: CrookcookedEvent, audible: Bool) {
        // This is the final safety gate: no sound API is called unless the owner
        // explicitly enabled audible alarms in settings.
        alarm.startIfAllowed(audible)
        camera.streamingEnabled = true
        if configuration.recordEvidence { camera.recordEvidenceClip() }
        relay.sendEvent(event, snapshot: camera.latestFrame)
        sendStatus(.triggered)
    }

    func setStreaming(_ value: Bool) {
        camera.streamingEnabled = value
        if value { camera.start() }
    }

    func sendSnapshot() {
        guard let frame = camera.latestFrame else { return }
        relay.sendFrame(frame)
    }

    func sendStatus(_ status: CrookcookedStatus) {
        relay.send(RelayMessage(type: .status, status: status))
    }

    private func connectRelay() {
        guard let url = RelayEndpoint.validatedURL(from: configuration.relayURL) else {
            model?.relayState = "Enter a ws:// or wss:// relay URL"
            return
        }
        relay.connect(url: url, secret: configuration.pairingSecret)
    }
}
