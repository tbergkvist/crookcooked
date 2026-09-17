import AppKit
import CrookcookedCore

@MainActor
enum CrookcookedTerminationGuard {
    static var status: CrookcookedStatus = .disarmed
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch CrookcookedTerminationGuard.status {
        case .arming, .armed, .triggered:
            return .terminateCancel
        case .disarmed:
            return .terminateNow
        }
    }
}
