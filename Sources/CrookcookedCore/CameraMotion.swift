import Foundation

/// Decides whether the Mac itself moved, from how the camera image shifted.
///
/// Someone walking up to the Mac or leaning in to look changes part of the
/// picture; picking the Mac up, turning it, or tilting the lid shifts all of it.
/// So a strip at each side of the frame is aligned against a reference taken
/// when watching started: only when both strips are displaced the same way, far
/// enough, in consecutive checks, does it count. A person usually covers at most
/// one side, and never moves the background behind them. Comparing with the
/// reference rather than the previous frame also catches one quick lift that is
/// over between two checks.
public struct CameraMotionDetector: Sendable {
    /// A strip's displacement from the reference, in fractions of the frame's width and height.
    public struct Shift: Equatable, Sendable {
        public let x: Double
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        var magnitude: Double { (x * x + y * y).squareRoot() }
    }

    /// Minimum shift of each strip, as a fraction of the frame.
    public let threshold: Double
    /// Consecutive shifted analyses needed, so one bumped table does not count.
    public let requiredStreak: Int
    private var streak = 0

    /// 0.04 of the frame is roughly a three-degree turn of a laptop camera.
    public init(threshold: Double = 0.04, requiredStreak: Int = 2) {
        self.threshold = threshold
        self.requiredStreak = requiredStreak
    }

    /// Feeds one pair of strip shifts. Returns true when the Mac should be
    /// treated as moved; the streak then starts over.
    public mutating func observe(left: Shift?, right: Shift?) -> Bool {
        guard let left, let right,
              left.magnitude >= threshold, right.magnitude >= threshold,
              // Same direction: a person crossing in front drags the strips apart.
              left.x * right.x + left.y * right.y > 0
        else {
            streak = 0
            return false
        }
        streak += 1
        guard streak >= requiredStreak else { return false }
        streak = 0
        return true
    }

    public mutating func reset() {
        streak = 0
    }
}
