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

        // The QR code is how a phone pairs: a link whose fragment carries the secret.
        let secret = PairingSecret.generate()
        let link = PairingLink.url(host: "192.168.1.20", port: 47_823, secret: secret)
        precondition(URLComponents(string: link)?.fragment == "k=\(secret)", "The secret must travel only in the fragment")

        let first = PairingSecret.displayCode(from: "ABCDEFGHIJKLMNOP")
        precondition(first == PairingSecret.displayCode(from: "ABCDEFGHIJKLMNOP") && first.count == 6)

        let evidence = Data("camera bytes".utf8)
        let sealed = try LinkCrypto.seal(evidence, secret: "SECRET")
        precondition(sealed != evidence)
        let opened = try LinkCrypto.open(sealed, secret: "SECRET")
        precondition(opened == evidence)

        let command = try LinkCrypto.seal(PhoneLinkCoding.encoder.encode(CommandEnvelope(command: .disarm)), secret: "SECRET")
        precondition(PhoneLinkCoding.openCommand(command.base64EncodedString(), secret: "SECRET")?.command == .disarm)
        precondition(PhoneLinkCoding.openCommand(command.base64EncodedString(), secret: "OTHER") == nil, "Commands must be authenticated")

        var replayGuard = CommandReplayGuard()
        let envelope = CommandEnvelope(command: .disarm)
        precondition(replayGuard.accept(envelope) && !replayGuard.accept(envelope), "A captured command must not work twice")

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

        print("CrookcookedCore checks passed (loud default, reachable quiet mode, pairing link, authenticated commands).")
    }
}
