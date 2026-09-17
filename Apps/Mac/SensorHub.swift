import AppKit
import ApplicationServices
import Foundation
import IOKit
import IOKit.ps
import CrookcookedCore

final class SensorHub {
    var onEvent: ((CrookcookedEvent) -> Void)?

    private var eventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var timer: DispatchSourceTimer?
    private var initialUSBIDs: Set<UInt64> = []
    private var wasOnACPower: Bool?
    private var lastInputEvent = Date.distantPast

    static func requestInputPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func start() {
        guard timer == nil else { return }
        initialUSBIDs = currentUSBIDs()
        wasOnACPower = isOnACPower()

        installInputMonitor()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.pollPhysicalConnections() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTap = nil
        eventTapSource = nil
        timer?.cancel()
        timer = nil
        initialUSBIDs.removeAll()
        wasOnACPower = nil
    }

    private func installInputMonitor() {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<SensorHub>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = monitor.eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            } else {
                monitor.handleInput(type)
            }
            return Unmanaged.passUnretained(event)
        }

        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            eventTapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }

        // Compatibility fallback for systems that grant AppKit monitoring but
        // reject a HID-level tap. No key values or characters are inspected.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel]
        ) { [weak self] event in
            self?.handleInput(CGEventType(rawValue: UInt32(event.type.rawValue)) ?? .null)
        }
    }

    private func handleInput(_ type: CGEventType) {
        guard Date().timeIntervalSince(lastInputEvent) > 1 else { return }
        lastInputEvent = Date()
        onEvent?(CrookcookedEvent(kind: .keyboardOrPointer, detail: "Physical input event: \(type.rawValue)"))
    }

    private func pollPhysicalConnections() {
        let ids = currentUSBIDs()
        let added = ids.subtracting(initialUSBIDs)
        if !added.isEmpty {
            onEvent?(CrookcookedEvent(kind: .usbAttached, detail: "A new USB device appeared"))
        }
        initialUSBIDs = ids

        let onAC = isOnACPower()
        if wasOnACPower == true && onAC == false {
            onEvent?(CrookcookedEvent(kind: .powerDisconnected, detail: "Charging power was removed"))
        }
        wasOnACPower = onAC
    }

    private func currentUSBIDs() -> Set<UInt64> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var ids = Set<UInt64>()
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS { ids.insert(id) }
            IOObjectRelease(service)
        }
        return ids
    }

    private func isOnACPower() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }
            return state == kIOPSACPowerValue
        }
        return nil
    }
}
