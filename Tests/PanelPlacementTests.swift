import Foundation
import CoreGraphics

@main
enum PanelPlacementTests {
    static func main() {
        func close(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
            precondition(abs(actual - expected) < 0.000_001, message)
        }
        func contained(_ frame: NSRect, in screen: NSRect, _ message: String) {
            precondition(frame.minX >= screen.minX && frame.maxX <= screen.maxX
                         && frame.minY >= screen.minY && frame.maxY <= screen.maxY, message)
        }

        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = NSRect(x: 1000, y: 875, width: 40, height: 25)
        let loading = PanelPlacement.frame(anchor: anchor, size: NSSize(width: 270, height: 107), screen: screen)
        let loaded = PanelPlacement.frame(anchor: anchor, size: NSSize(width: 270, height: 230), screen: screen)
        close(loading.maxY, anchor.minY, "Loading panel attaches to the menu bar")
        close(loaded.maxY, loading.maxY, "Fetching data and growing from 107 to 230 points must not move the top")
        close(loaded.minY, loading.minY - 123, "Additional content grows downward")
        close(loaded.midX, anchor.midX, "Panel is centered below the status item")
        close(loaded.width, 270, "Normal display preserves the compact width")

        for origin in [NSPoint(x: -1440, y: -200), NSPoint(x: 1440, y: 300)] {
            let translatedScreen = screen.offsetBy(dx: origin.x, dy: origin.y)
            let translatedAnchor = anchor.offsetBy(dx: origin.x, dy: origin.y)
            let result = PanelPlacement.frame(anchor: translatedAnchor,
                size: loaded.size, screen: translatedScreen)
            close(result.minX, loaded.minX + origin.x, "Horizontal display origin is preserved")
            close(result.maxY, loaded.maxY + origin.y, "Vertical display origin is preserved")
            contained(result, in: translatedScreen, "Panel fits the selected display")
        }

        for (x, expectedX) in [(CGFloat(0), CGFloat(8)), (CGFloat(1400), CGFloat(1162))] {
            let edgeAnchor = NSRect(x: x, y: 875, width: 40, height: 25)
            let result = PanelPlacement.frame(anchor: edgeAnchor, size: loaded.size, screen: screen)
            close(result.minX, expectedX, "Horizontal edge keeps an 8-point inset")
            close(result.maxY, anchor.minY, "Clamping horizontally must not move the top")
        }

        let huge = PanelPlacement.frame(anchor: anchor, size: NSSize(width: 5000, height: 5000), screen: screen)
        close(huge.height, 875, "Oversized content is limited to the space below the menu bar")
        close(huge.minY, screen.minY, "Tall panel stays above the screen bottom")
        close(huge.maxY, anchor.minY, "Tall panel does not overlap the menu bar")
        close(huge.width, 1424, "Oversized width leaves both horizontal margins")

        let narrowScreen = NSRect(x: -200, y: -100, width: 200, height: 500)
        let narrow = PanelPlacement.frame(anchor: NSRect(x: -40, y: 375, width: 40, height: 25),
            size: loaded.size, screen: narrowScreen)
        close(narrow.width, 184, "Narrow display caps the panel width")
        contained(narrow, in: narrowScreen, "Narrow display does not produce an offscreen panel")
        let tinyScreen = NSRect(x: 0, y: 0, width: 12, height: 40)
        let tiny = PanelPlacement.frame(anchor: NSRect(x: 0, y: 30, width: 12, height: 10),
            size: loaded.size, screen: tinyScreen)
        close(tiny.width, 12, "A screen smaller than the margins retains usable width")
        contained(tiny, in: tinyScreen, "Tiny screen still contains the frame")

        let fractionalAnchor = NSRect(x: 1000.25, y: 875.5, width: 39.5, height: 24.5)
        let fractional = PanelPlacement.frame(anchor: fractionalAnchor,
            size: NSSize(width: 270, height: 230.25), screen: screen)
        close(fractional.maxY, 875.5, "Fractional point geometry is not rounded to pixels")
        close(fractional.height, 230.25, "Content height stays in points")

        precondition(PanelPlacement.frame(anchor: anchor, size: loaded.size, screen: .zero) == .zero,
                     "Invalid screen returns an empty frame")
        precondition(PanelPlacement.frame(anchor: anchor, size: NSSize(width: CGFloat.infinity, height: 230), screen: screen) == .zero,
                     "Non-finite input returns an empty frame")
        print("PanelPlacementTests passed")
    }
}
