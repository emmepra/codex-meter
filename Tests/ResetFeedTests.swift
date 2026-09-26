import Foundation

@main struct ResetFeedTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_790_424_000) // Synthetic, fixed date.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        func item(_ text: String, author: String = "@thsottiaux", id: String = "123", host: String = "x.noodl3.net", user: String = "thsottiaux", age: TimeInterval = 60) -> String {
            "<item><title><![CDATA[\(text)]]></title><dc:creator>\(author)</dc:creator><link>https://\(host)/\(user)/status/\(id)#m</link><pubDate>\(formatter.string(from: now.addingTimeInterval(-age)))</pubDate></item>"
        }
        func feed(_ items: String) -> Data {
            Data("<rss xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><channel><link>https://x.noodl3.net/thsottiaux</link>\(items)</channel></rss>".utf8)
        }
        for text in ["A reset is coming", "RESET!", "A Reset?", "#reset"] {
            let post = try ResetFeed.latest(data: feed(item(text)), now: now)
            precondition(post?.url.absoluteString == "https://x.com/thsottiaux/status/123")
        }
        for text in ["resetting", "preset", "Read https://example.com/reset", "Nothing new"] {
            let result = try ResetFeed.latest(data: feed(item(text)), now: now)
            precondition(result == nil)
        }
        for value in [item("reset", author: "@other"), item("reset", host: "evil.example"),
                      item("reset", user: "other"), item("reset", id: "123/extra"),
                      item("reset", age: 8 * 86400), item("reset", age: -3600), item("RT by @thsottiaux: reset")] {
            let result = try ResetFeed.latest(data: feed(value), now: now)
            precondition(result == nil)
        }
        let ordered = try ResetFeed.latest(data: feed(item("reset", id: "1", age: 200) + item("reset", id: "2", age: 100)), now: now)
        precondition(ordered?.id == "2")
        let empty = try ResetFeed.latest(data: feed(""), now: now)
        precondition(empty == nil)
        for data in [Data("<html>blocked</html>".utf8), Data("<rss>".utf8), Data("<!DOCTYPE rss><rss/>".utf8), Data(repeating: 32, count: ResetFeed.maximumBytes + 1)] {
            precondition((try? ResetFeed.latest(data: data, now: now)) == nil)
            do { _ = try ResetFeed.latest(data: data, now: now); fatalError("Must reject invalid RSS") } catch {}
        }
        print("Reset RSS parsing, exact-word filter, author/link validation, recency and malformed data tests passed")
    }
}
