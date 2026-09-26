import AppKit
import SwiftUI

@main
struct MeterPanelTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var dateCalendar = Calendar(identifier: .gregorian)
        dateCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateNow = Date(timeIntervalSince1970: 1_800_000_000)
        precondition(postDateLabel(dateNow, now: dateNow, calendar: dateCalendar) == "Today")
        precondition(postDateLabel(dateNow.addingTimeInterval(-86400), now: dateNow, calendar: dateCalendar) == "Yesterday")
        precondition(postDateLabel(dateNow.addingTimeInterval(-172800), now: dateNow, calendar: dateCalendar) != "Yesterday")
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
        precondition(store.statusResetCount == 3)
        store.error = "Could not read usage limits. Try again shortly."
        precondition(store.resetAvailabilityText == "3 · Out of date")
        precondition(store.statusResetCount == nil)
        store.error = nil
        store.updatedAt = now.addingTimeInterval(-601)
        precondition(store.resetAvailabilityText == "3 · Out of date")
        precondition(store.statusResetCount == nil)
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
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: appearanceName)!
            for resetCount: Int? in [nil, 0, 1, 3] {
                let updateIcon = StatusIndicator.image(used: 37, uncertain: false, showPercentage: true,
                    refreshing: false, resetCount: resetCount, appearance: appearance, updateAvailable: true)
                precondition(updateIcon.size.width == 24)
                let updateBitmap = NSBitmapImageRep(data: updateIcon.tiffRepresentation!)!
                try updateBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:
                    ".build/update-\(appearanceName.rawValue)-\(resetCount.map(String.init) ?? "unknown").png"))
                for used: Double? in [nil, 0, 37, 100, .nan, .infinity] {
                    for uncertain in [false, true] {
                        let icon = StatusIndicator.image(used: used, uncertain: uncertain,
                            showPercentage: true, refreshing: false, resetCount: resetCount, appearance: appearance)
                        precondition(icon.size.width == ((resetCount ?? 0) > 0 ? 24 : 20))
                        precondition(icon.size.height == 20)
                        precondition(icon.tiffRepresentation != nil)
                    }
                }
                let icon = StatusIndicator.image(used: 37, uncertain: false, showPercentage: true,
                    refreshing: false, resetCount: resetCount, appearance: appearance)
                let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:
                    ".build/status-\(appearanceName.rawValue)-\(resetCount.map(String.init) ?? "unknown").png"))
            }
            for update in [false, true] {
                for unread in [false, true] {
                    let icon = StatusIndicator.image(used: 37, uncertain: false, showPercentage: true,
                        refreshing: false, resetCount: 1, appearance: appearance,
                        updateAvailable: update, unreadAnnouncement: unread)
                    precondition(icon.size.width == 24)
                    let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:
                        ".build/corner-dots-\(appearanceName.rawValue)-\(update)-\(unread).png"))
                }
            }
            let view = NSHostingView(rootView: MeterPanel(store: store)
                .environment(\.colorScheme, appearanceName == .darkAqua ? .dark : .light)
                .background(Color(nsColor: .windowBackgroundColor)))
            view.appearance = appearance
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:
                ".build/panel-\(appearanceName.rawValue).png"))
        }
        // Reproducible README preview: no network, account data or real post text.
        let demoPreferences = UserDefaults(suiteName: "CodexMeter.SyntheticPreview")!
        demoPreferences.removePersistentDomain(forName: "CodexMeter.SyntheticPreview")
        defer { demoPreferences.removePersistentDomain(forName: "CodexMeter.SyntheticPreview") }
        let demoPost = ResetAnnouncement(id: "1", text: "Demo announcement: we will reset usage limits tomorrow for everyone. More details soon.", date: now)
        let demoAnnouncements = ResetAnnouncements(preferences: demoPreferences, latest: demoPost)
        let demo = NSHostingView(rootView: MeterPanel(store: store, announcements: demoAnnouncements)
            .environment(\.colorScheme, .dark)
            .background(Color(nsColor: .windowBackgroundColor)))
        demo.appearance = NSAppearance(named: .darkAqua)
        demo.frame = NSRect(origin: .zero, size: demo.fittingSize)
        demo.layoutSubtreeIfNeeded()
        let demoBitmap = demo.bitmapImageRepForCachingDisplay(in: demo.bounds)!
        demo.cacheDisplay(in: demo.bounds, to: demoBitmap)
        try demoBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/readme-demo.png"))
        store.error = "Could not read usage limits. Try again shortly."
        try render("stale")
        store.error = nil
        store.snapshot = try snapshot(#", "rateLimitResetCredits":{"availableCount":0}"#)
        precondition(store.resetAvailabilityText == "0 available")
        precondition(store.statusResetCount == 0)
        try render("zero")
        store.snapshot = try snapshot("")
        precondition(store.resetAvailabilityText == "Unavailable", "A new snapshot must clear the previous count")
        precondition(store.statusResetCount == nil)
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
