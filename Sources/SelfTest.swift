import AppKit
import CoreGraphics

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description:String) { self.description = description }
}

@MainActor enum SelfTest {
    static func run() throws {
        var checks = 0
        func check(_ value:Bool,_ name:String) throws {
            checks += 1
            if !value { throw TestFailure(name) }
        }
        let keys = KeyboardLayout.keys
        try check(Set(keys.map(\.id)).count == keys.count,"Duplicate key IDs")
        try check(KeyboardLayout.letterCodes.count == 26,"Letter count")
        try check(KeyboardLayout.numberCodes.count == 10,"Number count")
        try check(KeyboardLayout.functionCodes.count == 12,"Function count")
        try check(KeyboardLayout.arrowCodes.count == 4,"Arrow count")
        try check(!KeyboardLayout.selectableCodes.contains(KeyboardLayout.touchID),"Power must not be selectable")
        try check(KeyboardLayout.selectableCodes.contains(63),"Fn key is missing")
        for key in keys {
            try check(key.frame.minX >= 0 && key.frame.maxX <= KeyboardLayout.width &&
                      key.frame.minY >= 0 && key.frame.maxY <= KeyboardLayout.height + 0.001,"Key outside layout: \(key.name)")
            let hit = KeyboardLayout.hit(at:CGPoint(x:key.frame.midX,y:key.frame.midY))
            try check(hit == (key.selectable ? key.id : nil),"Incorrect hit region: \(key.name)")
        }
        for (i,key) in keys.enumerated() {
            for other in keys.dropFirst(i+1) {
                try check(!key.frame.insetBy(dx:0.001,dy:0.001).intersects(other.frame.insetBy(dx:0.001,dy:0.001)),
                          "Overlapping keys: \(key.name), \(other.name)")
            }
        }
        let left = KeyboardLayout.codes(for:.left), right = KeyboardLayout.codes(for:.right)
        try check(left.isDisjoint(with:right) && left.union(right) == KeyboardLayout.selectableCodes,"Side groups must cover keyboard exactly")
        var selection = KeyboardSelection()
        selection.replace(with:[])
        selection.toggle(0); try check(selection.codes == [0],"Click selects A")
        selection.toggle(0); try check(selection.codes.isEmpty,"Click deselects A")
        selection.toggle(255); try check(selection.codes.isEmpty,"Power must ignore clicks")
        selection.drag(from:.zero,to:CGPoint(x:15,y:5.48),additive:false)
        try check(selection.codes == KeyboardLayout.selectableCodes,"Full marquee selection")
        selection.drag(from:.zero,to:CGPoint(x:2,y:1),additive:false)
        try check(selection.codes.count < 5,"Retracting marquee must retract selection")
        selection.endDrag(); selection.replace(with:[0])
        selection.drag(from:.zero,to:CGPoint(x:1.4,y:0.7),additive:true)
        try check(selection.codes == [0,53],"Shift marquee preserves prior selection")
        selection.endDrag()

        // Every region, every physical key, both down and up, including repeats.
        for group in KeyGroup.allCases {
            let chosen = KeyboardLayout.codes(for:group)
            var filter = KeyboardFilter(selected:chosen)
            for code in KeyboardLayout.selectableCodes {
                for down in [false,true] {
                    let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!
                    event.flags = []
                    event.setIntegerValueField(.keyboardEventAutorepeat,value:1)
                    let type: CGEventType = down ? .keyDown : .keyUp
                    try check(filter.allows(type,event:event) == !chosen.contains(code),"Filter \(group.rawValue), key \(code), down=\(down)")
                }
            }
        }
        var all = KeyboardFilter(selected:KeyboardLayout.selectableCodes)
        for (key,alias): (UInt16,UInt16) in [(111,72),(103,73),(109,74)] {
            var filter = KeyboardFilter(selected:[key])
            for down in [true,false] {
                let event = CGEvent(keyboardEventSource:nil,virtualKey:alias,keyDown:down)!
                try check(!filter.allows(down ? .keyDown : .keyUp,event:event),"Volume virtual-key alias leaked")
            }
        }
        let external = CGEvent(keyboardEventSource:nil,virtualKey:90,keyDown:true)!
        try check(!all.allows(.keyDown,event:external),"Whole keyboard includes external keyboard keys")
        for pair in KeyboardFilter.pairs {
            for side in [pair.left,pair.right] {
                var filter = KeyboardFilter(selected:[side])
                let blockedBit = side == pair.left ? pair.leftBit : pair.rightBit
                let availableBit = side == pair.left ? pair.rightBit : pair.leftBit
                let removed = filter.filteredFlags(CGEventFlags(rawValue:pair.aggregate|blockedBit))
                try check(removed.rawValue & (pair.aggregate|blockedBit) == 0,"Selected modifier leaks flags")
                let retained = filter.filteredFlags(CGEventFlags(rawValue:pair.aggregate|availableBit))
                try check(retained.rawValue & pair.aggregate != 0 && retained.rawValue & availableBit != 0,"Opposite modifier must work")
                let both = filter.filteredFlags(CGEventFlags(rawValue:pair.aggregate|availableBit|blockedBit))
                try check(both.rawValue & pair.aggregate != 0 && both.rawValue & blockedBit == 0,"Both-side modifier state")
                let changed = CGEvent(keyboardEventSource:nil,virtualKey:side,keyDown:true)!
                changed.type = .flagsChanged; changed.flags = CGEventFlags(rawValue:pair.aggregate|blockedBit)
                try check(!filter.allows(.flagsChanged,event:changed),"Selected modifier event not blocked")
            }
        }
        var capOff = KeyboardFilter(selected:[57])
        try check(!capOff.filteredFlags(.maskAlphaShift).contains(.maskAlphaShift),"Caps off preserved")
        var capOn = KeyboardFilter(selected:[57],initialFlags:.maskAlphaShift)
        try check(capOn.filteredFlags([]).contains(.maskAlphaShift),"Existing caps state preserved")
        var fn = KeyboardFilter(selected:[63])
        try check(!fn.filteredFlags(.maskSecondaryFn).contains(.maskSecondaryFn),"Fn flag removed")
        for type in KeyboardLock.eventTypes where type != .keyDown && type != .keyUp && type != .flagsChanged && type.rawValue != 14 {
            let event = CGEvent(source:nil)!; event.type = type
            event.flags = CGEventFlags(rawValue:0x100008)
            try check(all.allows(type,event:event),"Mouse event was suppressed")
            try check(!event.flags.contains(.maskCommand),"Blocked Command affected mouse")
        }
        for (key,specials) in KeyboardFilter.mediaForKey {
            var filter = KeyboardFilter(selected:[key])
            for special in specials {
                for keyState in [0xA,0xB] {
                    let ns = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],timestamp:0,
                                               windowNumber:0,context:nil,subtype:8,data1:(special<<16)|(keyState<<8),data2:-1)!
                    try check(!filter.allows(CGEventType(rawValue:14)!,event:ns.cgEvent!),"Selected media key leaked")
                }
            }
        }
        let power = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],timestamp:0,
                                      windowNumber:0,context:nil,subtype:8,data1:(6<<16)|0xA00,data2:-1)!
        try check(all.allows(CGEventType(rawValue:14)!,event:power.cgEvent!),"Power must pass")
        let unrelatedSystem = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],timestamp:0,
                                                windowNumber:0,context:nil,subtype:7,data1:0,data2:0)!
        try check(all.allows(CGEventType(rawValue:14)!,event:unrelatedSystem.cgEvent!),"Auxiliary mouse controls must pass")

        let pointer = KeyboardPointerView(frame:NSRect(x:0,y:0,width:500,height:300))
        var clicks = 0, drags = 0, ends = 0, additive = false
        pointer.onClick = { _ in clicks += 1 }
        pointer.onDrag = { _,_,adding in drags += 1; additive = adding }
        pointer.onEnd = { ends += 1 }
        func mouse(_ type:NSEvent.EventType,_ x:CGFloat,_ y:CGFloat,_ flags:NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:CGPoint(x:x,y:y),modifierFlags:flags,timestamp:0,windowNumber:0,
                              context:nil,eventNumber:0,clickCount:1,pressure:0)!
        }
        pointer.mouseDown(with:mouse(.leftMouseDown,10,10))
        pointer.mouseUp(with:mouse(.leftMouseUp,10,10))
        try check(clicks == 1 && drags == 0 && ends == 1,"Click gesture")
        pointer.mouseDown(with:mouse(.leftMouseDown,10,10,.shift))
        pointer.mouseDragged(with:mouse(.leftMouseDragged,100,100,.shift))
        pointer.mouseUp(with:mouse(.leftMouseUp,100,100,.shift))
        try check(clicks == 1 && drags == 1 && ends == 2 && additive,"Dragging must not trigger a second click")
        pointer.enabled = false
        pointer.mouseDown(with:mouse(.leftMouseDown,10,10))
        pointer.mouseUp(with:mouse(.leftMouseUp,10,10))
        try check(clicks == 1 && drags == 1,"Selection disabled while cleaning")
        let model = KeyNapModel(preview:true,previewLocked:true)
        let before = model.selected
        model.clear(); model.choose(.all); model.toggle(0)
        try check(model.selected == before,"Selection changed while locked")
        model.wake()
        try check(!model.locked && !model.lock.active,"Wake must release lock")
        let lock = KeyboardLock()
        lock.stop(); lock.stop()
        try check(!lock.active,"Repeated stop must be safe")
        do { try lock.start(selected:[]); throw TestFailure("Empty lock succeeded") }
        catch LockFailure.empty {}
        let denied = KeyboardLock(permissionCheck:{false})
        do { try denied.start(selected:[0]); throw TestFailure("Permissionless lock succeeded") }
        catch LockFailure.permission {}
        try check(!denied.active,"Permission denial must leave keyboard awake")
        let secure = KeyboardLock(permissionCheck:{true},secureInputCheck:{true})
        do { try secure.start(selected:[0]); throw TestFailure("Secure input was ignored") }
        catch LockFailure.secureInput {}
        try check(!secure.active,"Secure input must leave keyboard awake")
        let held = KeyboardLock(permissionCheck:{true},secureInputCheck:{false},heldKeyCheck:{$0 == 55})
        do { try held.start(selected:[0]); throw TestFailure("Held modifier was ignored") }
        catch LockFailure.heldKeys {}
        try check(!held.active,"Held shortcut must leave keyboard awake")
        let start = CFAbsoluteTimeGetCurrent()
        var fast = KeyboardFilter(selected:KeyboardLayout.letterCodes)
        let event = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true)!
        var suppressed = 0
        for _ in 0..<100_000 { if !fast.allows(.keyDown,event:event) { suppressed += 1 } }
        let elapsed = CFAbsoluteTimeGetCurrent()-start
        try check(suppressed == 100_000,"Callback stress count")
        print("PASS \(checks) checks. Layout, hit testing, regions, click/drag arbitration, key pairs, repeats, modifiers, media, mouse escape, permission failure and idle teardown.")
        print(String(format:"Filter benchmark: 100000 events in %.4f s (%.2f µs/event). No events were posted to the desktop.",elapsed,elapsed*10))
        print("Physical keyboard routing and system-reserved keys require Accessibility and a separate live check.")
    }
}

private final class SystemTestContext {
    var filter = KeyboardFilter(selected:[0,55])
    var received: [(CGEventType,Int64,CGEventFlags)] = []
    static let marker: Int64 = 0x4B4E4150
}
private func systemTestFilter(_ proxy:CGEventTapProxy,_ type:CGEventType,_ event:CGEvent,_ context:UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context, event.getIntegerValueField(.eventSourceUserData) == SystemTestContext.marker else {
        return Unmanaged.passUnretained(event)
    }
    let state = Unmanaged<SystemTestContext>.fromOpaque(context).takeUnretainedValue()
    return state.filter.allows(type,event:event) ? Unmanaged.passUnretained(event) : nil
}
private func systemTestObserver(_ proxy:CGEventTapProxy,_ type:CGEventType,_ event:CGEvent,_ context:UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let context, event.getIntegerValueField(.eventSourceUserData) == SystemTestContext.marker {
        let state = Unmanaged<SystemTestContext>.fromOpaque(context).takeUnretainedValue()
        state.received.append((type,event.getIntegerValueField(.keyboardEventKeycode),event.flags))
    }
    return Unmanaged.passUnretained(event)
}

@MainActor enum SystemTest {
    static func run() throws {
        guard KeyboardLock.hasPermission else { throw TestFailure("Accessibility approval is required; no live test ran.") }
        let service = KeyboardLock()
        // A nonphysical code validates the global tap lifecycle without locking
        // any of the user's keys. Behavioral events below target only this PID.
        for _ in 0..<20 {
            try service.start(selected:[UInt16.max])
            guard service.active else { throw TestFailure("Tap did not become active") }
            service.stop()
        }
        guard !service.active else { throw TestFailure("Tap retained after stop") }
        let state = SystemTestContext()
        let context = Unmanaged.passUnretained(state).toOpaque()
        guard let filter = CGEvent.tapCreateForPid(pid:getpid(),place:.headInsertEventTap,options:.defaultTap,
                                                   eventsOfInterest:KeyboardLock.eventMask,callback:systemTestFilter,userInfo:context) else {
            throw TestFailure("Could not create app-scoped filter")
        }
        defer { CFMachPortInvalidate(filter) }
        guard let observer = CGEvent.tapCreateForPid(pid:getpid(),place:.tailAppendEventTap,options:.listenOnly,
                                                     eventsOfInterest:KeyboardLock.eventMask,callback:systemTestObserver,userInfo:context) else {
            throw TestFailure("Could not create app-scoped observer")
        }
        defer { CFMachPortInvalidate(observer) }
        let sources = [filter,observer].map { CFMachPortCreateRunLoopSource(nil,$0,0)! }
        for source in sources { CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes) }
        defer { for source in sources { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) } }
        func post(_ event:CGEvent) {
            event.setIntegerValueField(.eventSourceUserData,value:SystemTestContext.marker)
            event.postToPid(getpid())
            RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        }
        for code: UInt16 in [0,11] {
            for down in [true,false] {
                let event = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!
                event.flags = []; post(event)
            }
        }
        for type:CGEventType in [.leftMouseDown,.leftMouseUp] {
            let mouse = CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:.zero,mouseButton:.left)!
            mouse.flags = CGEventFlags(rawValue:0x100008); post(mouse)
        }
        RunLoop.current.run(until:Date().addingTimeInterval(0.3))
        let keys = state.received.filter { $0.0 == .keyDown || $0.0 == .keyUp }
        let mouse = state.received.filter { $0.0 == .leftMouseDown || $0.0 == .leftMouseUp }
        guard keys.count == 2, keys.allSatisfy({ $0.1 == 11 }), mouse.count == 2,
              mouse.allSatisfy({ !$0.2.contains(.maskCommand) }) else {
            throw TestFailure("App-scoped filter mismatch: keys=\(keys.count), mouse=\(mouse.count)")
        }
        print("PASS 20 global tap install/remove cycles. PASS OS-routed A down/up suppressed, B down/up forwarded, mouse down/up forwarded with blocked Command removed. Events targeted this test process only.")
    }
}
