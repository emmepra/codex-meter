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
        let originalIconOnly = store.iconOnly
        let originalSelectedID = store.selectedID
        store.iconOnly = false
        defer { store.iconOnly = originalIconOnly; store.selectedID = originalSelectedID }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        store.now = now
        store.updatedAt = now
        let quota = #""rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800003600}}"#
        func snapshot(_ metadata: String, quotaFields: String? = nil) throws -> UsageSnapshot {
            try UsageSnapshot(data: Data(("{" + (quotaFields ?? quota) + metadata + "}").utf8))
        }
        func creditSnapshot(_ amount: Double, used: Double = 100, reset: Double = 1_800_003_600,
                            secondary: Double? = nil, secondaryReset: Double = 1_800_007_200) throws -> UsageSnapshot {
            var limits: [String: Any] = [
                "primary": ["usedPercent": used, "windowDurationMins": 10080, "resetsAt": reset],
                "credits": ["hasCredits": true, "unlimited": false, "balance": String(amount)]
            ]
            if let secondary { limits["secondary"] = ["usedPercent": secondary, "resetsAt": secondaryReset] }
            return try UsageSnapshot(data: JSONSerialization.data(withJSONObject: [
                "rateLimits": limits, "meterCreditScope": "synthetic",
                "rateLimitResetCredits": ["availableCount": 1]
            ]))
        }
        func observeCredit(_ amount: Double, at date: Date, used: Double = 100,
                           reset: Double = 1_800_003_600) throws {
            store.snapshot = try creditSnapshot(amount, used: used, reset: reset)
            store.observeCredits(at: date)
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
            for resetAvailable in [false, true] {
                for unread in [false, true] {
                    let icon = StatusIndicator.image(used: 37, uncertain: false, showPercentage: true,
                        refreshing: false, resetCount: resetAvailable ? 1 : 0, appearance: appearance,
                        unreadAnnouncement: unread)
                    precondition(icon.size.width == (resetAvailable || unread ? 24 : 20))
                    let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath:
                        ".build/corner-dots-\(appearanceName.rawValue)-\(resetAvailable)-\(unread).png"))
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
        try observeCredit(900, at: now.addingTimeInterval(-2100), used: 99, reset: 1_800_007_200)
        try observeCredit(900, at: now.addingTimeInterval(-1800), reset: 1_800_007_200)
        for index in 1...6 {
            try observeCredit(Double(900 - index * 10), at: now.addingTimeInterval(Double(index * 300 - 1800)), reset: 1_800_007_200)
        }
        precondition(store.creditBalanceText == "840" && store.creditInUse)
        let demo = MeterPanel(store: store, announcements: demoAnnouncements, staticPreview: true)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
        // Render SwiftUI directly at 4x instead of enlarging an offscreen view cache.
        let renderer = ImageRenderer(content: demo)
        renderer.scale = 4
        let demoBitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try demoBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/readme-demo.png"))
        store.creditPace.reset()
        store.error = "Could not read usage limits. Try again shortly."
        try render("stale")
        store.error = nil
        store.snapshot = try snapshot(#", "rateLimitResetCredits":{"availableCount":1}"#)
        precondition(store.resetAvailabilityText == "1 available")
        precondition(store.statusResetCount == 1)
        try render("one")
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
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic", "rateLimitResetCredits":{"availableCount":1}"#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1800003600},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(!store.creditInUse, "Exhausted quota alone is not observed credit consumption")
        try observeCredit(850, at: now.addingTimeInterval(-300))
        try observeCredit(840, at: now)
        precondition(store.creditInUse && store.creditRateText == "Estimating…")
        store.creditPace.reset()
        try observeCredit(900, at: now.addingTimeInterval(-1800))
        for index in 1...6 {
            try observeCredit(Double(900 - index * 10), at: now.addingTimeInterval(Double(index * 300 - 1800)))
        }
        precondition(store.creditInUse)
        precondition(store.creditRateText == "120 cr/h")
        precondition(store.creditRunwayText == "≈7 h")
        try render("credits")
        let creditPreview = ImageRenderer(content: MeterPanel(store: store, staticPreview: true)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12)))
        creditPreview.scale = 4
        let creditBitmap = NSBitmapImageRep(cgImage: creditPreview.cgImage!)
        try creditBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/credits-preview.png"))
        store.error = "Synthetic failure"
        precondition(!store.creditInUse && store.creditRate == nil)
        precondition(store.creditBalanceText == "840 · Out of date" && store.creditRateText == "Unavailable")
        store.error = nil
        store.iconOnly = true
        precondition(store.creditInUse, "Ring-only display does not change observed credit activity")
        store.iconOnly = false
        store.snapshot = try creditSnapshot(840, used: 80)
        store.observeCredits(at: now.addingTimeInterval(1))
        store.now = now.addingTimeInterval(1)
        precondition(!store.creditInUse && store.creditRate != nil,
                     "Quota recovery does not restart independent balance observations")
        store.snapshot = try creditSnapshot(840)
        store.observeCredits(at: now.addingTimeInterval(2))
        store.now = now.addingTimeInterval(2)
        precondition(store.creditRate != nil, "Reaching 100% does not start a credit-spend counter or erase recent pace")
        store.snapshot = try snapshot("",
            quotaFields: #""rateLimits":{"primary":{"usedPercent":100,"resetsAt":1800003600},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(!store.creditInUse && store.creditRate == nil,
                     "Unscoped balances cannot use the previous account's credit estimate")
        store.selectedID = "codex/primary"
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":25,"resetsAt":1800003600},"secondary":{"usedPercent":100,"resetsAt":1799999999},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(!store.resetPending && !store.creditInUse, "An unconfirmed exhausted window cannot activate credit consumption")
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":25,"resetsAt":1799999999},"secondary":{"usedPercent":100,"resetsAt":1800003600},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(store.resetPending && store.creditInUse, "Credit consumption is independent of an unrelated selected window")
        // A recent average can survive a pause, but no credit estimate is shown compactly.
        store.creditPace.reset()
        let pauseStart = now.addingTimeInterval(10_000)
        let pauseReset = pauseStart.timeIntervalSince1970 + 7200
        store.now = pauseStart
        store.updatedAt = store.now
        try observeCredit(1000, at: store.now, reset: pauseReset)
        precondition(store.creditBalanceText == "1,000" && store.creditRate == nil)
        try render("credit-estimating")
        for index in 1...6 {
            store.now = pauseStart.addingTimeInterval(Double(index * 300))
            store.updatedAt = store.now
            try observeCredit(970, at: store.now, reset: pauseReset)
        }
        precondition(!store.creditInUse && store.creditRateText == "60 cr/h")
        precondition(store.creditBalanceText == "970")
        try render("credit-recent-average")
        for index in 7...12 {
            store.now = pauseStart.addingTimeInterval(Double(index * 300))
            store.updatedAt = store.now
            try observeCredit(970, at: store.now, reset: pauseReset)
        }
        precondition(store.creditRateText == "Awaiting balance updates" && store.creditBalanceText == "970")
        try render("credit-flat-window")
        store.now = pauseStart.addingTimeInterval(3900)
        store.updatedAt = store.now
        try observeCredit(960, at: store.now, reset: pauseReset)
        precondition(store.creditBalanceText == "960" && store.creditRate != nil && store.creditInUse)
        try observeCredit(0, at: store.now.addingTimeInterval(1), reset: pauseReset)
        precondition(store.creditBalanceText == "0" && store.creditRunwayText == "Exhausted" && !store.creditInUse)
        store.snapshot = try snapshot(#", "meterCreditScope":"different-account""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":100},"credits":{"hasCredits":true,"unlimited":false,"balance":"500"}}"#)
        store.observeCredits(at: store.now.addingTimeInterval(2))
        precondition(store.creditRate == nil && !store.creditInUse)
        print("Meter panel state and synthetic rendering tests passed")
    }
}
