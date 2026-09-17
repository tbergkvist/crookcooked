import Foundation
import CrookcookedCore

@main
struct CrookcookedCoreChecks {
    static func main() async throws {
        let standard = CrookcookedConfiguration.standard
        precondition(standard.audibleAlarm, "Shipped defaults must arm the audible alarm")
        precondition(standard.armingDelaySeconds == 5)
        precondition(standard.recordEvidence)
        precondition(standard.faceAttentionWarning)
        precondition(standard.lockScreenAvatar, "The lock screen avatar ships on")

        // Quiet mode must remain reachable and must silence nothing but the alarm.
        let quiet = CrookcookedConfiguration.quiet
        precondition(!quiet.audibleAlarm, "Quiet mode must not sound the alarm")
        precondition(quiet.recordEvidence, "Quiet mode must still gather evidence")
        precondition(quiet.cameraMovementDetection, "Quiet mode must still watch the camera")

        let legacyJSON = Data(#"{"audibleAlarm":false,"triggerThreshold":70,"armingDelaySeconds":8,"recordEvidence":true,"cameraMovementDetection":true,"relayURL":"ws://127.0.0.1:8787","pairingSecret":"OLDSECRET"}"#.utf8)
        let migrated = try JSONDecoder().decode(CrookcookedConfiguration.self, from: legacyJSON)
        precondition(migrated.faceAttentionWarning, "Older preferences should enable the on-device warning by default")

        let strongScorer = ThreatScorer(threshold: 70)
        let strong = await strongScorer.evaluate(CrookcookedEvent(kind: .usbAttached))
        precondition(strong.shouldTrigger && strong.combinedScore == 85)

        let weakScorer = ThreatScorer(threshold: 75)
        let weak = await weakScorer.evaluate(CrookcookedEvent(kind: .cameraMovement))
        precondition(!weak.shouldTrigger)

        let inputScorer = ThreatScorer(threshold: 70)
        let input = await inputScorer.evaluate(CrookcookedEvent(kind: .keyboardOrPointer))
        precondition(input.shouldTrigger && input.combinedScore == 80)

        // The QR path is now the main way a phone gets paired.
        let pairing = PairingPayload(relayURL: "wss://relay.example.com", secret: PairingSecret.generate())
        precondition(PairingPayload.decode(pairing.encoded) == pairing, "Pairing links must round-trip")
        precondition(PairingPayload.decode("https://example.com") == nil, "Foreign QR codes must be refused")

        let first = PairingSecret.displayCode(from: "ABCDEFGHIJKLMNOP")
        precondition(first == PairingSecret.displayCode(from: "ABCDEFGHIJKLMNOP") && first.count == 6)

        let original = RelayMessage.hello(secret: "SECRET", role: .mac, deviceID: "mac-1")
        let data = try RelayCoding.encoder.encode(original)
        let decoded = try RelayCoding.decoder.decode(RelayMessage.self, from: data)
        precondition(decoded.type == .hello && decoded.roomID == PairingSecret.roomID(from: "SECRET") && decoded.role == .mac)

        precondition(RelayEndpoint.validatedURL(from: " ws://127.0.0.1:8787 ")?.absoluteString == "ws://127.0.0.1:8787")
        precondition(RelayEndpoint.validatedURL(from: "q") == nil)
        precondition(RelayEndpoint.validatedURL(from: "https://example.com") == nil)

        let evidence = Data("camera bytes".utf8)
        let sealed = try EvidenceCrypto.seal(evidence, secret: "SECRET")
        let opened = try EvidenceCrypto.open(sealed, secret: "SECRET")
        precondition(sealed != evidence)
        precondition(opened == evidence)

        let idleFrame = EvidenceFramePolicy.disposition(
            streamingEnabled: false,
            secondsSinceLastRefresh: EvidenceFramePolicy.refreshInterval
        )
        precondition(idleFrame.refreshSnapshot, "Armed camera must keep the alert snapshot current while live streaming is off")
        precondition(!idleFrame.publishToLiveStream, "Refreshing alert evidence must not publish an unsolicited live frame")

        let throttledStreamFrame = EvidenceFramePolicy.disposition(
            streamingEnabled: true,
            secondsSinceLastRefresh: EvidenceFramePolicy.refreshInterval / 2
        )
        precondition(!throttledStreamFrame.refreshSnapshot && !throttledStreamFrame.publishToLiveStream)

        let dueStreamFrame = EvidenceFramePolicy.disposition(
            streamingEnabled: true,
            secondsSinceLastRefresh: EvidenceFramePolicy.refreshInterval
        )
        precondition(dueStreamFrame.refreshSnapshot && dueStreamFrame.publishToLiveStream)

        var frameCache = EvidenceFrameCache()
        let frameDate = Date()
        frameCache.store(evidence, at: frameDate)
        precondition(frameCache.latestFrame == evidence && frameCache.refreshedAt == frameDate)
        frameCache.reset()
        precondition(frameCache.latestFrame == nil, "Stopping capture must discard evidence from the prior armed session")
        precondition(frameCache.refreshedAt == .distantPast, "Restarted capture must refresh before evidence can be sent")

        print("CrookcookedCore checks passed (loud default, reachable quiet mode, pairing codec).")
    }
}
