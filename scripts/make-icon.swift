import AppKit

// One geometry for app icons, the transparent panel mark and repository artwork.
// Build: swift scripts/make-icon.swift <AppIcon.iconset>
// Refresh public artwork: swift scripts/make-icon.swift --brand <repository-root>
enum MeterArtwork {
    static let ink = color(0x192426)
    static let tileTop = color(0x2C3431)
    static let paper = color(0xF6F2E9)
    static let teal = color(0x48CCB0)
    static let terracotta = color(0xEF9B78)
    static let track = color(0x87928B, alpha: 0.34)
    static let radius: CGFloat = 190
    static let stroke: CGFloat = 68
    static let rings: [(x: CGFloat, start: CGFloat, end: CGFloat, color: NSColor, hex: String)] = [
        (354, 90, -155, teal, "#48CCB0"),
        (670, 38, -207, terracotta, "#EF9B78")
    ]

    static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: alpha)
    }

    static func mark(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 1024, yBy: rect.height / 1024)
        transform.concat()
        for ring in rings {
            let path = NSBezierPath(ovalIn: NSRect(x: ring.x - radius, y: 512 - radius,
                                                   width: radius * 2, height: radius * 2))
            path.lineWidth = stroke
            track.setStroke()
            path.stroke()
        }
        for ring in rings {
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: ring.x, y: 512), radius: radius,
                           startAngle: ring.start, endAngle: ring.end, clockwise: true)
            path.lineWidth = stroke
            path.lineCapStyle = .round
            ring.color.setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func icon() {
        let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920),
                                xRadius: 210, yRadius: 210)
        NSGradient(starting: ink, ending: tileTop)!.draw(in: tile, angle: 90)
        mark(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    }

    static func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
                     weight: NSFont.Weight, color: NSColor) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }

    static func banner(height: CGFloat = 540) {
        let offset = (height - 540) / 2
        ink.setFill()
        NSRect(x: 0, y: 0, width: 1600, height: height).fill()
        teal.setFill()
        NSBezierPath(roundedRect: NSRect(x: 88, y: 433 + offset, width: 48, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
        terracotta.setFill()
        NSBezierPath(roundedRect: NSRect(x: 146, y: 433 + offset, width: 28, height: 5), xRadius: 2.5, yRadius: 2.5).fill()
        text("Codex Meter", x: 82, y: 302 + offset, size: 100, weight: .semibold, color: paper)
        text("Both limits. One glance.", x: 88, y: 231 + offset, size: 47, weight: .regular, color: paper)
        text("Codex + Claude Code · Native for macOS", x: 91, y: 146 + offset, size: 24,
             weight: .regular, color: color(0xA8B7B0))
        mark(in: NSRect(x: 903, y: -75 + offset, width: 690, height: 690))
    }

    static func png(width: Int, height: Int, logicalWidth: CGFloat, logicalHeight: CGFloat,
                    draw: () -> Void) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.bitmapData!.initialize(repeating: 0, count: bitmap.bytesPerRow * height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.scaleX(by: CGFloat(width) / logicalWidth, yBy: CGFloat(height) / logicalHeight)
        transform.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func markSVG() -> String {
        let tracks = rings.map { "<circle cx=\"\(Int($0.x))\" cy=\"512\" r=\"190\"/>" }.joined(separator: "\n")
        let arcs = rings.map { ring -> String in
            func point(_ angle: CGFloat) -> String {
                let radians = angle * .pi / 180
                return String(format: "%.3f %.3f", Double(ring.x + radius * cos(radians)), Double(512 - radius * sin(radians)))
            }
            return "<path d=\"M \(point(ring.start)) A 190 190 0 1 1 \(point(ring.end))\" stroke=\"\(ring.hex)\"/>"
        }.joined(separator: "\n")
        return """
        <g fill="none" stroke-width="68">
          <g stroke="#87928B" stroke-opacity="0.34">
        \(tracks)
          </g>
          <g stroke-linecap="round">
        \(arcs)
          </g>
        </g>
        """
    }

    static func logoSVG() -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024" role="img" aria-labelledby="title desc">
          <title id="title">Codex Meter mark</title>
          <desc id="desc">Two parallel, overlapping meter rings in teal and terracotta. An independent geometric project mark.</desc>
        \(markSVG())
        </svg>

        """
    }

    static func bannerSVG() -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" width="1600" height="540" viewBox="0 0 1600 540" role="img" aria-labelledby="title desc">
          <title id="title">Codex Meter — Both limits. One glance.</title>
          <desc id="desc">Codex and Claude Code quota in one native macOS app. Abstract twin rings; no account data or interface screenshot.</desc>
          <rect width="1600" height="540" fill="#192426"/>
          <rect x="88" y="102" width="48" height="5" rx="2.5" fill="#48CCB0"/>
          <rect x="146" y="102" width="28" height="5" rx="2.5" fill="#EF9B78"/>
          <g font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif">
            <text x="82" y="216" fill="#F6F2E9" font-size="100" font-weight="600">Codex Meter</text>
            <text x="88" y="298" fill="#F6F2E9" font-size="47">Both limits. One glance.</text>
            <text x="91" y="385" fill="#A8B7B0" font-size="24">Codex + Claude Code · Native for macOS</text>
          </g>
          <g transform="translate(903 -75) scale(0.673828125)">
        \(markSVG())
          </g>
        </svg>

        """
    }

    static func preview() {
        paper.setFill()
        NSRect(x: 0, y: 0, width: 960, height: 430).fill()
        ink.setFill()
        NSRect(x: 480, y: 0, width: 480, height: 430).fill()
        for offset: CGFloat in [0, 480] {
            text("ICON / MARK", x: offset + 32, y: 384, size: 12, weight: .medium,
                 color: offset == 0 ? ink : paper)
            for (index, size) in [16, 32, 64, 128].enumerated() {
                let x = offset + 32 + CGFloat(index) * 105
                let edge = CGFloat(size)
                let image = NSImage(data: png(width: size, height: size, logicalWidth: 1024, logicalHeight: 1024, draw: icon))!
                image.draw(in: NSRect(x: x, y: 222, width: edge, height: edge))
                let symbol = NSImage(data: png(width: size, height: size, logicalWidth: 1024, logicalHeight: 1024) {
                    mark(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
                })!
                symbol.draw(in: NSRect(x: x, y: 65, width: edge, height: edge))
                text("\(size) px", x: x, y: 31, size: 11, weight: .regular,
                     color: offset == 0 ? ink : paper)
            }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 || (arguments.count == 2 && arguments[0] == "--brand") else {
    fputs("Usage: make-icon.swift <AppIcon.iconset> | --brand <repository-root>\n", stderr)
    exit(1)
}
let files = FileManager.default
if arguments[0] == "--brand" {
    guard arguments.count == 2 else { exit(1) }
    let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
    for folder in ["assets", "Resources", ".build"] {
        try files.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    let logo = Data(MeterArtwork.logoSVG().utf8)
    try logo.write(to: root.appendingPathComponent("assets/logo.svg"))
    try logo.write(to: root.appendingPathComponent("Resources/MeterMark.svg"))
    try Data(MeterArtwork.bannerSVG().utf8).write(to: root.appendingPathComponent("assets/banner.svg"))
    for (path, size) in [("assets/logo.png", 1024), ("Resources/MeterMark.png", 256)] {
        try MeterArtwork.png(width: size, height: size, logicalWidth: 1024, logicalHeight: 1024) {
            MeterArtwork.mark(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        }.write(to: root.appendingPathComponent(path))
    }
    try MeterArtwork.png(width: 1600, height: 540, logicalWidth: 1600, logicalHeight: 540) {
        MeterArtwork.banner()
    }.write(to: root.appendingPathComponent("assets/banner.png"))
    try MeterArtwork.png(width: 1600, height: 800, logicalWidth: 1600, logicalHeight: 800) {
        MeterArtwork.banner(height: 800)
    }.write(to: root.appendingPathComponent("assets/social-preview.png"))
    try MeterArtwork.png(width: 960, height: 430, logicalWidth: 960, logicalHeight: 430,
                         draw: MeterArtwork.preview).write(to: root.appendingPathComponent(".build/brand-preview.png"))
} else {
    let output = URL(fileURLWithPath: arguments[0], isDirectory: true)
    try files.createDirectory(at: output, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
            try MeterArtwork.png(width: pixels, height: pixels, logicalWidth: 1024, logicalHeight: 1024,
                                 draw: MeterArtwork.icon).write(to: output.appendingPathComponent(name))
        }
    }
}
