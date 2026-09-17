import AppKit
import Foundation
import CrookcookedCore

@MainActor
final class AppModel: ObservableObject {
    @Published var status: CrookcookedStatus = .disarmed {
        didSet { CrookcookedTerminationGuard.status = status }
    }
    @Published var countdown = 0
    @Published var events: [CrookcookedEvent] = []
    @Published var relayState = "Offline"
    @Published var cameraState = "Not requested"
    @Published var inputMonitoringState = "Permission required for global input"
    @Published var securityState = "Apple lock verification ready"
    @Published var hasCheckedPermissions = false
    @Published var configuration: CrookcookedConfiguration {
        didSet {
            store.save(configuration)
            controller?.apply(configuration)
        }
    }

    private let store = ConfigurationStore()
    private var controller: CrookcookedController!
    private var armingTask: Task<Void, Never>?

    init() {
        configuration = store.load()
        // The alarm is loud out of the box. Only an explicit choice to go quiet
        // overrides that, so a half-written preference file cannot silence the Mac.
        if UserDefaults.standard.object(forKey: Self.alarmChoiceKey) == nil {
            configuration.audibleAlarm = true
        }
        controller = CrookcookedController(model: self, configuration: configuration)
    }

    private static let alarmChoiceKey = "crookcooked.audibleAlarmChoice"

    var statusLabel: String {
        switch status {
        case .disarmed: return "disarmed"
        case .arming: return "arming in \(countdown)s"
        case .armed: return "watching your Mac"
        case .triggered: return configuration.audibleAlarm ? "alarm sounding" : "silent alert sent"
        }
    }

    var menuBarIcon: String {
        switch status {
        case .disarmed: return "shield"
        case .arming: return "timer"
        case .armed: return "shield.fill"
        case .triggered: return "exclamationmark.shield.fill"
        }
    }

    var pairingCode: String { PairingSecret.displayCode(from: configuration.pairingSecret) }

    var pairingPayload: PairingPayload {
        PairingPayload(relayURL: configuration.relayURL, secret: configuration.pairingSecret)
    }

    /// The relay reports "iPhone connected" only while a phone is in the room;
    /// "Connected; waiting for iPhone" must not count.
    var isPhonePaired: Bool { relayState == "iPhone connected" }

    func copyPairingLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingPayload.encoded, forType: .string)
    }

    func arm() {
        guard status == .disarmed else { return }
        status = .arming
        countdown = max(1, configuration.armingDelaySeconds)
        controller.preparePermissions()
        armingTask?.cancel()
        armingTask = Task { [weak self] in
            guard let self else { return }
            while self.countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.countdown -= 1
            }
            await self.finishArming()
        }
    }

    private func finishArming() async {
        controller.prepareForSystemLock()
        do {
            let method = try await controller.lockAndVerify()
            guard status == .arming else { return }
            status = .armed
            securityState = "Locked and verified via \(method)"
            controller.startArmed()
            controller.sendStatus(.armed)
        } catch {
            securityState = error.localizedDescription
            status = .disarmed
            controller.stopArmed()
        }
    }

    func disarm() {
        armingTask?.cancel()
        status = .disarmed
        countdown = 0
        controller.stopArmed()
        controller.sendStatus(.disarmed)
    }

    func receiveSensorEvent(_ event: CrookcookedEvent) {
        guard status == .armed else { return }
        events.insert(event, at: 0)
        if events.count > 50 { events.removeLast(events.count - 50) }
        controller.evaluate(event)
    }

    func trigger(_ event: CrookcookedEvent) {
        guard status == .armed else { return }
        status = .triggered
        controller.trigger(event, audible: configuration.audibleAlarm)
    }

    func setAudibleAlarm(_ enabled: Bool) {
        configuration.audibleAlarm = enabled
        UserDefaults.standard.set(enabled, forKey: Self.alarmChoiceKey)
    }

    /// One button: report what is already granted, and only prompt for the things
    /// macOS will still ask about.
    func testPermissions() {
        controller.refreshPermissionState()
        controller.preparePermissions()
        hasCheckedPermissions = true
    }

    func openSettings(for target: PermissionTarget) {
        guard let url = URL(string: target.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func regeneratePairingSecret() {
        configuration.pairingSecret = PairingSecret.generate()
    }

    func copyPairingSecret() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.pairingSecret, forType: .string)
    }

    func handleRemoteCommand(_ command: RemoteCommand) {
        switch command {
        case .arm: arm()
        case .disarm: disarm()
        case .startStream: controller.setStreaming(true)
        case .stopStream: controller.setStreaming(false)
        case .requestSnapshot: controller.sendSnapshot()
        }
    }
}
