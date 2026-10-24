import Foundation
import CoreGraphics

struct KeySpec: Identifiable {
    let id: UInt16
    let label: String
    let symbol: String?
    let name: String
    let frame: CGRect
    let selectable: Bool
}

enum KeyGroup: String, CaseIterable {
    case all = "All keys", letters = "Letters", numbers = "Numbers"
    case function = "Function row", arrows = "Arrows", left = "Left half", right = "Right half"
}

enum KeyboardLayout {
    static let width: CGFloat = 15
    static let height: CGFloat = 5.48
    static let touchID: UInt16 = 255
    static let letterCodes: Set<UInt16> = [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15,16,17,31,32,34,35,37,38,40,45,46]
    static let numberCodes: Set<UInt16> = [18,19,20,21,23,22,26,28,25,29]
    static let functionCodes: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111]
    static let arrowCodes: Set<UInt16> = [123,124,125,126]
    static let modifierCodes: Set<UInt16> = [54,55,56,57,58,59,60,61,62,63]

    static let keys: [KeySpec] = {
        var result: [KeySpec] = []
        func key(_ code: UInt16, _ label: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1,
                 _ h: CGFloat = 0.91, symbol: String? = nil, name: String? = nil) {
            result.append(KeySpec(id: code, label: label, symbol: symbol, name: name ?? label,
                                  frame: CGRect(x: x, y: y, width: w, height: h), selectable: code != touchID))
        }
        key(53, "esc", 0, 0, 1.5, 0.64, name: "Escape")
        let functions: [(UInt16, String, String)] = [
            (122,"sun.min","F1, brightness down"), (120,"sun.max","F2, brightness up"),
            (99,"rectangle.3.group","F3, Mission Control"), (118,"magnifyingglass","F4, Spotlight"),
            (96,"mic","F5, dictation"), (97,"moon","F6, Focus"),
            (98,"backward.end","F7, previous"), (100,"playpause","F8, play or pause"),
            (101,"forward.end","F9, next"), (109,"speaker.slash","F10, mute"),
            (103,"speaker.wave.1","F11, volume down"), (111,"speaker.wave.2","F12, volume up")
        ]
        for (i, item) in functions.enumerated() {
            key(item.0, "F\(i+1)", 1.5+CGFloat(i), 0, 1, 0.64, symbol: item.1, name: item.2)
        }
        key(touchID, "", 13.5, 0, 1.5, 0.64, symbol: "touchid", name: "Touch ID and power, always available")
        let row1: [(UInt16,String)] = [(50,"\u{0060}"),(18,"1"),(19,"2"),(20,"3"),(21,"4"),(23,"5"),(22,"6"),(26,"7"),(28,"8"),(25,"9"),(29,"0"),(27,"−"),(24,"=")]
        for (i, k) in row1.enumerated() { key(k.0,k.1,CGFloat(i),0.76) }
        key(51,"delete",13,0.76,2,name:"Delete")
        key(48,"tab",0,1.73,1.5,name:"Tab")
        let row2: [(UInt16,String)] = [(12,"Q"),(13,"W"),(14,"E"),(15,"R"),(17,"T"),(16,"Y"),(32,"U"),(34,"I"),(31,"O"),(35,"P"),(33,"["),(30,"]")]
        for (i, k) in row2.enumerated() { key(k.0,k.1,1.5+CGFloat(i),1.73) }
        key(42,"\\",13.5,1.73,1.5,name:"Backslash")
        key(57,"caps lock",0,2.70,1.75,name:"Caps Lock")
        let row3: [(UInt16,String)] = [(0,"A"),(1,"S"),(2,"D"),(3,"F"),(5,"G"),(4,"H"),(38,"J"),(40,"K"),(37,"L"),(41,";"),(39,"'")]
        for (i, k) in row3.enumerated() { key(k.0,k.1,1.75+CGFloat(i),2.70) }
        key(36,"return",12.75,2.70,2.25,name:"Return")
        key(56,"shift",0,3.67,2.25,name:"Left Shift")
        let row4: [(UInt16,String)] = [(6,"Z"),(7,"X"),(8,"C"),(9,"V"),(11,"B"),(45,"N"),(46,"M"),(43,","),(47,"."),(44,"/")]
        for (i, k) in row4.enumerated() { key(k.0,k.1,2.25+CGFloat(i),3.67) }
        key(60,"shift",12.25,3.67,2.75,name:"Right Shift")
        key(63,"fn",0,4.64,1,0.84,symbol:"globe",name:"Fn / Globe")
        key(59,"control",1,4.64,1,0.84,symbol:"control",name:"Left Control")
        key(58,"option",2,4.64,1,0.84,symbol:"option",name:"Left Option")
        key(55,"command",3,4.64,1.25,0.84,symbol:"command",name:"Left Command")
        key(49,"",4.25,4.64,5,0.84,name:"Space")
        key(54,"command",9.25,4.64,1.25,0.84,symbol:"command",name:"Right Command")
        key(61,"option",10.5,4.64,1.5,0.84,symbol:"option",name:"Right Option")
        key(123,"",12,5.07,1,0.41,symbol:"arrowtriangle.left.fill",name:"Left Arrow")
        key(126,"",13,4.64,1,0.41,symbol:"arrowtriangle.up.fill",name:"Up Arrow")
        key(125,"",13,5.07,1,0.41,symbol:"arrowtriangle.down.fill",name:"Down Arrow")
        key(124,"",14,5.07,1,0.41,symbol:"arrowtriangle.right.fill",name:"Right Arrow")
        return result
    }()
    static let selectableCodes = Set(keys.filter(\.selectable).map(\.id))
    static func codes(for group: KeyGroup) -> Set<UInt16> {
        switch group {
        case .all: return selectableCodes
        case .letters: return letterCodes
        case .numbers: return numberCodes
        case .function: return functionCodes
        case .arrows: return arrowCodes
        case .left: return Set(keys.filter { $0.selectable && $0.frame.midX < width/2 }.map(\.id))
        case .right: return Set(keys.filter { $0.selectable && $0.frame.midX >= width/2 }.map(\.id))
        }
    }
    static func hit(at point: CGPoint) -> UInt16? {
        keys.first { $0.selectable && $0.frame.insetBy(dx: 0.035, dy: 0.035).contains(point) }?.id
    }
    static func enclosed(by rect: CGRect) -> Set<UInt16> {
        Set(keys.filter { $0.selectable && rect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map(\.id))
    }
}

struct KeyboardSelection {
    private(set) var codes = KeyboardLayout.selectableCodes
    private var dragBase: Set<UInt16>?
    mutating func replace(with new: Set<UInt16>) { codes = new.intersection(KeyboardLayout.selectableCodes); dragBase = nil }
    mutating func toggle(_ code: UInt16) {
        guard KeyboardLayout.selectableCodes.contains(code) else { return }
        if codes.contains(code) { codes.remove(code) } else { codes.insert(code) }
    }
    mutating func drag(from start: CGPoint, to end: CGPoint, additive: Bool) {
        if dragBase == nil { dragBase = additive ? codes : [] }
        let rect = CGRect(x: min(start.x,end.x), y: min(start.y,end.y), width: abs(start.x-end.x), height: abs(start.y-end.y))
        codes = (dragBase ?? []).union(KeyboardLayout.enclosed(by: rect))
    }
    mutating func endDrag() { dragBase = nil }
}
