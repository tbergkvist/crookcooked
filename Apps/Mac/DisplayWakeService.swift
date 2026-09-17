import Foundation
import IOKit.pwr_mgt
import OSLog

final class DisplayWakeService {
    private var assertionID: IOPMAssertionID = 0
    private var active = false
    private let logger = Logger(subsystem: "app.crookcooked.mac.local", category: "DisplayWake")

    @discardableResult
    func start() -> Bool {
        guard !active else { return true }
        var newID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "crookcooked is armed" as CFString,
            &newID
        )
        guard result == kIOReturnSuccess else {
            logger.error("Could not prevent idle display sleep: \(result)")
            return false
        }
        assertionID = newID
        active = true
        logger.info("Idle display sleep prevention enabled")
        return true
    }

    func stop() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        active = false
        logger.info("Idle display sleep prevention released")
    }

    deinit {
        if active { IOPMAssertionRelease(assertionID) }
    }
}
