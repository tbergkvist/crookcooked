import Foundation
import CryptoKit

public enum CrookcookedStatus: String, Codable, Sendable {
    case disarmed
    case arming
    case armed
    case triggered
}

public enum ThreatKind: String, Codable, CaseIterable, Sendable {
    case keyboardOrPointer = "keyboard_or_pointer"
    case powerDisconnected = "power_disconnected"
    case usbAttached = "usb_attached"
    case cameraMovement = "camera_movement"
    case remoteRequest = "remote_request"
    case manualTest = "manual_test"

    public var title: String {
        switch self {
        case .keyboardOrPointer: return "Keyboard or pointer activity"
        case .powerDisconnected: return "Power adapter disconnected"
        case .usbAttached: return "USB device attached"
        case .cameraMovement: return "Camera detected movement"
        case .remoteRequest: return "Remote trigger"
        case .manualTest: return "Test trigger"
        }
    }

    public var baseScore: Int {
        switch self {
        case .keyboardOrPointer: return 80
        case .powerDisconnected: return 75
        case .usbAttached: return 85
        case .cameraMovement: return 72
        case .remoteRequest, .manualTest: return 100
        }
    }
}

public struct CrookcookedEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: ThreatKind
    public let occurredAt: Date
    public let detail: String
    public let score: Int
    public var evidenceBase64: String?

    public init(
        id: UUID = UUID(),
        kind: ThreatKind,
        occurredAt: Date = Date(),
        detail: String = "",
        score: Int? = nil,
        evidenceBase64: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.detail = detail
        self.score = score ?? kind.baseScore
        self.evidenceBase64 = evidenceBase64
    }
}

public struct CrookcookedConfiguration: Codable, Equatable, Sendable {
    public var audibleAlarm: Bool
    public var triggerThreshold: Int
    public var armingDelaySeconds: Int
    public var recordEvidence: Bool
    public var cameraMovementDetection: Bool
    public var faceAttentionWarning: Bool
    public var lockScreenAvatar: Bool
    public var relayURL: String
    public var pairingSecret: String

    public init(
        audibleAlarm: Bool = true,
        triggerThreshold: Int = 70,
        armingDelaySeconds: Int = 5,
        recordEvidence: Bool = true,
        cameraMovementDetection: Bool = true,
        faceAttentionWarning: Bool = true,
        lockScreenAvatar: Bool = true,
        relayURL: String = "ws://127.0.0.1:8787",
        pairingSecret: String = PairingSecret.generate()
    ) {
        self.audibleAlarm = audibleAlarm
        self.triggerThreshold = triggerThreshold
        self.armingDelaySeconds = armingDelaySeconds
        self.recordEvidence = recordEvidence
        self.cameraMovementDetection = cameraMovementDetection
        self.faceAttentionWarning = faceAttentionWarning
        self.lockScreenAvatar = lockScreenAvatar
        self.relayURL = relayURL
        self.pairingSecret = pairingSecret
    }

    private enum CodingKeys: String, CodingKey {
        case audibleAlarm
        case triggerThreshold
        case armingDelaySeconds
        case recordEvidence
        case cameraMovementDetection
        case faceAttentionWarning
        case lockScreenAvatar
        case relayURL
        case pairingSecret
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        audibleAlarm = try values.decodeIfPresent(Bool.self, forKey: .audibleAlarm) ?? true
        triggerThreshold = try values.decodeIfPresent(Int.self, forKey: .triggerThreshold) ?? 70
        armingDelaySeconds = try values.decodeIfPresent(Int.self, forKey: .armingDelaySeconds) ?? 5
        recordEvidence = try values.decodeIfPresent(Bool.self, forKey: .recordEvidence) ?? true
        cameraMovementDetection = try values.decodeIfPresent(Bool.self, forKey: .cameraMovementDetection) ?? true
        faceAttentionWarning = try values.decodeIfPresent(Bool.self, forKey: .faceAttentionWarning) ?? true
        lockScreenAvatar = try values.decodeIfPresent(Bool.self, forKey: .lockScreenAvatar) ?? true
        relayURL = try values.decodeIfPresent(String.self, forKey: .relayURL) ?? "ws://127.0.0.1:8787"
        pairingSecret = try values.decodeIfPresent(String.self, forKey: .pairingSecret) ?? ""
    }

    /// First-run configuration: loud, because an alarm nobody hears deters nobody.
    public static let standard = CrookcookedConfiguration()

    /// Quiet mode — everything still watches and records, the alarm just stays silent.
    /// Also the right starting point for headless contexts that must not make noise.
    public static let quiet = CrookcookedConfiguration(audibleAlarm: false)
}

public enum PairingSecret {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func generate(length: Int = 16) -> String {
        String((0..<max(8, length)).map { _ in alphabet.randomElement()! })
    }

    public static func displayCode(from secret: String) -> String {
        let scalars = secret.unicodeScalars.map(\.value)
        let value = scalars.reduce(UInt64(5381)) { (($0 << 5) &+ $0) &+ UInt64($1) }
        return String(format: "%06llu", value % 1_000_000)
    }

    public static func roomID(from secret: String) -> String {
        let digest = SHA256.hash(data: Data(("crookcooked-room:" + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum EvidenceCrypto {
    private static func key(for secret: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(("crookcooked-evidence:" + secret).utf8)))
    }

    public static func seal(_ data: Data, secret: String) throws -> Data {
        let box = try ChaChaPoly.seal(data, using: key(for: secret))
        return box.combined
    }

    public static func open(_ data: Data, secret: String) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key(for: secret))
    }
}

public struct EvidenceFrameDisposition: Equatable, Sendable {
    public let refreshSnapshot: Bool
    public let publishToLiveStream: Bool
}

public struct EvidenceFrameCache: Sendable {
    public private(set) var latestFrame: Data?
    public private(set) var refreshedAt: Date

    public init(latestFrame: Data? = nil, refreshedAt: Date = .distantPast) {
        self.latestFrame = latestFrame
        self.refreshedAt = refreshedAt
    }

    public mutating func store(_ frame: Data, at date: Date) {
        latestFrame = frame
        refreshedAt = date
    }

    public mutating func reset() {
        latestFrame = nil
        refreshedAt = .distantPast
    }
}

/// Keeps the evidence snapshot current even when live streaming is off.
/// Snapshot capture and live-stream publication are deliberately separate:
/// triggering needs a recent still, but an idle phone must not receive frames.
public enum EvidenceFramePolicy {
    public static let refreshInterval: TimeInterval = 0.5

    public static func disposition(
        streamingEnabled: Bool,
        secondsSinceLastRefresh: TimeInterval
    ) -> EvidenceFrameDisposition {
        let shouldRefresh = secondsSinceLastRefresh >= refreshInterval
        return EvidenceFrameDisposition(
            refreshSnapshot: shouldRefresh,
            publishToLiveStream: shouldRefresh && streamingEnabled
        )
    }
}
