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
        print("Unread reset posts: persistence, new/old IDs, expiry and disable passed")
    }
}
