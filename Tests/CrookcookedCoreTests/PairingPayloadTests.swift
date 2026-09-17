import Foundation
import Testing

@testable import CrookcookedCore

/// The QR code is the way a phone gets paired: the iPhone Camera app opens it as
/// a web page served by the relay. This codec decides what that link contains.
@Suite("Pairing payload")
struct PairingPayloadTests {
    private let payload = PairingPayload(
        relayURL: "wss://relay.example.com",
        secret: "ABCDEFGHJKLMNPQR"
    )

    @Test("A payload survives the trip through a QR code")
    func roundTrips() {
        #expect(PairingPayload.decode(payload.encoded) == payload)
    }

    @Test("The encoded form is a web link to the relay with the secret in the fragment")
    func usesWebLink() {
        #expect(payload.encoded == "https://relay.example.com/#k=ABCDEFGHJKLMNPQR")
        #expect(PairingPayload(relayURL: "ws://192.168.1.20:8787", secret: "ABCDEFGHJKLMNPQR").encoded
                == "http://192.168.1.20:8787/#k=ABCDEFGHJKLMNPQR")
    }

    @Test("Relay paths are kept, queries are dropped")
    func keepsPath() {
        let proxied = PairingPayload(relayURL: "wss://example.com/crookcooked/?x=1", secret: "ABCDEFGHJKLMNPQR")
        #expect(proxied.encoded == "https://example.com/crookcooked/#k=ABCDEFGHJKLMNPQR")
    }

    @Test("Surrounding whitespace is tolerated")
    func trimsWhitespace() {
        #expect(PairingPayload.decode("  \(payload.encoded)\n") == payload)
    }

    @Test("Unrelated QR codes are refused", arguments: [
        "https://example.com",
        "https://example.com/#section",
        "hello world",
        "",
        "ftp://relay.example.com/#k=ABCDEFGHJKLMNPQR",
        "https://user:pw@relay.example.com/#k=ABCDEFGHJKLMNPQR",
    ])
    func rejectsForeignCodes(raw: String) {
        // Scanning a poster, a wifi code, or another app's link must do nothing.
        #expect(PairingPayload.decode(raw) == nil)
    }

    @Test("An invalid relay URL produces no link")
    func invalidRelayProducesNoLink() {
        #expect(PairingPayload(relayURL: "relay.example.com", secret: "ABCDEFGHJKLMNPQR").encoded == "")
    }

    @Test("A short secret is refused")
    func rejectsShortSecret() {
        let encoded = PairingPayload(relayURL: "wss://relay.example.com", secret: "SHORT").encoded

        #expect(PairingPayload.decode(encoded) == nil)
    }

    @Test("Loopback relays are flagged as unreachable from a phone", arguments: [
        ("ws://127.0.0.1:8787", false),
        ("ws://localhost:8787", false),
        ("ws://192.168.1.20:8787", true),
        ("wss://relay.example.com", true),
    ])
    func flagsLoopback(relay: String, reachable: Bool) {
        #expect(PairingPayload(relayURL: relay, secret: "ABCDEFGHJKLMNPQR").isReachableFromPhone == reachable)
    }

    @Test("Every generated secret is long enough to pair with")
    func generatedSecretsPair() {
        // The generator's floor and the decoder's minimum must not drift apart.
        let generated = PairingSecret.generate()
        let encoded = PairingPayload(relayURL: "wss://relay.example.com", secret: generated).encoded

        #expect(PairingPayload.decode(encoded)?.secret == generated)
        #expect(generated.count >= PairingPayload.minimumSecretLength)
    }

    @Test("A scanned payload reaches the same room as the Mac")
    func scannedPayloadJoinsTheSameRoom() {
        let scanned = PairingPayload.decode(payload.encoded)

        #expect(scanned.map { PairingSecret.roomID(from: $0.secret) }
                == PairingSecret.roomID(from: payload.secret))
    }
}
