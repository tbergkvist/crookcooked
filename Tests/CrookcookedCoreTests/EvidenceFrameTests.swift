import Foundation
import Testing

@testable import CrookcookedCore

/// Snapshot refresh and live streaming are deliberately decoupled: a trigger must
/// send a *recent* frame, while an idle phone must not receive a video feed.
/// Collapsing the two is how stale evidence — or a silent privacy leak — appears.
@Suite("Evidence frame policy")
struct EvidenceFramePolicyTests {
    @Test("A stale snapshot refreshes even when nobody is watching")
    func refreshesWithoutStreaming() {
        let disposition = EvidenceFramePolicy.disposition(
            streamingEnabled: false,
            secondsSinceLastRefresh: 1.0
        )

        #expect(disposition.refreshSnapshot)
        #expect(!disposition.publishToLiveStream)
    }

    @Test("A fresh snapshot is left alone")
    func skipsRefreshWhenFresh() {
        let disposition = EvidenceFramePolicy.disposition(
            streamingEnabled: true,
            secondsSinceLastRefresh: 0.1
        )

        #expect(!disposition.refreshSnapshot)
        #expect(!disposition.publishToLiveStream)
    }

    @Test("The refresh interval boundary counts as due")
    func boundaryIsDue() {
        let disposition = EvidenceFramePolicy.disposition(
            streamingEnabled: false,
            secondsSinceLastRefresh: EvidenceFramePolicy.refreshInterval
        )

        #expect(disposition.refreshSnapshot)
    }

    @Test("Frames reach the phone only while streaming is on")
    func publishesOnlyWhileStreaming() {
        let watching = EvidenceFramePolicy.disposition(
            streamingEnabled: true,
            secondsSinceLastRefresh: 1.0
        )

        #expect(watching.refreshSnapshot)
        #expect(watching.publishToLiveStream)
    }

    @Test("Publishing never happens without a refresh")
    func neverPublishesAStaleFrame() {
        var published = 0

        for streaming in [true, false] {
            for elapsed in [0.0, 0.25, 0.49, 0.5, 1.0, 30.0] {
                let disposition = EvidenceFramePolicy.disposition(
                    streamingEnabled: streaming,
                    secondsSinceLastRefresh: elapsed
                )

                if disposition.publishToLiveStream {
                    published += 1
                    #expect(disposition.refreshSnapshot)
                    #expect(streaming)
                }
            }
        }

        // Guard against the invariant holding only because nothing ever published.
        #expect(published == 3)
    }
}

/// The cache is what a trigger actually reads from, so a stop must leave nothing
/// behind for a later session to send by mistake.
@Suite("Evidence frame cache")
struct EvidenceFrameCacheTests {
    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A new cache holds nothing and reads as indefinitely stale")
    func startsEmpty() {
        let cache = EvidenceFrameCache()

        #expect(cache.latestFrame == nil)
        #expect(cache.refreshedAt == .distantPast)
    }

    @Test("Storing a frame records it with its capture time")
    func storesFrame() {
        var cache = EvidenceFrameCache()
        let frame = Data([0x01, 0x02, 0x03])

        cache.store(frame, at: origin)

        #expect(cache.latestFrame == frame)
        #expect(cache.refreshedAt == origin)
    }

    @Test("A newer frame replaces the previous one")
    func replacesOlderFrame() {
        var cache = EvidenceFrameCache()

        cache.store(Data([0x01]), at: origin)
        cache.store(Data([0x02]), at: origin.addingTimeInterval(1))

        #expect(cache.latestFrame == Data([0x02]))
        #expect(cache.refreshedAt == origin.addingTimeInterval(1))
    }

    @Test("Resetting clears the frame so a later session cannot send it")
    func resetClearsEverything() {
        var cache = EvidenceFrameCache()
        cache.store(Data([0x01]), at: origin)

        cache.reset()

        #expect(cache.latestFrame == nil)
        #expect(cache.refreshedAt == .distantPast)
    }
}
