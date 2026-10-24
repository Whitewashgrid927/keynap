import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = KeyNapModel()
    var window: NSWindow?
    var status: NSStatusItem?
    var testingClose = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification:Notification) {
        buildMenu()
        model.onStateChange = { [weak self] in self?.updateStatus() }
        let window = makeWindow(model:model)
        window.delegate = self; self.window = window
        window.setFrameAutosaveName("KeyNapMainWindow")
        window.center()
        if testingClose {
            window.alphaValue = 0
            window.orderBack(nil)
            if KeyboardLock.hasPermission {
                do { try model.lock.start(selected:[UInt16.max]) }
                catch { fputs("Close test could not create harmless tap: \(error)\n",stderr); exit(1) }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { window.close() }
        } else {
            window.makeKeyAndOrderFront(nil)
        }
        // LaunchServices owns activation. Never activate on timers or updates.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wakeForInterruption() }
            })
        }
        appObservers.append(NotificationCenter.default.addObserver(forName:NSApplication.didHideNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wakeForInterruption() }
        })
    }
    func applicationDidBecomeActive(_ notification:Notification) { model.refreshPermission() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        model.wake(); return .terminateNow
    }
    func applicationWillTerminate(_ notification:Notification) {
        model.lock.stop()
        if let status { NSStatusBar.system.removeStatusItem(status) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        if testingClose {
            guard !model.lock.active, status == nil else { fputs("Close test retained a lock\n",stderr); exit(1) }
            print("PASS closing the last window released the tap and terminated KeyNap.")
            fflush(stdout)
        }
    }
    func windowWillClose(_ notification:Notification) {
        model.wake()
        // This is a single-window utility. Explicit termination also covers
        // hidden/non-activating launches where AppKit's last-window rule varies.
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    func windowDidBecomeKey(_ notification:Notification) { model.refreshPermission() }
    private func wakeForInterruption() {
        if model.locked { model.wake(message:"Your keyboard is awake again.") }
    }
    func buildMenu() {
        let main = NSMenu()
        let appRoot = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle:"About KeyNap",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        let wake = NSMenuItem(title:"Wake Keyboard",action:#selector(wakeKeyboard),keyEquivalent:""); wake.target = self
        appMenu.addItem(wake)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Hide KeyNap",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(withTitle:"Quit KeyNap",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appRoot.submenu = appMenu; main.addItem(appRoot)
        let windowRoot = NSMenuItem(title:"Window",action:nil,keyEquivalent:"")
        let windowMenu = NSMenu(title:"Window")
        windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowMenu.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        windowRoot.submenu = windowMenu; main.addItem(windowRoot)
        NSApp.mainMenu = main; NSApp.windowsMenu = windowMenu
    }
    func updateStatus() {
        if model.locked {
            if status == nil { status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength) }
            status?.button?.image = NSImage(systemSymbolName:"moon.zzz.fill",accessibilityDescription:"KeyNap, keyboard locked")
            status?.button?.toolTip = "KeyNap — click to wake your keyboard"
            status?.button?.target = self; status?.button?.action = #selector(wakeKeyboard)
        } else if let status {
            NSStatusBar.system.removeStatusItem(status)
            self.status = nil
        }
    }
    @objc func wakeKeyboard() { model.wake() }
}

@MainActor func makeWindow(model:KeyNapModel) -> NSWindow {
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:590),
                          styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],
                          backing:.buffered,defer:false)
    window.title = "KeyNap"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isOpaque = false; window.backgroundColor = .clear
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width:850,height:540)
    window.contentMaxSize = NSSize(width:1250,height:750)
    window.contentView = NSHostingView(rootView:KeyNapView(model:model))
    window.tabbingMode = .disallowed
    return window
}

@main enum KeyNapMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let args = CommandLine.arguments
        if args.contains("--permission-status") {
            app.setActivationPolicy(.prohibited)
            print("{\"accessibility\":\(KeyboardLock.hasPermission)}")
            return
        }
        if args.contains("--self-test") {
            app.setActivationPolicy(.prohibited)
            do { try SelfTest.run(); return } catch {
                fputs("FAIL: \(error)\n",stderr); exit(1)
            }
        }
        if let index = args.firstIndex(of:"--preview"), args.count > index+1 {
            app.setActivationPolicy(.prohibited)
            do {
                try Preview.render(path:args[index+1],locked:args.contains("--locked"),dark:args.contains("--dark"),
                                   compact:args.contains("--compact"),denied:args.contains("--denied"))
                return
            } catch { fputs("Preview failed: \(error)\n",stderr); exit(1) }
        }
        if let index = args.firstIndex(of:"--profile-idle"), args.count > index+1 {
            app.setActivationPolicy(.prohibited)
            let window = makeWindow(model:KeyNapModel(preview:true))
            window.contentView?.layoutSubtreeIfNeeded()
            print("PROFILE pid=\(ProcessInfo.processInfo.processIdentifier) offscreen=true lock=false")
            fflush(stdout)
            RunLoop.current.run(until:Date().addingTimeInterval(Double(args[index+1]) ?? 15))
            window.close()
            return
        }
        if args.contains("--system-test") {
            app.setActivationPolicy(.prohibited)
            do { try SystemTest.run(); return } catch {
                fputs("System test: \(error)\n",stderr); exit(1)
            }
        }
        let closeTest = args.contains("--close-test")
        app.setActivationPolicy(closeTest ? .prohibited : .regular)
        let delegate = AppDelegate()
        delegate.testingClose = closeTest
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor enum Preview {
    static func render(path:String,locked:Bool,dark:Bool,compact:Bool,denied:Bool) throws {
        let model = KeyNapModel(preview:true,previewLocked:locked,previewPermission:!denied)
        let view = KeyNapView(model:model)
            .frame(width:compact ? 850 : 1000,height:compact ? 540 : 590)
            .environment(\.colorScheme,dark ? .dark : .light)
            .environment(\.keyNapLayoutProof,true)
            .background(dark ? Color(white:0.13) : Color(white:0.96))
        let renderer = ImageRenderer(content:view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw TestFailure("No preview bitmap") }
        let bitmap = NSBitmapImageRep(cgImage:image)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw TestFailure("No PNG") }
        try data.write(to:URL(fileURLWithPath:path))
        print("Saved \(path) (offscreen layout; desktop-dependent glass optics are not captured).")
    }
}
