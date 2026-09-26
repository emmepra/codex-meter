import AppKit
import SwiftUI

@main
struct MeterPanelTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let store = MeterStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.now = now
        store.updatedAt = now
        let quota = #""rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800003600}}"#
        func snapshot(_ metadata: String, quotaFields: String? = nil) throws -> UsageSnapshot {
            try UsageSnapshot(data: Data(("{" + (quotaFields ?? quota) + metadata + "}").utf8))
        }
        let positive = try snapshot(#", "rateLimitResetCredits":{"availableCount":3}"#)
        store.snapshot = positive
        precondition(store.resetAvailabilityText == "3 available")
        store.error = "Could not read usage limits. Try again shortly."
        precondition(store.resetAvailabilityText == "3 · Out of date")
        store.error = nil
        store.updatedAt = now.addingTimeInterval(-601)
        precondition(store.resetAvailabilityText == "3 · Out of date")
        store.updatedAt = now
        store.now = now.addingTimeInterval(3601)
        store.updatedAt = store.now
        precondition(store.resetPending)
        precondition(store.resetAvailabilityText == "3 available", "Quota reset pending is not credit staleness")
        store.now = now
        store.updatedAt = now

        func render(_ name: String) throws {
            let view = NSHostingView(rootView: MeterPanel(store: store)
                .background(Color(nsColor: .windowBackgroundColor)))
            let size = view.fittingSize
            precondition(size.width == 270 && size.height > 0)
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/reset-\(name).png"))
        }
        try render("available")
        store.error = "Could not read usage limits. Try again shortly."
        try render("stale")
        store.error = nil
        store.snapshot = try snapshot(#", "rateLimitResetCredits":{"availableCount":0}"#)
        precondition(store.resetAvailabilityText == "0 available")
        try render("zero")
        store.snapshot = try snapshot("")
        precondition(store.resetAvailabilityText == "Unavailable", "A new snapshot must clear the previous count")
        try render("unavailable")
        store.snapshot = positive
        store.snapshot = try snapshot(#", "rateLimitResetCredits":null"#)
        precondition(store.resetAvailabilityText == "Unavailable")
        store.snapshot = try snapshot(#", "rateLimitResetCredits":{"availableCount":3}"#, quotaFields: #""rateLimits":null"#)
        precondition(store.entry == nil && store.resetAvailabilityText == "3 available")
        try render("no-window")
        print("Meter panel state and synthetic rendering tests passed")
    }
}
