import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210).fill()
        let track = NSBezierPath(ovalIn: NSRect(x: 220, y: 220, width: 584, height: 584))
        track.lineWidth = 64
        NSColor.white.withAlphaComponent(0.22).setStroke()
        track.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 292, startAngle: 90, endAngle: -155, clockwise: true)
        arc.lineWidth = 64
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 0.38, green: 0.90, blue: 0.73, alpha: 1).setStroke()
        arc.stroke()
        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: 512, y: 512))
        needle.line(to: NSPoint(x: 635, y: 635))
        needle.lineWidth = 52
        needle.lineCapStyle = .round
        NSColor.white.setStroke()
        needle.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 468, y: 468, width: 88, height: 88)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
    }
}
