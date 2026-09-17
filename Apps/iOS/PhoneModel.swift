import Foundation
import CrookcookedCore
import UIKit
import UserNotifications

struct PhoneEvent: Identifiable {
    let event: CrookcookedEvent
    let image: UIImage?
    var id: UUID { event.id }
}

@MainActor
final class PhoneModel: ObservableObject {
    @Published var relayURL: String {
        didSet { UserDefaults.standard.set(relayURL, forKey: "relayURL") }
    }
    @Published var pairingSecret: String {
        didSet { secretStore.save(pairingSecret) }
    }
    @Published var connectionState = "Not connected"
    @Published var macStatus: CrookcookedStatus = .disarmed
    @Published var liveImage: UIImage?
    @Published var events: [PhoneEvent] = []
    @Published var latestClipURL: URL?
    @Published var isStreaming = false

    private let relay = PhoneRelayClient()
    private let secretStore = SecretStore(service: "app.crookcooked.phone", account: "pairedMac")
    private var pushObserver: NSObjectProtocol?

    init() {
        relayURL = UserDefaults.standard.string(forKey: "relayURL") ?? "ws://127.0.0.1:8787"
        pairingSecret = secretStore.load() ?? ""

        relay.onStateChange = { [weak self] value in
            Task { @MainActor in self?.connectionState = value }
        }
        relay.onMessage = { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
        pushObserver = NotificationCenter.default.addObserver(forName: .crookcookedPushToken, object: nil, queue: .main) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { @MainActor in self?.relay.updatePushToken(token) }
        }
    }

    deinit {
        if let pushObserver { NotificationCenter.default.removeObserver(pushObserver) }
    }

    var pairingCode: String {
        pairingSecret.isEmpty ? "——" : PairingSecret.displayCode(from: pairingSecret)
    }

    /// Applies a scanned pairing link and connects in one step: the whole point of
    /// the QR path is that there is nothing left to type or tap afterwards.
    func apply(_ payload: PairingPayload) {
        relayURL = payload.relayURL
        pairingSecret = payload.secret
        connect()
    }

    func connect() {
        guard let url = RelayEndpoint.validatedURL(from: relayURL), pairingSecret.count >= 8 else {
            connectionState = "Enter a valid relay URL and pairing secret"
            return
        }
        relay.connect(url: url, secret: pairingSecret)
    }

    func arm() { relay.sendCommand(.arm) }
    func disarm() { relay.sendCommand(.disarm) }
    func requestSnapshot() { relay.sendCommand(.requestSnapshot) }

    func toggleStream() {
        isStreaming.toggle()
        relay.sendCommand(isStreaming ? .startStream : .stopStream)
    }

    private func handle(_ message: RelayMessage) {
        switch message.type {
        case .status:
            if let status = message.status { macStatus = status }
        case .frame:
            if let data = decrypt(message.frameBase64), let image = UIImage(data: data) { liveImage = image }
        case .event:
            guard let event = message.event else { return }
            let image = decrypt(event.evidenceBase64).flatMap(UIImage.init(data:))
            events.insert(PhoneEvent(event: event, image: image), at: 0)
            if let image { liveImage = image }
            notify(event)
        case .clip:
            if let data = decrypt(message.clipBase64) { saveClip(data) }
        default:
            break
        }
    }

    private func decrypt(_ base64: String?) -> Data? {
        guard let base64, let encrypted = Data(base64Encoded: base64) else { return nil }
        return try? EvidenceCrypto.open(encrypted, secret: pairingSecret)
    }

    private func saveClip(_ data: Data) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrookcookedEvidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("evidence-\(Int(Date().timeIntervalSince1970)).mov")
        do {
            try data.write(to: url, options: .atomic)
            latestClipURL = url
        } catch {
            connectionState = "Could not save evidence clip"
        }
    }

    private func notify(_ event: CrookcookedEvent) {
        let content = UNMutableNotificationContent()
        content.title = "crookcooked alert"
        content.body = event.kind.title
        // The phone notification itself stays silent; the Mac's alarm setting is independent.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil))
    }
}
