import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size)
    let background = NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(calibratedRed: 0.35, green: 0.44, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.23, green: 0.28, blue: 0.73, alpha: 1))!.draw(in: background, angle: -60)
    NSColor.white.withAlphaComponent(0.38).setStroke()
    let back = NSBezierPath(roundedRect: NSRect(x: s * 0.24, y: s * 0.25, width: s * 0.52, height: s * 0.43), xRadius: s * 0.055, yRadius: s * 0.055)
    back.lineWidth = s * 0.04
    back.stroke()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.22, y: s * 0.34, width: s * 0.56, height: s * 0.41), xRadius: s * 0.055, yRadius: s * 0.055).fill()
    NSColor(calibratedRed: 0.32, green: 0.40, blue: 0.89, alpha: 1).setStroke()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: s * 0.32, y: s * 0.56))
    line.line(to: NSPoint(x: s * 0.68, y: s * 0.56))
    line.lineWidth = s * 0.035
    line.lineCapStyle = .round
    line.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
for size in [16, 32, 48, 128] {
    try drawIcon(size: size).write(to: root.appendingPathComponent("extension/icon\(size).png"))
}
