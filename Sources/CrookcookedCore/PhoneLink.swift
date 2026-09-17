import Foundation

// The Mac serves the phone page and an encrypted event stream on the local
// network. Nothing here touches sockets, so the protocol can be tested directly.

public enum PhoneMessageType: String, Codable, Sendable {
    case status
    case event
    case frame
    case clip
    case notice
}

/// Mac → phone. Each message is JSON, sealed with `LinkCrypto`, then base64-encoded
/// into one server-sent event.
public struct PhoneMessage: Codable, Equatable, Sendable {
    public var type: PhoneMessageType
    public var status: CrookcookedStatus?
    /// Status detail (for example a sensor that is unavailable) or notice text.
    public var detail: String?
    public var event: CrookcookedEvent?
    public var frameBase64: String?
    public var clipID: String?
    /// With `status`: whether the Mac's siren is sounding right now.
    public var alarmSounding: Bool?
    public var sentAt: Date

    public init(
        type: PhoneMessageType,
        status: CrookcookedStatus? = nil,
        detail: String? = nil,
        event: CrookcookedEvent? = nil,
        frameBase64: String? = nil,
        clipID: String? = nil,
        alarmSounding: Bool? = nil,
        sentAt: Date = Date()
    ) {
        self.type = type
        self.status = status
        self.detail = detail
        self.event = event
        self.frameBase64 = frameBase64
        self.clipID = clipID
        self.alarmSounding = alarmSounding
        self.sentAt = sentAt
    }
}

public enum RemoteCommand: String, Codable, Sendable {
    case arm
    case disarm
    case startStream = "start_stream"
    case stopStream = "stop_stream"
    case requestSnapshot = "request_snapshot"
    /// Stops the siren but stays triggered: evidence keeps flowing.
    case silenceAlarm = "silence_alarm"
}

/// Phone → Mac. The random `id` and `sentAt` let the Mac refuse a captured
/// command replayed later, even though the attacker cannot read it.
public struct CommandEnvelope: Codable, Equatable, Sendable {
    public var id: String
    public var command: RemoteCommand
    public var sentAt: Date

    public init(id: String = UUID().uuidString, command: RemoteCommand, sentAt: Date = Date()) {
        self.id = id
        self.command = command
        self.sentAt = sentAt
    }
}

public enum PhoneLinkCoding {
    /// ISO-8601 without fractional seconds, which is what the phone page sends.
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

    public static func seal(_ message: PhoneMessage, secret: String) throws -> String {
        try LinkCrypto.seal(encoder.encode(message), secret: secret).base64EncodedString()
    }

    public static func openCommand(_ base64: String, secret: String) -> CommandEnvelope? {
        guard let sealed = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let json = try? LinkCrypto.open(sealed, secret: secret)
        else { return nil }
        return try? decoder.decode(CommandEnvelope.self, from: json)
    }
}

/// Accepts each command once, and only while it is fresh.
public struct CommandReplayGuard: Sendable {
    /// Generous enough for ordinary phone/Mac clock drift.
    public let window: TimeInterval
    private var seen: [String: Date] = [:]

    public init(window: TimeInterval = 120) {
        self.window = window
    }

    public mutating func accept(_ envelope: CommandEnvelope, now: Date = Date()) -> Bool {
        seen = seen.filter { now.timeIntervalSince($0.value) <= window * 2 }
        guard abs(now.timeIntervalSince(envelope.sentAt)) <= window, seen[envelope.id] == nil else { return false }
        seen[envelope.id] = now
        return true
    }
}

public enum PairingLink {
    /// `http://192.168.1.20:47823/#k=SECRET`. The fragment is never sent over
    /// the network by the browser, so the secret stays on the phone.
    public static func url(host: String, port: UInt16, secret: String) -> String {
        "http://\(host):\(port)/#k=\(secret)"
    }
}

/// Picks the address a phone on the same network is most likely to reach.
public enum LocalAddressPicker {
    public struct Candidate: Equatable, Sendable {
        public let interface: String
        public let address: String

        public init(interface: String, address: String) {
            self.interface = interface
            self.address = address
        }
    }

    public static func pick(from candidates: [Candidate]) -> String? {
        let usable = candidates.filter { candidate in
            let octets = candidate.address.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else { return false }
            let loopback = octets[0] == 127
            let linkLocal = octets[0] == 169 && octets[1] == 254
            // Virtual interfaces (VPNs, VMs) are unreachable from the phone.
            let physical = candidate.interface.hasPrefix("en") || candidate.interface.hasPrefix("bridge")
            return !loopback && !linkLocal && physical
        }
        // Wi-Fi and wired Ethernet before bridges such as Internet Sharing.
        return usable.sorted { rank($0.interface) < rank($1.interface) }.first?.address
    }

    private static func rank(_ interface: String) -> Int {
        if interface == "en0" { return 0 }
        if interface.hasPrefix("en") { return 1 }
        return 2
    }
}

/// Who may talk to the phone server at all, before any secret is checked.
public enum LocalNetworkPolicy {
    public struct Subnet: Equatable, Sendable {
        public let address: UInt32
        public let mask: UInt32

        public init(address: UInt32, mask: UInt32) {
            self.address = address
            self.mask = mask
        }
    }

    /// A Mac on a network that hands out public addresses is reachable from the
    /// internet, so only peers on one of the Mac's own subnets, or the Mac
    /// itself, are served. A phone on the same Wi-Fi or hotspot always qualifies.
    public static func allowsPeer(_ peer: UInt32, subnets: [Subnet]) -> Bool {
        if peer >> 24 == 127 { return true }
        return subnets.contains { $0.mask != 0 && peer & $0.mask == $0.address & $0.mask }
    }

    /// The pairing link always uses an IP address. Refusing any other `Host`
    /// stops a web page from reaching this server through DNS rebinding.
    public static func allowsHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        if name == "localhost" { return true }
        let octets = name.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil && !$0.isEmpty }
    }
}

/// The head of an HTTP/1.1 request. The server only needs method, path, query,
/// and body length; anything it cannot parse is rejected.
public struct HTTPRequestHead: Equatable, Sendable {
    public static let maximumHeadBytes = 16 * 1024

    public let method: String
    public let path: String
    public let query: [String: String]
    public let contentLength: Int
    public let host: String?

    public enum ParseResult: Equatable, Sendable {
        case incomplete
        case invalid
        case complete(HTTPRequestHead, bodyOffset: Int)
    }

    public static func parse(_ data: Data) -> ParseResult {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > maximumHeadBytes ? .invalid : .incomplete
        }
        guard end.lowerBound <= maximumHeadBytes,
              let text = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8)
        else { return .invalid }

        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3,
              requestLine[2].hasPrefix("HTTP/1."),
              let components = URLComponents(string: String(requestLine[1])),
              components.path.hasPrefix("/")
        else { return .invalid }

        var contentLength = 0
        var host: String?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].lowercased()
            if name == "host" {
                // Two Host headers is an attempt to confuse whoever checks one of them.
                guard host == nil else { return .invalid }
                host = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            if name == "transfer-encoding" { return .invalid }
            if name == "content-length" {
                guard let value = Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)), value >= 0 else {
                    return .invalid
                }
                contentLength = value
            }
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }

        let head = HTTPRequestHead(method: String(requestLine[0]), path: components.path, query: query, contentLength: contentLength, host: host)
        return .complete(head, bodyOffset: end.upperBound - data.startIndex)
    }
}
