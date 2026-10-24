import AppKit
import SwiftUI
import ApplicationServices

@MainActor final class KeyNapModel: ObservableObject {
    @Published private(set) var selection = KeyboardSelection()
    @Published private(set) var locked = false
    @Published private(set) var permission = KeyboardLock.hasPermission
    @Published var message: String?
    let lock = KeyboardLock()
    var onStateChange: (() -> Void)?
    let preview: Bool

    init(preview: Bool = false, previewLocked: Bool = false, previewPermission: Bool = true) {
        self.preview = preview
        if preview {
            selection.replace(with:KeyboardLayout.letterCodes)
            permission = previewPermission
            locked = previewLocked
        }
        lock.onInterrupted = { [weak self] message in
            guard let self else { return }
            self.locked = false
            self.message = message
            self.refreshPermission()
            self.onStateChange?()
        }
    }
    var selected: Set<UInt16> { selection.codes }
    var group: KeyGroup? { KeyGroup.allCases.first { KeyboardLayout.codes(for:$0) == selected } }
    func choose(_ group: KeyGroup) {
        guard !locked else { return }
        selection.replace(with:KeyboardLayout.codes(for:group)); message = nil
    }
    func clear() { guard !locked else { return }; selection.replace(with:[]); message = nil }
    func toggle(_ code: UInt16) { guard !locked else { return }; selection.toggle(code); message = nil }
    func drag(from: CGPoint, to: CGPoint, additive: Bool) {
        guard !locked else { return }
        selection.drag(from:from,to:to,additive:additive)
        message = nil
    }
    func endDrag() { selection.endDrag() }
    func refreshPermission() { if !preview { permission = KeyboardLock.hasPermission } }
    func openPermissionSettings() {
        guard !preview else { return }
        // Register this signed app with TCC using Apple's explicit prompt.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func primaryAction() {
        if locked { wake(); return }
        refreshPermission()
        guard permission else { openPermissionSettings(); return }
        guard !preview else { locked = true; return }
        do {
            try lock.start(selected:selected)
            locked = true; message = nil
        } catch {
            locked = false; message = error.localizedDescription
        }
        onStateChange?()
    }
    func wake(message: String? = nil) {
        lock.stop()
        locked = false
        self.message = message
        onStateChange?()
    }
}
