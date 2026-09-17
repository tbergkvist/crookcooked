import Foundation
import Testing

@testable import CrookcookedCore

/// The scorer decides whether the alarm fires. Under-triggering loses evidence;
/// over-triggering trains the owner to ignore the product, so both directions matter.
@Suite("Threat scoring")
struct ThreatScorerTests {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ kind: ThreatKind, at offset: TimeInterval) -> CrookcookedEvent {
        CrookcookedEvent(kind: kind, occurredAt: origin.addingTimeInterval(offset))
    }

    @Test("A single weak camera change does not trigger on its own")
    func loneCameraChangeIsNotEnough() async {
        let scorer = ThreatScorer(threshold: 75)
        let result = await scorer.evaluate(event(.cameraMovement, at: 0))

        #expect(result.combinedScore == 72)
        #expect(!result.shouldTrigger)
    }

    @Test("A strong single signal triggers at the default threshold")
    func usbAloneTriggers() async {
        let scorer = ThreatScorer(threshold: 70)
        let result = await scorer.evaluate(event(.usbAttached, at: 0))

        #expect(result.combinedScore == 85)
        #expect(result.shouldTrigger)
    }

    @Test("A different signal within the window corroborates a weak one")
    func correlatedSignalsCombine() async {
        let scorer = ThreatScorer(threshold: 75)

        let first = await scorer.evaluate(event(.cameraMovement, at: 0))
        #expect(!first.shouldTrigger)

        // 75 (power) + 72/2 (camera corroboration) = 111, clamped to 100.
        let second = await scorer.evaluate(event(.powerDisconnected, at: 1))
        #expect(second.combinedScore == 100)
        #expect(second.shouldTrigger)
    }

    @Test("Repeats of the same signal do not corroborate themselves")
    func sameKindDoesNotCorroborate() async {
        let scorer = ThreatScorer(threshold: 75)

        _ = await scorer.evaluate(event(.cameraMovement, at: 0))
        let repeated = await scorer.evaluate(event(.cameraMovement, at: 1))

        #expect(repeated.combinedScore == 72)
        #expect(!repeated.shouldTrigger)
    }

    @Test("Signals older than the correlation window are discarded")
    func staleSignalsExpire() async {
        let scorer = ThreatScorer(threshold: 70, correlationWindow: 4)

        _ = await scorer.evaluate(event(.cameraMovement, at: 0))
        let later = await scorer.evaluate(event(.powerDisconnected, at: 10))

        // No corroboration survives, so this is the bare power-disconnect score.
        #expect(later.combinedScore == 75)
    }

    @Test("A signal exactly at the window edge still corroborates")
    func windowBoundaryIsInclusive() async {
        let scorer = ThreatScorer(threshold: 70, correlationWindow: 4)

        _ = await scorer.evaluate(event(.cameraMovement, at: 0))
        let atEdge = await scorer.evaluate(event(.powerDisconnected, at: 4))

        #expect(atEdge.combinedScore == 100)
    }

    @Test("The combined score never exceeds 100")
    func combinedScoreIsClamped() async {
        let scorer = ThreatScorer(threshold: 70)

        _ = await scorer.evaluate(event(.remoteRequest, at: 0))
        let second = await scorer.evaluate(event(.manualTest, at: 1))

        #expect(second.combinedScore == 100)
    }

    @Test("Resetting clears corroboration history")
    func resetClearsHistory() async {
        let scorer = ThreatScorer(threshold: 75)

        _ = await scorer.evaluate(event(.cameraMovement, at: 0))
        await scorer.reset()
        let afterReset = await scorer.evaluate(event(.cameraMovement, at: 1))

        #expect(afterReset.combinedScore == 72)
        #expect(!afterReset.shouldTrigger)
    }

    @Test("An explicit score overrides the kind's base score")
    func explicitScoreWins() async {
        let scorer = ThreatScorer(threshold: 70)
        let quiet = CrookcookedEvent(kind: .usbAttached, occurredAt: origin, score: 10)

        let result = await scorer.evaluate(quiet)

        #expect(result.combinedScore == 10)
        #expect(!result.shouldTrigger)
    }
}
