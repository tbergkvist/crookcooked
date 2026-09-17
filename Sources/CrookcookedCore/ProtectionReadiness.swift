import Foundation

/// What the Mac can actually watch right now. Arming is still allowed with gaps —
/// power and USB need no permission — but the status must say what is missing
/// instead of claiming full protection.
public struct ProtectionReadiness: Equatable, Sendable {
    public var inputMonitoring: Bool
    public var cameraAccess: Bool
    public var cameraFeaturesEnabled: Bool
    /// Whether the Mac can lock itself without the owner pressing Control–Command–Q.
    public var canLockUnattended: Bool

    public init(inputMonitoring: Bool, cameraAccess: Bool, cameraFeaturesEnabled: Bool, canLockUnattended: Bool) {
        self.inputMonitoring = inputMonitoring
        self.cameraAccess = cameraAccess
        self.cameraFeaturesEnabled = cameraFeaturesEnabled
        self.canLockUnattended = canLockUnattended
    }

    /// Protection gaps while armed, phrased for the owner.
    public var limitations: [String] {
        var gaps: [String] = []
        if !inputMonitoring { gaps.append("keyboard and trackpad are not watched (Input Monitoring is off)") }
        if cameraFeaturesEnabled && !cameraAccess { gaps.append("no camera movement detection or evidence (camera access is off)") }
        return gaps
    }

    public var isComplete: Bool { limitations.isEmpty }

    /// One line for the phone and the menu bar, or nil when nothing is missing.
    public var summary: String? {
        let gaps = limitations
        guard !gaps.isEmpty else { return nil }
        return "Limited: " + gaps.joined(separator: "; ")
    }

    /// Why a phone cannot arm this Mac, or nil when it can.
    public var remoteArmRefusal: String? {
        canLockUnattended ? nil : "This Mac cannot lock itself remotely. Arm it on the Mac, or turn on Accessibility for crookcooked."
    }
}
