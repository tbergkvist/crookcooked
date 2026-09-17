import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

@MainActor
final class SystemLockService {
    enum LockError: LocalizedError {
        case unavailable
        case verificationTimedOut

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "The native lock service is unavailable and Accessibility is not enabled."
            case .verificationTimedOut:
                return "macOS did not confirm that the session was locked. crookcooked was not armed."
            }
        }
    }

    enum Method: String {
        case appleLoginFramework = "Apple login service"
        case systemKeyboardShortcut = "Control–Command–Q"
        case manualSystemShortcut = "owner Control–Command–Q"
    }

    var onUnlock: (() -> Void)?
    private(set) var lastMethod: Method?

    private typealias LockFunction = @convention(c) () -> Void
    private typealias ScreenSaverStateFunction = @convention(c) () -> Int32
    private let loginFramework: UnsafeMutableRawPointer?
    private let lockFunction: LockFunction?
    private let screenSaverStateFunction: ScreenSaverStateFunction?
    private var wasLocked = false
    private var stateTimer: Timer?
    private var lockedObserver: NSObjectProtocol?
    private var unlockedObserver: NSObjectProtocol?

    init() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/A/login"
        loginFramework = dlopen(path, RTLD_LAZY | RTLD_LOCAL)
        if let loginFramework, let symbol = dlsym(loginFramework, "SACLockScreenImmediate") {
            lockFunction = unsafeBitCast(symbol, to: LockFunction.self)
        } else {
            lockFunction = nil
        }
        if let loginFramework, let symbol = dlsym(loginFramework, "SACScreenSaverIsRunning") {
            screenSaverStateFunction = unsafeBitCast(symbol, to: ScreenSaverStateFunction.self)
        } else {
            screenSaverStateFunction = nil
        }

        let center = DistributedNotificationCenter.default()
        lockedObserver = center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wasLocked = true }
        }
        unlockedObserver = center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleUnlock() }
        }
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollState() }
        }
    }

    deinit {
        stateTimer?.invalidate()
        let center = DistributedNotificationCenter.default()
        if let lockedObserver { center.removeObserver(lockedObserver) }
        if let unlockedObserver { center.removeObserver(unlockedObserver) }
        if let loginFramework { dlclose(loginFramework) }
    }

    var nativeServiceAvailable: Bool { lockFunction != nil }

    func requestAndVerifyLock(manualPrompt: @escaping @MainActor () -> Void) async throws -> Method {
        wasLocked = false
        if let lockFunction {
            lockFunction()
            if await waitForLock(timeout: .seconds(1.5)) {
                lastMethod = .appleLoginFramework
                return .appleLoginFramework
            }
        }

        if AXIsProcessTrusted() {
            postSystemLockShortcut()
            if await waitForLock(timeout: .seconds(6)) {
                lastMethod = .systemKeyboardShortcut
                return .systemKeyboardShortcut
            }
        }

        manualPrompt()
        if await waitForLock(timeout: .seconds(30)) {
            lastMethod = .manualSystemShortcut
            return .manualSystemShortcut
        }
        throw AXIsProcessTrusted() ? LockError.verificationTimedOut : LockError.unavailable
    }

    private func waitForLock(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if isSessionLocked {
                wasLocked = true
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    var isSessionLocked: Bool {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            for key in ["CGSSessionScreenIsLocked", "kCGSSessionScreenIsLockedKey"] {
                if let value = session[key] as? Bool, value { return true }
                if let value = session[key] as? NSNumber, value.boolValue { return true }
            }
        }
        return screenSaverStateFunction?() != 0
    }

    private func postSystemLockShortcut() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: false)
        else { return }
        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags = [.maskCommand, .maskControl]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func pollState() {
        let locked = isSessionLocked
        if wasLocked && !locked { handleUnlock() }
        wasLocked = locked
    }

    private func handleUnlock() {
        guard wasLocked else { return }
        wasLocked = false
        onUnlock?()
    }
}
