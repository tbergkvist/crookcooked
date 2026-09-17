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
    private let phoneLink: PhoneLinkServer
    private let systemLock = SystemLockService()
    private let crookcookedWallpaper = CrookcookedWallpaperService()
    private let displayWake = DisplayWakeService()

    init(model: AppModel, configuration: CrookcookedConfiguration) {
        self.model = model
        self.configuration = configuration
        self.scorer = ThreatScorer(threshold: configuration.triggerThreshold)
        self.phoneLink = PhoneLinkServer(secret: configuration.pairingSecret)
        crookcookedWallpaper.setAudibleAlarm(configuration.audibleAlarm)
        crookcookedWallpaper.setShowAvatar(configuration.lockScreenAvatar)
        crookcookedWallpaper.prepare()
        model.securityState = systemLock.nativeServiceAvailable
            ? "Native Apple login service available; lock verification ready"
            : "Native service unavailable; Accessibility shortcut required"

        sensors.onEvent = { [weak model] event in
            Task { @MainActor in model?.receiveSensorEvent(event) }
        }
        camera.onMovement = { [weak model] in
            Task { @MainActor in
                model?.receiveSensorEvent(CrookcookedEvent(kind: .cameraMovement, detail: "The whole camera view shifted, so the Mac itself moved"))
            }
        }
        camera.onFrame = { [weak self] data in
            self?.phoneLink.sendFrame(data)
        }
        camera.onEvidenceClip = { [weak self] data in
            self?.phoneLink.sendClip(data)
        }
        // Someone looking is not tampering: show them their photo and tell the
        // owner, but never sound the alarm for it.
        camera.onAttentionChange = { [weak self] detected, mugshot in
            Task { @MainActor in
                guard let self, self.configuration.faceAttentionWarning, self.model?.status == .armed else { return }
                self.crookcookedWallpaper.show(detected ? .watching : .armed, mugshot: mugshot)
                if detected {
                    if let mugshot { self.phoneLink.sendFrame(mugshot) }
                    self.phoneLink.sendNotice("Someone is in front of your Mac. Nothing has been touched.")
                }
            }
        }
        phoneLink.onPairingLinkChange = { [weak model] link in
            MainActor.assumeIsolated { model?.pairingLink = link }
        }
        phoneLink.onPhoneCountChange = { [weak model] count in
            MainActor.assumeIsolated { model?.connectedPhones = count }
        }
        phoneLink.onCommand = { [weak model] command in
            MainActor.assumeIsolated { model?.handleRemoteCommand(command) }
        }
        systemLock.onUnlock = { [weak self, weak model] in
            self?.crookcookedWallpaper.restore()
            guard let model, model.status == .armed || model.status == .triggered else { return }
            model.disarm()
        }
        phoneLink.start()
    }

    func apply(_ configuration: CrookcookedConfiguration) {
        // A new scorer would forget signals already seen, so only replace it when it must change.
        if configuration.triggerThreshold != self.configuration.triggerThreshold {
            scorer = ThreatScorer(threshold: configuration.triggerThreshold)
        }
        self.configuration = configuration
        let watching = model?.status == .armed || model?.status == .triggered
        // While arming, detection stays off: the owner walking away must not count.
        if watching { camera.movementDetectionEnabled = configuration.cameraMovementDetection }
        crookcookedWallpaper.setAudibleAlarm(configuration.audibleAlarm)
        crookcookedWallpaper.setShowAvatar(configuration.lockScreenAvatar)
        camera.setAttentionDetectionEnabled(configuration.faceAttentionWarning && watching)
        if !configuration.faceAttentionWarning {
            crookcookedWallpaper.show(.armed, mugshot: nil)
        }
        phoneLink.updateSecret(configuration.pairingSecret)
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
            try await crookcookedWallpaper.activate()
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
        model?.alarmSounding = false
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
        // The final safety gate: no sound API is called in quiet mode.
        if audible { alarm.start() }
        model?.alarmSounding = alarm.isSounding
        let snapshot = camera.latestFrame
        crookcookedWallpaper.setAlarmSounding(alarm.isSounding)
        crookcookedWallpaper.show(.triggered, mugshot: snapshot)
        camera.streamingEnabled = true
        if configuration.recordEvidence { camera.recordEvidenceClip() }
        phoneLink.sendEvent(event, snapshot: snapshot)
        sendStatus(.triggered)
    }

    /// Stops the siren without disarming: the Mac stays triggered and keeps
    /// sending evidence.
    func silenceAlarm() {
        guard alarm.isSounding else { return }
        alarm.stop()
        model?.alarmSounding = false
        crookcookedWallpaper.setAlarmSounding(false)
        sendStatus(model?.status ?? .triggered)
    }

    func setStreaming(_ value: Bool) {
        camera.streamingEnabled = value
        let armed = model?.status == .armed || model?.status == .triggered
        if value {
            camera.start()
        } else if !armed {
            // Live view was the only reason the camera was on.
            camera.stop()
        }
    }

    func sendSnapshot() {
        guard let frame = camera.latestFrame else {
            return phoneLink.sendNotice("No camera frame yet. The camera runs while the Mac is armed or live view is on.")
        }
        phoneLink.sendFrame(frame)
    }

    func sendStatus(_ status: CrookcookedStatus) {
        let armed = status == .armed || status == .triggered
        phoneLink.sendStatus(status, detail: armed ? model?.readiness?.summary : nil, alarmSounding: alarm.isSounding)
    }

    func sendNotice(_ text: String) {
        phoneLink.sendNotice(text)
    }

    /// What protection is available right now, without prompting for anything.
    func readiness() -> ProtectionReadiness {
        ProtectionReadiness(
            inputMonitoring: CGPreflightListenEventAccess(),
            cameraAccess: AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            cameraFeaturesEnabled: configuration.cameraMovementDetection || configuration.recordEvidence || configuration.faceAttentionWarning,
            canLockUnattended: systemLock.nativeServiceAvailable || AXIsProcessTrusted()
        )
    }
}
