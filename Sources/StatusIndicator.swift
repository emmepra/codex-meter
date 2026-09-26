import AppKit

struct StatusIndicator {
    static func image(used: Double?, uncertain: Bool, showPercentage: Bool, refreshing: Bool, resetCount: Int?, appearance: NSAppearance, updateAvailable: Bool = false, unreadAnnouncement: Bool = false) -> NSImage {
        let used = used.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        let hasDots = updateAvailable || unreadAnnouncement || (resetCount ?? 0) > 0
        let width: CGFloat = hasDots ? 24 : 20
        let centerX = width / 2
        let image = NSImage(size: NSSize(width: width, height: 20), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let background = NSBezierPath(ovalIn: NSRect(x: centerX - 8.5, y: 1.5, width: 17, height: 17))
                background.lineWidth = 1.4
                NSColor.labelColor.withAlphaComponent(uncertain ? 0.45 : 0.22).setStroke()
                background.stroke()
                if let used, used > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: NSPoint(x: centerX, y: 10), radius: 8.5,
                                  startAngle: 90, endAngle: CGFloat(90 - min(100, max(0, used)) * 3.6), clockwise: true)
                    arc.lineWidth = 1.5
                    arc.lineCapStyle = .round
                    NSColor.labelColor.withAlphaComponent(uncertain ? 0.45 : 1).setStroke()
                    arc.stroke()
                }
                let centerText: String?
                if let used {
                    centerText = showPercentage ? String(Int(min(100, max(0, used)).rounded())) : (uncertain ? "!" : nil)
                } else {
                    centerText = uncertain ? "!" : (refreshing ? "…" : "—")
                }
                if let centerText {
                    let fontSize: CGFloat = centerText.count >= 3 ? 7.2 : 9.0
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                        .foregroundColor: NSColor.labelColor.withAlphaComponent(uncertain ? 0.65 : 1)
                    ]
                    let textSize = (centerText as NSString).size(withAttributes: attributes)
                    let origin = NSPoint(x: (width - textSize.width) / 2, y: (20 - textSize.height) / 2)
                    (centerText as NSString).draw(at: origin, withAttributes: attributes)
                }
                func dot(_ color: NSColor, x: CGFloat, y: CGFloat) {
                    color.setFill()
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3.5, height: 3.5)).fill()
                }
                if (resetCount ?? 0) > 0 { dot(.systemGreen, x: 0, y: 16.5) }
                if updateAvailable { dot(.systemBlue, x: 20.5, y: 16.5) }
                if unreadAnnouncement { dot(.systemOrange, x: 20.5, y: 0) }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
