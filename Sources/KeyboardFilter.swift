import AppKit
import CoreGraphics

/// No event text is inspected or retained. The live callback and tests use this
/// same filter; it only handles key identifiers, event kind and modifier bits.
struct KeyboardFilter {
    struct ModifierPair {
        let left: UInt16, right: UInt16
        let leftBit: UInt64, rightBit: UInt64, aggregate: UInt64
    }
    // Public NX_DEVICE* flags from IOKit/hidsystem/IOLLEvent.h.
    static let pairs: [ModifierPair] = [
        .init(left:56,right:60,leftBit:0x2,rightBit:0x4,aggregate:0x20000),
        .init(left:59,right:62,leftBit:0x1,rightBit:0x2000,aggregate:0x40000),
        .init(left:58,right:61,leftBit:0x20,rightBit:0x40,aggregate:0x80000),
        .init(left:55,right:54,leftBit:0x8,rightBit:0x10,aggregate:0x100000)
    ]
    // Public NX_KEYTYPE_* values. Power (6) is deliberately absent.
    static let mediaForKey: [UInt16:Set<Int>] = [
        122:[3], 120:[2], 99:[13], 98:[18,20], 100:[16], 101:[17,19],
        109:[7], 103:[1], 111:[0]
    ]
    let selected: Set<UInt16>
    let blockedCodes: Set<UInt16>
    let all: Bool
    let media: Set<Int>
    let initialCaps: Bool
    private var modifierDown = Set<UInt16>()

    init(selected: Set<UInt16>, initialFlags: CGEventFlags = []) {
        self.selected = selected
        // HIToolbox also exposes volume as ordinary virtual-key events.
        let aliases: [UInt16:UInt16] = [111:72,103:73,109:74]
        self.blockedCodes = selected.union(selected.compactMap { aliases[$0] })
        self.all = selected == KeyboardLayout.selectableCodes
        self.media = selected.reduce(into: Set<Int>()) { $0.formUnion(Self.mediaForKey[$1] ?? []) }
        self.initialCaps = initialFlags.contains(.maskAlphaShift)
    }

    mutating func filteredFlags(_ flags: CGEventFlags, changedKey: UInt16? = nil) -> CGEventFlags {
        var raw = flags.rawValue
        for pair in Self.pairs {
            let bits = pair.leftBit | pair.rightBit
            if raw & bits != 0 {
                if raw & pair.leftBit != 0 { modifierDown.insert(pair.left) } else { modifierDown.remove(pair.left) }
                if raw & pair.rightBit != 0 { modifierDown.insert(pair.right) } else { modifierDown.remove(pair.right) }
            } else if raw & pair.aggregate == 0 {
                modifierDown.remove(pair.left); modifierDown.remove(pair.right)
            } else if let key = changedKey, key == pair.left || key == pair.right {
                // Synthetic/accessibility events can omit side-specific bits.
                if modifierDown.contains(key) { modifierDown.remove(key) } else { modifierDown.insert(key) }
            }
            let blockLeft = all || selected.contains(pair.left)
            let blockRight = all || selected.contains(pair.right)
            guard blockLeft || blockRight else { continue }
            if blockLeft { raw &= ~pair.leftBit }
            if blockRight { raw &= ~pair.rightBit }
            let unblockedDown = (!blockLeft && modifierDown.contains(pair.left)) || (!blockRight && modifierDown.contains(pair.right))
            if (blockLeft && blockRight) || !unblockedDown { raw &= ~pair.aggregate }
        }
        if all || selected.contains(57) {
            raw &= ~UInt64(0x10000 | 0x1000000 | 0x80)
            if initialCaps { raw |= 0x10000 }
        }
        if all || selected.contains(63) { raw &= ~CGEventFlags.maskSecondaryFn.rawValue }
        return CGEventFlags(rawValue: raw)
    }

    mutating func allows(_ type: CGEventType, event: CGEvent) -> Bool {
        let keyboard = type == .keyDown || type == .keyUp || type == .flagsChanged
        let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        event.flags = filteredFlags(event.flags, changedKey: type == .flagsChanged ? code : nil)
        if keyboard { return !(all || blockedCodes.contains(code)) }
        if type.rawValue == 14, let nsEvent = NSEvent(cgEvent:event), nsEvent.subtype.rawValue == 8 {
            let special = (nsEvent.data1 >> 16) & 0xFFFF
            // Never swallow a power button, even in whole-keyboard mode.
            if special == 6 { return true }
            return !(all || media.contains(special))
        }
        // Mouse movement, clicking and scrolling are never suppressed.
        return true
    }
}
