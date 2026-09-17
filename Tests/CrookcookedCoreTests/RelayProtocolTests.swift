import Foundation
import Testing

@testable import CrookcookedCore

/// The relay is the only component an owner may self-host or expose to the
/// internet, so both the message shape and the endpoint validation are load-bearing.
@Suite("Relay protocol")
struct RelayProtocolTests {
    private let sentAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A hello derives its room from the pairing secret, not the secret itself")
    func helloDerivesRoom() {
        let secret = "ABCDEFGHJKLMNPQR"
        let hello = RelayMessage.hello(secret: secret, role: .mac, deviceID: "mac-1")

        #expect(hello.type == .hello)
        #expect(hello.role == .mac)
        #expect(hello.deviceID == "mac-1")
        #expect(hello.roomID == PairingSecret.roomID(from: secret))
        #expect(hello.roomID != secret)
    }

    @Test("Both peers derive the same room from one secret")
    func peersAgreeOnRoom() {
        let secret = "ABCDEFGHJKLMNPQR"

        let mac = RelayMessage.hello(secret: secret, role: .mac, deviceID: "mac-1")
        let phone = RelayMessage.hello(secret: secret, role: .phone, deviceID: "phone-1")

        #expect(mac.roomID == phone.roomID)
        #expect(mac.role != phone.role)
    }

    @Test("Wire identifiers are stable")
    func rawValuesAreStable() {
        #expect(RelayMessageType.registerPush.rawValue == "register_push")
        #expect(RelayMessageType.peerState.rawValue == "peer_state")
        #expect(RemoteCommand.startStream.rawValue == "start_stream")
        #expect(RemoteCommand.stopStream.rawValue == "stop_stream")
        #expect(RemoteCommand.requestSnapshot.rawValue == "request_snapshot")
        #expect(RelayRole.mac.rawValue == "mac")
        #expect(RelayRole.phone.rawValue == "phone")
        #expect(CrookcookedStatus.triggered.rawValue == "triggered")
    }

    @Test("An event message survives a round trip through the relay coding")
    func eventMessageRoundTrips() throws {
        let event = CrookcookedEvent(
            kind: .usbAttached,
            occurredAt: sentAt,
            detail: "A new USB device appeared"
        )
        let message = RelayMessage(
            type: .event,
            roomID: "room",
            role: .mac,
            deviceID: "mac-1",
            status: .triggered,
            event: event,
            sentAt: sentAt
        )

        let data = try RelayCoding.encoder.encode(message)
        let decoded = try RelayCoding.decoder.decode(RelayMessage.self, from: data)

        #expect(decoded.type == .event)
        #expect(decoded.roomID == "room")
        #expect(decoded.role == .mac)
        #expect(decoded.status == .triggered)
        #expect(decoded.event == event)
        #expect(decoded.sentAt == sentAt)
    }

    @Test("Dates cross the wire as ISO-8601")
    func datesUseISO8601() throws {
        let data = try RelayCoding.encoder.encode(RelayMessage(type: .status, sentAt: sentAt))
        let json = String(decoding: data, as: UTF8.self)

        #expect(json.contains("2023-11-14T22:13:20Z"))
    }

    @Test("Unset fields stay absent instead of arriving as nulls")
    func omitsUnsetFields() throws {
        let data = try RelayCoding.encoder.encode(RelayMessage(type: .status, sentAt: sentAt))
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("frameBase64"))
        #expect(!json.contains("pushToken"))
    }

    @Test("A command message round-trips")
    func commandRoundTrips() throws {
        let message = RelayMessage(type: .command, command: .disarm, sentAt: sentAt)

        let data = try RelayCoding.encoder.encode(message)
        let decoded = try RelayCoding.decoder.decode(RelayMessage.self, from: data)

        #expect(decoded.command == .disarm)
    }
}

/// A mistyped or hostile relay URL must be refused before any connection is made.
@Suite("Relay endpoint validation")
struct RelayEndpointTests {
    @Test("Plain and secure WebSocket URLs are accepted", arguments: [
        "ws://127.0.0.1:8787",
        "wss://relay.example.com",
        "wss://relay.example.com:443/socket",
    ])
    func acceptsWebSocketURLs(raw: String) {
        #expect(RelayEndpoint.validatedURL(from: raw) != nil)
    }

    @Test("Surrounding whitespace is tolerated")
    func trimsWhitespace() {
        #expect(RelayEndpoint.validatedURL(from: "  ws://127.0.0.1:8787\n") != nil)
    }

    @Test("The scheme is normalised to lower case")
    func normalisesScheme() {
        #expect(RelayEndpoint.validatedURL(from: "WSS://relay.example.com")?.scheme == "wss")
    }

    @Test("Non-WebSocket schemes are refused", arguments: [
        "https://relay.example.com",
        "http://relay.example.com",
        "file:///etc/passwd",
        "javascript:alert(1)",
    ])
    func rejectsOtherSchemes(raw: String) {
        #expect(RelayEndpoint.validatedURL(from: raw) == nil)
    }

    @Test("URLs without a host are refused", arguments: ["ws://", "wss://", "relay.example.com", ""])
    func rejectsHostlessURLs(raw: String) {
        #expect(RelayEndpoint.validatedURL(from: raw) == nil)
    }

    @Test("Credentials embedded in the URL are refused", arguments: [
        "ws://user@relay.example.com",
        "ws://user:password@relay.example.com",
        "wss://:password@relay.example.com",
    ])
    func rejectsEmbeddedCredentials(raw: String) {
        // These would otherwise be logged and stored in plain text alongside the
        // rest of the configuration.
        #expect(RelayEndpoint.validatedURL(from: raw) == nil)
    }
}
