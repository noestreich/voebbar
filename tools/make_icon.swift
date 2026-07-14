import AppKit

// Renders the app icon at 1024×1024 and writes a PNG.
// Usage: swift make_icon.swift <text> <out.png>

let text = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "oe"
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon.png"

let px = 1024
let coral = NSColor(calibratedRed: 0.906, green: 0.404, blue: 0.314, alpha: 1) // ~#E7674F

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("no rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let size = CGFloat(px)
let full = NSRect(x: 0, y: 0, width: size, height: size)

// Rounded-rect (squircle-ish) background, transparent corners.
let radius = size * 0.2237
let bg = NSBezierPath(roundedRect: full, xRadius: radius, yRadius: radius)
coral.setFill()
bg.fill()

// "oe" text, bold rounded, white, centered — sized to ~72% of width.
func roundedFont(_ pointSize: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: pointSize, weight: .bold)
    if let d = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: d, size: pointSize) ?? base
    }
    return base
}

var fontSize: CGFloat = 600
var attrs: [NSAttributedString.Key: Any] = [
    .font: roundedFont(fontSize),
    .foregroundColor: NSColor.white,
]
var str = NSAttributedString(string: text, attributes: attrs)
let targetWidth = size * 0.72
if str.size().width > 0 {
    fontSize *= targetWidth / str.size().width
    attrs[.font] = roundedFont(fontSize)
    str = NSAttributedString(string: text, attributes: attrs)
}
let sz = str.size()
str.draw(at: NSPoint(x: (size - sz.width) / 2, y: (size - sz.height) / 2))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(px)x\(px), text=\"\(text)\")")
