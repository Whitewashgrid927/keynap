import AppKit
import ApplicationServices
import Carbon

enum LockFailure: LocalizedError {
    case permission, heldKeys, tapUnavailable, empty, secureInput
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow KeyNap in Accessibility to lock keys."
        case .heldKeys: return "Release any held keys, then try again."
        case .tapUnavailable: return "macOS couldn’t start the keyboard lock. Your keyboard is awake."
        case .empty: return "Choose at least one key first."
        case .secureInput: return "Secure Keyboard Entry is active in another app. Leave that field or app before locking."
        }
    }
}

/// Owned by the main run loop. Nothing is installed or polled while unlocked.
/// The callback is bounded, synchronous, and never updates SwiftUI per keypress.
@MainActor final class KeyboardLock {
    private(set) var active = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: Timer?
    private var filter = KeyboardFilter(selected: [])
    private var generation = 0
    private let permissionCheck: () -> Bool
    private let secureInputCheck: () -> Bool
    private let heldKeyCheck: (UInt16) -> Bool
    var onInterrupted: ((String) -> Void)?
    init(permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
         secureInputCheck: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         heldKeyCheck: @escaping (UInt16) -> Bool = { CGEventSource.keyState(.hidSystemState,key:$0) }) {
        self.permissionCheck = permissionCheck
        self.secureInputCheck = secureInputCheck
        self.heldKeyCheck = heldKeyCheck
    }
    static let eventTypes: [CGEventType] = [
        .keyDown,.keyUp,.flagsChanged,CGEventType(rawValue:14)!,
        .leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,
        .otherMouseDown,.otherMouseUp,.mouseMoved,.leftMouseDragged,
        .rightMouseDragged,.otherMouseDragged,.scrollWheel
    ]
    static let eventMask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    static var hasPermission: Bool { AXIsProcessTrusted() }

    func start(selected: Set<UInt16>) throws {
        stop()
        guard !selected.isEmpty else { throw LockFailure.empty }
        guard permissionCheck() else { throw LockFailure.permission }
        guard !secureInputCheck() else { throw LockFailure.secureInput }
        // Starting from a released keyboard avoids cutting an existing shortcut
        // or key-down/key-up pair in half. Caps Lock is a latch, not a held key.
        let candidates = KeyboardLayout.selectableCodes.subtracting([57]).union([62])
        guard !candidates.contains(where:heldKeyCheck) else {
            throw LockFailure.heldKeys
        }
        filter = KeyboardFilter(selected: selected, initialFlags: CGEventSource.flagsState(.hidSystemState))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap,
                                          options:.defaultTap, eventsOfInterest:Self.eventMask,
                                          callback:keyNapEventCallback, userInfo:context) else {
            throw LockFailure.tapUnavailable
        }
        guard let loopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            throw LockFailure.tapUnavailable
        }
        tap = port; source = loopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap:port, enable:true)
        guard CGEvent.tapIsEnabled(tap:port) else { stop(); throw LockFailure.tapUnavailable }
        active = true
        // One low-frequency check only during a cleaning session. It catches
        // permission revocation or a tap that disappears without a callback.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                if self.secureInputCheck() {
                    self.interrupt("Secure Keyboard Entry started. The keyboard lock has ended.")
                    return
                }
                guard let tap = self.tap, CGEvent.tapIsEnabled(tap:tap), self.permissionCheck() else {
                    self.interrupt("macOS ended the lock. Your keyboard is awake.")
                    return
                }
            }
        }
        timer.tolerance = 0.25
        healthTimer = timer
        RunLoop.main.add(timer, forMode:.common)
    }

    func stop() {
        generation += 1
        active = false
        healthTimer?.invalidate(); healthTimer = nil
        if let tap { CGEvent.tapEnable(tap:tap, enable:false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
        filter = KeyboardFilter(selected: [])
    }

    private func interrupt(_ message: String) {
        stop()
        onInterrupted?(message)
    }

    fileprivate func receive(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            active = false
            // Do not silently re-enable a tap after the system interrupts it.
            // Move CF source teardown out of the callback stack.
            let expectedGeneration = generation
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == expectedGeneration else { return }
                self.interrupt("The lock was interrupted. Your keyboard is awake.")
            }
            return Unmanaged.passUnretained(event)
        }
        guard active else { return Unmanaged.passUnretained(event) }
        return filter.allows(type,event:event) ? Unmanaged.passUnretained(event) : nil
    }
}

private func keyNapEventCallback(_ proxy: CGEventTapProxy, _ type: CGEventType,
                                 _ event: CGEvent, _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated {
        Unmanaged<KeyboardLock>.fromOpaque(context).takeUnretainedValue().receive(type,event:event)
    }
}
