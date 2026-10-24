import AppKit

let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
let blue = NSColor(calibratedRed:0.17,green:0.43,blue:0.92,alpha:1)
for (name,size) in [
    ("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
    ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),
    ("icon_512x512",512),("icon_512x512@2x",1024)
] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,
                                  samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
                                  bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep:bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    let base = NSBezierPath(roundedRect:NSRect(x:92,y:92,width:840,height:840),xRadius:185,yRadius:185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width:0,height:-12); shadow.set()
    NSColor.white.setFill(); base.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors:[NSColor(calibratedWhite:0.79,alpha:1),.white])!.draw(in:base,angle:90)
    let face = NSBezierPath(roundedRect:NSRect(x:179,y:212,width:666,height:635),xRadius:132,yRadius:132)
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow(); keyShadow.shadowColor = blue.withAlphaComponent(0.18)
    keyShadow.shadowBlurRadius = 32; keyShadow.shadowOffset = NSSize(width:0,height:-20); keyShadow.set()
    NSColor.white.setFill(); face.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors:[NSColor(calibratedRed:0.84,green:0.90,blue:0.99,alpha:1),.white])!.draw(in:face,angle:75)
    NSColor.white.setStroke(); face.lineWidth = 5; face.stroke()
    if let symbol = NSImage(systemSymbolName:"moon.zzz.fill",accessibilityDescription:nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors:[blue])) {
        symbol.draw(in:NSRect(x:309,y:343,width:406,height:370))
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
}
