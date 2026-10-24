import SwiftUI
import AppKit

private enum KeyNapPalette {
    static let lock = Color(red:0.46,green:0.34,blue:0.64)
    static let lightInk = Color(red:0.31,green:0.21,blue:0.46)
    static let darkInk = Color(red:0.85,green:0.77,blue:0.96)
}

private struct LayoutProofKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var keyNapLayoutProof: Bool {
        get { self[LayoutProofKey.self] }
        set { self[LayoutProofKey.self] = newValue }
    }
}

// Offscreen evidence uses the same content and geometry with flat material.
// ImageRenderer cannot capture the native window compositor or AppKit views.
private struct KeyNapGlass<S: Shape>: ViewModifier {
    let tint: Color
    let shape: S
    @Environment(\.keyNapLayoutProof) private var proof
    @Environment(\.colorScheme) private var scheme
    func body(content:Content) -> some View {
        if proof {
            content.background(shape.fill(scheme == .dark ? Color(white:0.22) : Color.white.opacity(0.7)))
                .background(shape.fill(tint))
                .overlay(shape.fill(tint).allowsHitTesting(false))
        } else {
            content.glassEffect(.regular.tint(tint),in:shape)
        }
    }
}
private extension View {
    func keyNapGlass<S:Shape>(_ tint:Color,in shape:S) -> some View {
        modifier(KeyNapGlass(tint:tint,shape:shape))
    }
}
private struct PrimaryActionStyle: ViewModifier {
    let color: Color
    @Environment(\.keyNapLayoutProof) private var proof
    func body(content:Content) -> some View {
        if proof {
            content.buttonStyle(.plain).foregroundStyle(.white).background(Capsule().fill(color.gradient))
        } else {
            content.buttonStyle(.glassProminent).tint(color)
        }
    }
}

@MainActor struct KeyNapView: View {
    @ObservedObject var model: KeyNapModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.keyNapLayoutProof) private var layoutProof
    private var accent: Color {
        model.locked ? Color(red:0.77,green:0.43,blue:0.08)
        : scheme == .dark ? KeyNapPalette.darkInk : KeyNapPalette.lock
    }

    var body: some View {
        VStack(alignment:.leading, spacing:16) {
            HStack(alignment:.center) {
                VStack(alignment:.leading, spacing:5) {
                    Text(model.locked ? "A little quiet time." : "Choose what sleeps.")
                        .font(.system(size:26,weight:.semibold,design:.rounded))
                    Text(model.locked ? "\(model.selected.count) keys asleep. Clean away." : "Give your keyboard a moment to rest.")
                        .font(.system(size:13)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing:7) {
                    Image(systemName:model.locked ? "moon.zzz.fill" : "keyboard")
                    Text(model.locked ? "Cleaning" : "Keyboard awake")
                }
                .font(.system(size:12,weight:.medium)).foregroundStyle(accent)
                .padding(.horizontal,14).padding(.vertical,10)
                .keyNapGlass(accent.opacity(0.10),in:Capsule())
            }
            HStack(spacing:6) {
                ForEach([KeyGroup.all,.letters,.numbers,.function,.arrows],id:\.self) { group in
                    Button { model.choose(group) } label: {
                        Text(group.rawValue).font(.system(size:12,weight:.medium))
                            .padding(.horizontal,14).padding(.vertical,9)
                            .foregroundStyle(model.group == group ? Color.white : Color.primary.opacity(0.7))
                            .background {
                                if model.group == group { Capsule().fill(KeyNapPalette.lock.gradient) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(model.locked)
                    .accessibilityAddTraits(model.group == group ? .isSelected : [])
                }
                if layoutProof {
                    Image(systemName:"rectangle.split.2x1").font(.system(size:13))
                } else { Menu {
                    Button("Left half") { model.choose(.left) }
                    Button("Right half") { model.choose(.right) }
                } label: { Image(systemName:"rectangle.split.2x1").font(.system(size:13)) }
                    .menuStyle(.borderlessButton).fixedSize().padding(.leading,6)
                    .help("Select a side").disabled(model.locked).accessibilityLabel("Select a side")
                }
                Spacer(minLength:8)
                Button("Clear") { model.clear() }.buttonStyle(.plain)
                    .font(.system(size:12)).foregroundStyle(.secondary)
                    .disabled(model.locked || model.selected.isEmpty)
            }
            KeyboardView(model:model)
                .aspectRatio(KeyboardLayout.width/KeyboardLayout.height,contentMode:.fit)
                .layoutPriority(1)
            HStack(alignment:.center,spacing:20) {
                VStack(alignment:.leading,spacing:5) {
                    if let message = model.message {
                        Label(message,systemImage:"info.circle")
                            .foregroundStyle(.primary).font(.system(size:12))
                    } else if model.locked {
                        Label("Mouse and trackpad stay awake.",systemImage:"cursorarrow")
                            .foregroundStyle(.secondary).font(.system(size:12))
                    } else if !model.permission {
                        Label("One-time Accessibility access is needed to lock keys.",systemImage:"hand.raised")
                            .foregroundStyle(.secondary).font(.system(size:12))
                    } else {
                        Text("Click keys or drag an area. Shift-drag adds to your selection.")
                            .foregroundStyle(.secondary).font(.system(size:12))
                    }
                    Text("Touch ID and power stay available.")
                        .font(.system(size:11)).foregroundStyle(.tertiary)
                }
                Spacer(minLength:0)
                Button { model.primaryAction() } label: {
                    Label(model.locked ? "Wake keyboard" : !model.permission ? "Enable KeyNap" : "Lock \(model.selected.count) keys",
                          systemImage:model.locked ? "sun.max" : !model.permission ? "lock.open" : "moon")
                        .font(.system(size:14,weight:.semibold)).frame(minWidth:160)
                        .padding(.horizontal,8).padding(.vertical,10)
                }
                .modifier(PrimaryActionStyle(color:model.locked ? .orange : KeyNapPalette.lock))
                .disabled(!model.locked && model.selected.isEmpty)
                .accessibilityHint(model.locked ? "Immediately restores normal keyboard input." : "Locks the selected keys until you click Wake keyboard or close KeyNap.")
            }
        }
        .padding(.horizontal,28).padding(.top,40).padding(.bottom,24)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .tint(KeyNapPalette.lock)
        .background {
            if reduceTransparency {
                Color(nsColor:.windowBackgroundColor)
            } else {
                if !layoutProof { NativeBackdrop() }
                LinearGradient(colors: scheme == .dark
                               ? [KeyNapPalette.lock.opacity(0.08),Color.clear,Color.teal.opacity(0.06)]
                               : [Color(red:0.89,green:0.94,blue:0.98).opacity(0.65),
                                  Color.white.opacity(0.27),Color(red:0.87,green:0.93,blue:0.89).opacity(0.55)],
                               startPoint:.topLeading,endPoint:.bottomTrailing)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration:0.18),value:model.locked)
    }
}

private struct NativeBackdrop: NSViewRepresentable {
    func makeNSView(context:Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}

@MainActor struct KeyboardView: View {
    @ObservedObject var model: KeyNapModel
    @State private var dragRect: CGRect?
    @State private var hovered: UInt16?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.keyNapLayoutProof) private var layoutProof
    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / KeyboardLayout.width
            GlassEffectContainer(spacing:0) {
                ZStack(alignment:.topLeading) {
                    ForEach(KeyboardLayout.keys) { key in
                        let selected = model.selected.contains(key.id)
                        let color: Color = model.locked ? .orange : KeyNapPalette.lock
                        KeyFace(key:key,unit:unit,selected:selected,locked:model.locked)
                            .frame(width:key.frame.width*unit-5,height:key.frame.height*unit-5)
                            .background {
                                if reduceTransparency {
                                    RoundedRectangle(cornerRadius:9)
                                        .fill(selected ? color.opacity(scheme == .dark ? 0.45 : 0.22) : Color(nsColor:.controlBackgroundColor))
                                }
                            }
                            .keyNapGlass(selected ? color.opacity(model.locked ? 0.23 : 0.19) : .clear,
                                         in:RoundedRectangle(cornerRadius:9))
                            .overlay {
                                RoundedRectangle(cornerRadius:9)
                                    .strokeBorder(selected ? color.opacity(0.62) : Color.primary.opacity(hovered == key.id ? 0.3 : 0.08),
                                                  lineWidth:selected ? 1 : 0.65)
                            }
                            .shadow(color:.black.opacity(0.06),radius:2,y:2)
                            .opacity(key.selectable ? 1 : 0.5)
                            .position(x:key.frame.midX*unit,y:key.frame.midY*unit)
                            .accessibilityElement(children:.ignore)
                            .accessibilityLabel(key.name)
                            .accessibilityValue(key.selectable ? selected ? model.locked ? "Asleep" : "Selected" : "Awake" : "Always available")
                            .accessibilityAddTraits(key.selectable ? [.isButton] : [])
                            .accessibilityAction { model.toggle(key.id) }
                    }
                }
            }
            if let dragRect {
                RoundedRectangle(cornerRadius:7)
                    .fill(KeyNapPalette.lock.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(KeyNapPalette.lock.opacity(0.65),style:StrokeStyle(lineWidth:1,dash:[4,3])))
                    .frame(width:dragRect.width,height:dragRect.height)
                    .position(x:dragRect.midX,y:dragRect.midY).allowsHitTesting(false)
            }
            if !layoutProof { KeyboardMouseSurface(enabled:!model.locked,onClick:{ point in
                if let code = KeyboardLayout.hit(at:CGPoint(x:point.x/unit,y:point.y/unit)) { model.toggle(code) }
            },onDrag:{ start,end,additive in
                dragRect = CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(start.x-end.x),height:abs(start.y-end.y))
                model.drag(from:CGPoint(x:start.x/unit,y:start.y/unit),to:CGPoint(x:end.x/unit,y:end.y/unit),additive:additive)
            },onEnd:{ model.endDrag(); dragRect = nil },onHover:{ point in
                hovered = point.flatMap { KeyboardLayout.hit(at:CGPoint(x:$0.x/unit,y:$0.y/unit)) }
            })
            .accessibilityHidden(true)
            }
        }
    }
}

private struct KeyFace: View {
    let key: KeySpec
    let unit: CGFloat
    let selected: Bool
    let locked: Bool
    @Environment(\.colorScheme) private var scheme
    private var ink: Color {
        guard selected else { return .primary.opacity(0.75) }
        if scheme == .dark { return locked ? Color(red:1,green:0.84,blue:0.52) : KeyNapPalette.darkInk }
        return locked ? Color(red:0.48,green:0.26,blue:0.04) : KeyNapPalette.lightInk
    }
    var body: some View {
        ZStack {
            if let symbol = key.symbol {
                VStack(spacing:key.frame.height < 0.7 ? 3 : 5) {
                    Image(systemName:symbol).font(.system(size:key.id == KeyboardLayout.touchID ? 20 : key.frame.height < 0.5 ? 8 : 14,weight:.regular))
                    if !key.label.isEmpty {
                        Text(key.label).font(.system(size:key.frame.height < 0.7 ? 8 : 9,weight:.medium))
                    }
                }
            } else {
                Text(key.label).font(.system(size:key.label.count > 1 ? 11 : 16,weight:.medium))
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:key.label.count > 1 ? .bottomLeading : .center)
                    .padding(key.label.count > 1 ? 10 : 0)
            }
            if selected && locked && key.frame.width > 1.4 && key.frame.height > 0.7 {
                Image(systemName:"moon.fill").font(.system(size:7)).opacity(0.5)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(7)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

/// A single AppKit pointer surface gives deterministic click/drag arbitration.
/// The individual keys above remain separate VoiceOver actions.
struct KeyboardMouseSurface: NSViewRepresentable {
    var enabled: Bool
    var onClick: (CGPoint)->Void
    var onDrag: (CGPoint,CGPoint,Bool)->Void
    var onEnd: ()->Void
    var onHover: (CGPoint?)->Void
    func makeNSView(context:Context) -> KeyboardPointerView { KeyboardPointerView() }
    func updateNSView(_ view:KeyboardPointerView,context:Context) {
        view.enabled = enabled; view.onClick = onClick; view.onDrag = onDrag; view.onEnd = onEnd; view.onHover = onHover
    }
}

final class KeyboardPointerView: NSView {
    var enabled = true
    var onClick: ((CGPoint)->Void)?
    var onDrag: ((CGPoint,CGPoint,Bool)->Void)?
    var onEnd: (()->Void)?
    var onHover: ((CGPoint?)->Void)?
    private var start: CGPoint?
    private var dragging = false
    private var additive = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self)
        addTrackingArea(tracking!)
    }
    override func mouseDown(with event:NSEvent) {
        guard enabled else { return }
        start = convert(event.locationInWindow,from:nil); dragging = false
        additive = event.modifierFlags.contains(.shift)
    }
    override func mouseDragged(with event:NSEvent) {
        guard enabled, let start else { return }
        let end = convert(event.locationInWindow,from:nil)
        if hypot(end.x-start.x,end.y-start.y) >= 4 { dragging = true }
        if dragging { onDrag?(start,end,additive) }
    }
    override func mouseUp(with event:NSEvent) {
        defer { start = nil; dragging = false; onEnd?() }
        guard enabled, start != nil else { return }
        if !dragging { onClick?(convert(event.locationInWindow,from:nil)) }
    }
    override func mouseMoved(with event:NSEvent) { if enabled { onHover?(convert(event.locationInWindow,from:nil)) } }
    override func mouseExited(with event:NSEvent) { onHover?(nil) }
}
