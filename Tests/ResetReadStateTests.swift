import Foundation
@main struct ResetReadStateTests {
    @MainActor static func main() {
        let name = "ResetReadStateTests.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: name)!
        defer { prefs.removePersistentDomain(forName: name) }
        func post(_ id: String, age: TimeInterval = 0) -> ResetAnnouncement {
            ResetAnnouncement(id: id, text: "Synthetic reset", date: Date().addingTimeInterval(-age))
        }
        let first = ResetAnnouncements(preferences: prefs, latest: post("100"))
        precondition(first.hasUnread)
        first.markRead()
        precondition(!first.hasUnread)
        let reopened = ResetAnnouncements(preferences: prefs, latest: post("100"))
        precondition(!reopened.hasUnread)
        let newer = ResetAnnouncements(preferences: prefs, latest: post("101"))
        precondition(newer.hasUnread)
        let older = ResetAnnouncements(preferences: prefs, latest: post("99"))
        precondition(!older.hasUnread)
        let expired = ResetAnnouncements(preferences: prefs, latest: post("102", age: 8 * 86400))
        precondition(!expired.hasUnread)
        newer.enabled = false
        precondition(!newer.hasUnread)
        prefs.set(true, forKey: "resetAnnouncements")
        // Each case starts unread and uses synthetic successful quota samples.
        func monitor(_ id: String) -> ResetAnnouncements {
            ResetAnnouncements(preferences: prefs, latest: post(id, age: 60))
        }
        let now = Date()
        let increased = monitor("200")
        increased.observeResetCount(0, at: now)
        precondition(increased.hasUnread)
        increased.observeResetCount(1, at: now.addingTimeInterval(180))
        precondition(!increased.hasUnread)
        precondition(increased.latest?.id == "200", "Acknowledgement keeps the link")
        let firstPositive = monitor("201")
        firstPositive.observeResetCount(3, at: now)
        firstPositive.observeResetCount(3, at: now.addingTimeInterval(180))
        precondition(firstPositive.hasUnread, "Existing availability proves nothing")
        firstPositive.observeResetCount(2, at: now.addingTimeInterval(360))
        precondition(firstPositive.hasUnread, "Consumption must not acknowledge a post")
        let missing = monitor("202")
        missing.observeResetCount(0, at: now)
        missing.observeResetCount(nil, at: now.addingTimeInterval(100))
        missing.observeResetCount(1, at: now.addingTimeInterval(180))
        precondition(missing.hasUnread, "Missing or failed reads break the comparison")
        let gap = monitor("203")
        gap.observeResetCount(0, at: now)
        gap.observeResetCount(1, at: now.addingTimeInterval(601))
        precondition(gap.hasUnread, "Stale observations must not acknowledge a post")
        let sameTime = monitor("204")
        sameTime.observeResetCount(0, at: now)
        sameTime.observeResetCount(1, at: now)
        precondition(sameTime.hasUnread)
        let afterRestart = monitor("205")
        afterRestart.observeResetCount(4, at: now)
        precondition(afterRestart.hasUnread, "No persisted quota baseline after restart")
        print("Unread reset posts: persistence, IDs, expiry, disable and conservative reset-count acknowledgement passed")
    }
}
