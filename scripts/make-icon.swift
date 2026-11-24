import AppKit
let output = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(srgbRed: 0.065, green: 0.095, blue: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
let blocks: [(NSRect, NSColor)] = [
    (NSRect(x: 170, y: 170, width: 350, height: 684), NSColor(srgbRed: 0.38, green: 0.78, blue: 0.65, alpha: 1)),
    (NSRect(x: 550, y: 482, width: 304, height: 372), NSColor(srgbRed: 0.34, green: 0.56, blue: 0.82, alpha: 1)),
    (NSRect(x: 550, y: 170, width: 304, height: 282), NSColor(srgbRed: 0.80, green: 0.59, blue: 0.33, alpha: 1))
]
for (rect, color) in blocks {
    color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36).fill()
    color.blended(withFraction: 0.25, of: .white)!.setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 35, yRadius: 35); border.lineWidth = 3; border.stroke()
}
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
