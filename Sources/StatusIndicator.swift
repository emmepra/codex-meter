import AppKit

struct StatusIndicator {
    static func image(used: Double?, uncertain: Bool, showPercentage: Bool, refreshing: Bool, resetCount: Int?, appearance: NSAppearance, updateAvailable: Bool = false) -> NSImage {
        let used = used.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        let image = NSImage(size: NSSize(width: updateAvailable || (resetCount ?? 0) > 0 ? 28 : 20, height: 20), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let background = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 17, height: 17))
                background.lineWidth = 1.4
                NSColor.labelColor.withAlphaComponent(uncertain ? 0.45 : 0.22).setStroke()
                background.stroke()
                if let used, used > 0 {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: NSPoint(x: 10, y: 10), radius: 8.5,
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
                    let origin = NSPoint(x: (20 - textSize.width) / 2, y: (20 - textSize.height) / 2)
                    (centerText as NSString).draw(at: origin, withAttributes: attributes)
                }
                if updateAvailable || (resetCount ?? 0) > 0 {
                    (updateAvailable ? NSColor.systemBlue : NSColor.systemGreen).setFill()
                    NSBezierPath(ovalIn: NSRect(x: 23, y: 8, width: 4, height: 4)).fill()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
