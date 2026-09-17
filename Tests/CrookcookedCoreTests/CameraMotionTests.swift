import Testing

@testable import CrookcookedCore

/// Looking at the Mac must never sound the alarm; moving it must.
@Suite("Camera motion")
struct CameraMotionTests {
    private typealias Shift = CameraMotionDetector.Shift

    @Test("Both sides shifting the same way, twice, means the Mac moved")
    func sustainedSharedShiftIsMovement() {
        var detector = CameraMotionDetector()
        let turned = Shift(x: 0.12, y: 0.01)

        let first = detector.observe(left: turned, right: turned)
        let second = detector.observe(left: turned, right: turned)

        #expect(!first)
        #expect(second)
    }

    @Test("A person covering one side is not movement")
    func oneSidedChangeIsIgnored() {
        var detector = CameraMotionDetector()
        let results = (0..<5).map { _ in detector.observe(left: Shift(x: 0.2, y: 0.1), right: Shift(x: 0.002, y: 0)) }

        #expect(!results.contains(true))
    }

    @Test("Sides shifting in opposite directions are not movement")
    func opposingShiftsAreIgnored() {
        var detector = CameraMotionDetector()
        let results = (0..<5).map { _ in detector.observe(left: Shift(x: 0.1, y: 0), right: Shift(x: -0.1, y: 0)) }

        #expect(!results.contains(true))
    }

    @Test("Camera noise below the threshold is not movement")
    func jitterIsIgnored() {
        var detector = CameraMotionDetector()
        let results = (0..<5).map { _ in detector.observe(left: Shift(x: 0.01, y: 0.01), right: Shift(x: 0.01, y: 0.01)) }

        #expect(!results.contains(true))
    }

    @Test("A still check in between restarts the count")
    func interruptedStreakStartsOver() {
        var detector = CameraMotionDetector()
        let moved = Shift(x: 0, y: 0.1)

        let first = detector.observe(left: moved, right: moved)
        let still = detector.observe(left: Shift(x: 0, y: 0), right: Shift(x: 0, y: 0))
        let again = detector.observe(left: moved, right: moved)

        #expect(!first && !still && !again)
    }

    @Test("A failed alignment counts as no movement")
    func missingMeasurementIsNotMovement() {
        var detector = CameraMotionDetector()

        let first = detector.observe(left: nil, right: Shift(x: 0.2, y: 0))
        let second = detector.observe(left: nil, right: Shift(x: 0.2, y: 0))

        #expect(!first && !second)
    }
}
