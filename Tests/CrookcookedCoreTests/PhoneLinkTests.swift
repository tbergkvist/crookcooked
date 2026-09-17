import Foundation
import Testing

@testable import CrookcookedCore

/// The phone link runs on networks the owner does not control, so every
/// boundary here — pairing link, command authenticity, replay, request parsing —
/// is load-bearing.
@Suite("Phone link protocol")
struct PhoneLinkTests {
    private let secret = "ABCDEFGHJKLMNPQR"
    private let now = Date(timeIntervalSince1970: 1_789_639_200)

    @Test("The pairing link carries the secret only in the fragment")
    func pairingLinkShape() {
        let link = PairingLink.url(host: "192.168.1.20", port: 47_823, secret: secret)

        #expect(link == "http://192.168.1.20:47823/#k=ABCDEFGHJKLMNPQR")
        #expect(URLComponents(string: link)?.fragment == "k=ABCDEFGHJKLMNPQR")
        #expect(URLComponents(string: link)?.query == nil)
    }

    @Test("A command sealed by the phone page opens on the Mac")
    func opensPhoneSealedCommand() {
        // Produced by Apps/PhoneWeb/pairing.js `sealCommand("disarm", …)`.
        let sealed = "Dy5o6fH2m2QxzOctLYtjJ3OwKqSeTzLeYm30cT4oDL5cZahXdyzPS68uOAhdsTzkc46nY99VcEmebWZFkBvfQW7OweF8WNQpKvFoKOSEse5dRepe1EyFj8LmeVbLl9qVea+Iw0RkkjiwAbclSv2OCyWmg8od9ogK"
        let envelope = PhoneLinkCoding.openCommand(sealed, secret: secret)

        #expect(envelope?.command == .disarm)
        #expect(envelope?.sentAt == ISO8601DateFormatter().date(from: "2026-09-17T10:00:00Z"))
    }

    @Test("Commands sealed with another secret, or not sealed at all, are refused", arguments: [
        "", "not base64", Data("{\"command\":\"disarm\"}".utf8).base64EncodedString(),
    ])
    func refusesForgedCommands(raw: String) {
        #expect(PhoneLinkCoding.openCommand(raw, secret: secret) == nil)
    }

    @Test("A message from the Mac cannot be reflected back as a command")
    func messagesAreNotCommands() throws {
        let message = PhoneMessage(type: .status, status: .disarmed, sentAt: now)
        let sealed = try PhoneLinkCoding.seal(message, secret: secret)

        #expect(PhoneLinkCoding.openCommand(sealed, secret: secret) == nil)
    }

    @Test("A command for one Mac does not open on another")
    func refusesOtherSecret() throws {
        let json = try PhoneLinkCoding.encoder.encode(CommandEnvelope(command: .disarm, sentAt: now))
        let sealed = try LinkCrypto.seal(json, secret: "RQPNMLKJHGFEDCBA").base64EncodedString()

        #expect(PhoneLinkCoding.openCommand(sealed, secret: secret) == nil)
    }

    @Test("A message sealed for the phone opens with the same secret")
    func messageRoundTrips() throws {
        let message = PhoneMessage(type: .status, status: .armed, detail: "Limited: camera", sentAt: now)
        let sealed = try PhoneLinkCoding.seal(message, secret: secret)
        let json = try LinkCrypto.open(#require(Data(base64Encoded: sealed)), secret: secret)

        #expect(try PhoneLinkCoding.decoder.decode(PhoneMessage.self, from: json) == message)
        #expect(!String(decoding: json, as: UTF8.self).contains("frameBase64"))
    }

    @Test("Wire identifiers are stable")
    func rawValuesAreStable() {
        #expect(RemoteCommand.startStream.rawValue == "start_stream")
        #expect(RemoteCommand.stopStream.rawValue == "stop_stream")
        #expect(RemoteCommand.requestSnapshot.rawValue == "request_snapshot")
        #expect(RemoteCommand.silenceAlarm.rawValue == "silence_alarm")
        #expect(PhoneMessageType.notice.rawValue == "notice")
        #expect(CrookcookedStatus.triggered.rawValue == "triggered")
    }

    @Test("A command is accepted once")
    func replayIsRefused() {
        var guardrail = CommandReplayGuard()
        let envelope = CommandEnvelope(id: "one", command: .disarm, sentAt: now)

        let first = guardrail.accept(envelope, now: now)
        let replayed = guardrail.accept(envelope, now: now.addingTimeInterval(1))
        let another = guardrail.accept(CommandEnvelope(id: "two", command: .disarm, sentAt: now), now: now)

        #expect(first)
        #expect(!replayed)
        #expect(another)
    }

    @Test("Stale or future-dated commands are refused")
    func staleCommandsAreRefused() {
        var guardrail = CommandReplayGuard(window: 120)

        let stale = guardrail.accept(CommandEnvelope(id: "old", command: .disarm, sentAt: now.addingTimeInterval(-121)), now: now)
        let future = guardrail.accept(CommandEnvelope(id: "future", command: .disarm, sentAt: now.addingTimeInterval(121)), now: now)
        let drifted = guardrail.accept(CommandEnvelope(id: "drift", command: .disarm, sentAt: now.addingTimeInterval(-60)), now: now)

        #expect(!stale)
        #expect(!future)
        #expect(drifted)
    }
}

@Suite("Local network policy")
struct LocalNetworkPolicyTests {
    private let wifi = LocalNetworkPolicy.Subnet(address: 0xC0A8_0114, mask: 0xFFFF_FF00) // 192.168.1.20/24

    @Test("Phones on the Mac's own subnet, and the Mac itself, are served")
    func allowsLocalPeers() {
        #expect(LocalNetworkPolicy.allowsPeer(0xC0A8_0142, subnets: [wifi])) // 192.168.1.66
        #expect(LocalNetworkPolicy.allowsPeer(0x7F00_0001, subnets: [wifi])) // 127.0.0.1
    }

    @Test("Anyone else on the internet is not")
    func refusesOtherNetworks() {
        #expect(!LocalNetworkPolicy.allowsPeer(0x0808_0808, subnets: [wifi])) // 8.8.8.8
        #expect(!LocalNetworkPolicy.allowsPeer(0xC0A8_0242, subnets: [wifi])) // 192.168.2.66
        #expect(!LocalNetworkPolicy.allowsPeer(0xC0A8_0142, subnets: []))
        #expect(!LocalNetworkPolicy.allowsPeer(0x0808_0808, subnets: [.init(address: 0, mask: 0)]), "a zero mask must not match everything")
    }

    @Test("Only IP-address hosts are accepted, which defeats DNS rebinding", arguments: [
        ("192.168.1.20:47823", true),
        ("192.168.1.20", true),
        ("localhost:47823", true),
        ("attacker.example:47823", false),
        ("192.168.1.20.attacker.example", false),
        ("192.168.1", false),
        ("", false),
    ])
    func hostHeader(host: String, allowed: Bool) {
        #expect(LocalNetworkPolicy.allowsHost(host) == allowed)
    }

    @Test("A request without a Host is refused")
    func missingHost() {
        #expect(!LocalNetworkPolicy.allowsHost(nil))
    }
}

@Suite("Local address choice")
struct LocalAddressPickerTests {
    private typealias Candidate = LocalAddressPicker.Candidate

    @Test("Wi-Fi wins over bridges, and unusable addresses are skipped")
    func picksReachableAddress() {
        let picked = LocalAddressPicker.pick(from: [
            Candidate(interface: "lo0", address: "127.0.0.1"),
            Candidate(interface: "utun4", address: "10.8.0.2"),
            Candidate(interface: "bridge100", address: "192.168.2.1"),
            Candidate(interface: "en5", address: "169.254.10.3"),
            Candidate(interface: "en0", address: "192.168.1.20"),
        ])

        #expect(picked == "192.168.1.20")
    }

    @Test("A personal hotspot address is usable")
    func acceptsHotspot() {
        #expect(LocalAddressPicker.pick(from: [Candidate(interface: "en0", address: "172.20.10.3")]) == "172.20.10.3")
    }

    @Test("No usable interface means no pairing link")
    func nothingUsable() {
        #expect(LocalAddressPicker.pick(from: [Candidate(interface: "lo0", address: "127.0.0.1")]) == nil)
    }
}

@Suite("HTTP request parsing")
struct HTTPRequestHeadTests {
    @Test("A GET with a query parses")
    func parsesGet() {
        let raw = Data("GET /events?t=abc HTTP/1.1\r\nHost: 192.168.1.20\r\n\r\n".utf8)

        guard case .complete(let head, let offset) = HTTPRequestHead.parse(raw) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(head.method == "GET")
        #expect(head.path == "/events")
        #expect(head.query["t"] == "abc")
        #expect(head.host == "192.168.1.20")
        #expect(offset == raw.count)
    }

    @Test("A POST reports its body length and where the body starts")
    func parsesPost() {
        let raw = Data("POST /command HTTP/1.1\r\nContent-Length: 4\r\n\r\nbody".utf8)

        guard case .complete(let head, let offset) = HTTPRequestHead.parse(raw) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(head.contentLength == 4)
        #expect(raw.dropFirst(offset) == Data("body".utf8))
    }

    @Test("A partial head waits for more bytes")
    func waitsForMore() {
        #expect(HTTPRequestHead.parse(Data("GET / HTTP/1.1\r\nHost:".utf8)) == .incomplete)
    }

    @Test("Malformed requests are refused", arguments: [
        "GARBAGE\r\n\r\n",
        "GET noslash HTTP/1.1\r\n\r\n",
        "GET / SPDY/3\r\n\r\n",
        "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "GET / HTTP/1.1\r\nno colon here\r\n\r\n",
        "GET / HTTP/1.1\r\nHost: 192.168.1.20\r\nHost: attacker.example\r\n\r\n",
        "POST /command HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
    ])
    func refusesMalformed(raw: String) {
        #expect(HTTPRequestHead.parse(Data(raw.utf8)) == .invalid)
    }

    @Test("An endless head is refused rather than buffered forever")
    func refusesOversizedHead() {
        let raw = Data(("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequestHead.maximumHeadBytes)).utf8)

        #expect(HTTPRequestHead.parse(raw) == .invalid)
    }
}

@Suite("Protection readiness")
struct ProtectionReadinessTests {
    @Test("Full permissions report no gaps")
    func completeReadiness() {
        let ready = ProtectionReadiness(inputMonitoring: true, cameraAccess: true, cameraFeaturesEnabled: true, canLockUnattended: true)

        #expect(ready.isComplete)
        #expect(ready.summary == nil)
        #expect(ready.remoteArmRefusal == nil)
    }

    @Test("Each missing permission is named")
    func namesGaps() {
        let limited = ProtectionReadiness(inputMonitoring: false, cameraAccess: false, cameraFeaturesEnabled: true, canLockUnattended: true)

        #expect(limited.limitations.count == 2)
        #expect(limited.summary?.contains("Input Monitoring") == true)
        #expect(limited.summary?.contains("camera") == true)
    }

    @Test("Camera access does not matter when every camera feature is off")
    func cameraGapNeedsCameraFeatures() {
        let noCamera = ProtectionReadiness(inputMonitoring: true, cameraAccess: false, cameraFeaturesEnabled: false, canLockUnattended: true)

        #expect(noCamera.isComplete)
    }

    @Test("A Mac that needs a key press to lock refuses remote arming")
    func remoteArmNeedsUnattendedLock() {
        let manual = ProtectionReadiness(inputMonitoring: true, cameraAccess: true, cameraFeaturesEnabled: true, canLockUnattended: false)

        #expect(manual.remoteArmRefusal != nil)
    }
}

@Suite("Configuration store")
struct ConfigurationStoreTests {
    private func makeStore() throws -> (ConfigurationStore, URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "crookcooked.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (ConfigurationStore(defaults: defaults, directory: directory), directory, defaults)
    }

    @Test("The secret persists outside UserDefaults, readable only by the owner")
    func secretLivesInOwnerOnlyFile() throws {
        let (store, directory, defaults) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = store.load()
        let file = directory.appendingPathComponent("pairing-secret")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int

        #expect(first.pairingSecret.count >= PairingSecret.minimumLength)
        #expect(ConfigurationStore(defaults: defaults, directory: directory).load().pairingSecret == first.pairingSecret)
        #expect(permissions == 0o600)
        #expect(defaults.data(forKey: "crookcooked.configuration.v1").map { String(decoding: $0, as: UTF8.self).contains(first.pairingSecret) } == false)
    }

    @Test("Regenerating the secret replaces the stored one")
    func regeneratedSecretIsSaved() throws {
        let (store, directory, defaults) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var configuration = store.load()
        configuration.pairingSecret = "RQPNMLKJHGFEDCBA"
        store.save(configuration)

        #expect(ConfigurationStore(defaults: defaults, directory: directory).load().pairingSecret == "RQPNMLKJHGFEDCBA")
    }
}
