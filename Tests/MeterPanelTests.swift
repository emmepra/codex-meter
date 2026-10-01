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
        precondition(store.creditSpendLabel == "Since quota exhausted")
        precondition(store.creditSpentText == "60 cr")
        precondition(store.creditNeededText == "≈240 cr")
        let demo = MeterPanel(store: store, announcements: demoAnnouncements, staticPreview: true)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12))
        // Render SwiftUI directly at 4x instead of enlarging an offscreen view cache.
        let renderer = ImageRenderer(content: demo)
        renderer.scale = 4
        let demoBitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
        try demoBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/readme-demo.png"))
        store.creditSpend = CreditSpendTracker()
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
        precondition(!store.creditInUse && store.creditPeriod == nil, "Exhausted quota alone is not observed credit consumption")
        try observeCredit(850, at: now.addingTimeInterval(-300))
        try observeCredit(840, at: now)
        precondition(store.creditInUse && store.creditNeededText == "Estimating…")
        precondition(store.creditSpendLabel == "Observed spend" && store.creditSpentText == "10 cr")
        store.creditSpend = CreditSpendTracker()
        store.creditPace.reset()
        try observeCredit(900, at: now.addingTimeInterval(-1800))
        for index in 1...6 {
            try observeCredit(Double(900 - index * 10), at: now.addingTimeInterval(Double(index * 300 - 1800)))
        }
        precondition(store.creditInUse)
        precondition(store.creditRateText == "120 cr/h")
        precondition(store.creditRunwayText == "≈7 h")
        precondition(store.creditSpentText == "60 cr" && store.creditNeededText == "≈120 cr")
        try render("credits")
        let creditPreview = ImageRenderer(content: MeterPanel(store: store, staticPreview: true)
            .environment(\.colorScheme, .dark)
            .background(Color(red: 0.12, green: 0.12, blue: 0.12)))
        creditPreview.scale = 4
        let creditBitmap = NSBitmapImageRep(cgImage: creditPreview.cgImage!)
        try creditBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/credits-preview.png"))
        store.error = "Synthetic failure"
        precondition(!store.creditInUse && store.creditRate == nil)
        precondition(store.creditSpentText == "60 cr · Out of date" && store.creditNeededText == "Unavailable")
        store.error = nil
        store.iconOnly = true
        precondition(store.creditInUse, "Ring-only display does not change observed credit activity")
        store.iconOnly = false
        // Forecast horizon covers every exhausted window, regardless of selection.
        store.snapshot = try creditSnapshot(840, secondary: 100)
        store.observeCredits(at: now.addingTimeInterval(1))
        store.now = now.addingTimeInterval(1)
        precondition(store.creditSpend.resetDeadline(at: store.now) == Date(timeIntervalSince1970: 1_800_007_200))
        precondition((store.creditsNeededUntilReset ?? 0) > 200)
        store.selectedID = "codex/secondary"
        precondition((store.creditsNeededUntilReset ?? 0) > 200, "Display selection cannot shorten the credit horizon")
        store.snapshot = try creditSnapshot(50, secondary: 100)
        store.observeCredits(at: now.addingTimeInterval(2))
        store.now = now.addingTimeInterval(2)
        precondition((store.creditsNeededUntilReset ?? 0) > 50, "Required credits are not capped at the remaining balance")
        store.now = now
        store.snapshot = try creditSnapshot(840, used: 80)
        store.observeCredits(at: now.addingTimeInterval(3))
        precondition(!store.creditInUse && store.creditPeriod == nil, "Available quota keeps the credit balance secondary")
        precondition(store.creditSpend.previous != nil && store.creditRate == nil, "Recovery keeps the aggregate and restarts pace")
        store.snapshot = try snapshot("",
            quotaFields: #""rateLimits":{"primary":{"usedPercent":100,"resetsAt":1800003600},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(!store.creditInUse, "Unscoped credit balances cannot activate the observed-consumption cue")
        store.selectedID = "codex/primary"
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":25,"resetsAt":1800003600},"secondary":{"usedPercent":100,"resetsAt":1799999999},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        precondition(!store.resetPending && !store.creditInUse, "An unconfirmed exhausted window cannot activate credit consumption")
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":25,"resetsAt":1799999999},"secondary":{"usedPercent":100,"resetsAt":1800003600},"credits":{"hasCredits":true,"unlimited":false,"balance":"840"}}"#)
        store.observeCredits(at: now.addingTimeInterval(4))
        store.creditPace.observe(850, scope: "synthetic", at: now.addingTimeInterval(5))
        store.creditPace.observe(840, scope: "synthetic", at: now.addingTimeInterval(6))
        store.now = now.addingTimeInterval(6)
        precondition(store.resetPending && store.creditInUse, "Credit consumption is independent of an unrelated selected window")
        store.now = Date(timeIntervalSince1970: 1_800_003_600)
        store.updatedAt = store.now
        precondition(store.creditsNeededUntilReset == nil && store.creditNeededText == "Waiting for reset")
        store.snapshot = try snapshot(#", "meterCreditScope":"synthetic""#,
            quotaFields: #""rateLimits":{"primary":{"usedPercent":null},"secondary":{"usedPercent":100,"resetsAt":1800007200},"credits":{"hasCredits":true,"unlimited":false,"balance":"800"}}"#)
        store.now = now.addingTimeInterval(3601)
        store.observeCredits(at: store.now)
        precondition(store.creditNeededText == "Unavailable" && store.creditRate == nil,
                     "Unknown quota invalidates the pace used for reset forecasts")
        try observeCredit(790, at: now.addingTimeInterval(3901), reset: 1_800_007_200)
        store.now = now.addingTimeInterval(3901)
        precondition(store.creditRate == nil && store.creditNeededText == "Estimating…",
                     "A confirmed exhausted reading starts fresh pace history after unknown quota")
        print("Meter panel state and synthetic rendering tests passed")
    }
}
