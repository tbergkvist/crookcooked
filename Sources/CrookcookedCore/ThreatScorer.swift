import Foundation

/// Combines weak signals that occur close together without making a single
/// camera change or accidental pointer event immediately fire the alarm.
public actor ThreatScorer {
    private let threshold: Int
    private let correlationWindow: TimeInterval
    private var recent: [CrookcookedEvent] = []

    public init(threshold: Int = 70, correlationWindow: TimeInterval = 4) {
        self.threshold = threshold
        self.correlationWindow = correlationWindow
    }

    public func evaluate(_ event: CrookcookedEvent) -> (shouldTrigger: Bool, combinedScore: Int) {
        recent.removeAll { event.occurredAt.timeIntervalSince($0.occurredAt) > correlationWindow }

        let corroborating = recent
            .filter { $0.kind != event.kind }
            .map(\.score)
            .max() ?? 0
        let combined = min(100, event.score + corroborating / 2)
        recent.append(event)
        return (combined >= threshold, combined)
    }

    public func reset() {
        recent.removeAll()
    }
}

