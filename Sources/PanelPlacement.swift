import Foundation
import CoreGraphics

enum PanelPlacement {
    /// AppKit screen coordinates are measured in points, with Y increasing upward.
    /// Recompute the whole frame after a size change so the top stays at the anchor.
    static func frame(anchor: NSRect, size: NSSize, screen: NSRect) -> NSRect {
        let values = [anchor.minX, anchor.minY, anchor.width, anchor.height,
                      size.width, size.height, screen.minX, screen.minY,
                      screen.width, screen.height, screen.maxX, screen.maxY]
        guard values.allSatisfy({ $0.isFinite }), screen.width > 0, screen.height > 0,
              anchor.width >= 0, anchor.height >= 0 else { return .zero }

        // Preserve usable space if a synthetic or transitional screen is narrower
        // than the two cosmetic margins. Real displays keep an 8-point inset.
        let inset: CGFloat = screen.width > 16 ? 8 : 0
        let width = min(max(0, size.width), screen.width - 2 * inset)
        let top = min(max(anchor.minY, screen.minY), screen.maxY)
        let height = min(max(0, size.height), top - screen.minY)
        let x = min(max(anchor.midX - width / 2, screen.minX + inset),
                    screen.maxX - inset - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }
}
