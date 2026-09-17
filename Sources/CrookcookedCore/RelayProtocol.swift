import Foundation

public enum RelayRole: String, Codable, Sendable {
    case mac
    case phone
}

public enum RelayMessageType: String, Codable, Sendable {
    case hello
    case status
    case event
    case frame
    case clip
    case command
    case registerPush = "register_push"
    case peerState = "peer_state"
    case error
}

public enum RemoteCommand: String, Codable, Sendable {
    case arm
    case disarm
    case startStream = "start_stream"
    case stopStream = "stop_stream"
    case requestSnapshot = "request_snapshot"
}

public struct RelayMessage: Codable, Sendable {
    public var type: RelayMessageType
    public var roomID: String?
    public var role: RelayRole?
    public var deviceID: String?
    public var status: CrookcookedStatus?
    public var event: CrookcookedEvent?
    public var frameBase64: String?
    public var clipBase64: String?
    public var command: RemoteCommand?
    public var pushToken: String?
    public var message: String?
    public var sentAt: Date

    public init(
        type: RelayMessageType,
        roomID: String? = nil,
        role: RelayRole? = nil,
        deviceID: String? = nil,
        status: CrookcookedStatus? = nil,
        event: CrookcookedEvent? = nil,
        frameBase64: String? = nil,
        clipBase64: String? = nil,
        command: RemoteCommand? = nil,
        pushToken: String? = nil,
        message: String? = nil,
        sentAt: Date = Date()
    ) {
        self.type = type
        self.roomID = roomID
        self.role = role
        self.deviceID = deviceID
        self.status = status
        self.event = event
        self.frameBase64 = frameBase64
        self.clipBase64 = clipBase64
        self.command = command
        self.pushToken = pushToken
        self.message = message
        self.sentAt = sentAt
    }

    public static func hello(secret: String, role: RelayRole, deviceID: String) -> RelayMessage {
        RelayMessage(type: .hello, roomID: PairingSecret.roomID(from: secret), role: role, deviceID: deviceID)
    }
}

public enum RelayCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum RelayEndpoint {
    public static func validatedURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil
        else { return nil }
        components.scheme = scheme
        return components.url
    }
}
