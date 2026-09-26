import AppKit
import Foundation
import SwiftUI

struct ResetAnnouncement: Equatable {
    let id: String
    let text: String
    let date: Date
    var url: URL { URL(string: "https://x.com/thsottiaux/status/\(id)")! }
}

struct ResetFeed {
    static let endpoint = URL(string: "https://x.noodl3.net/thsottiaux/rss")!
    static let maximumAge: TimeInterval = 7 * 86_400
    static let maximumBytes = 262_144

    static func latest(data: Data, now: Date = Date()) throws -> ResetAnnouncement? {
        guard data.count <= maximumBytes, let xml = String(data: data, encoding: .utf8),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else { throw URLError(.cannotParseResponse) }
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.channelLink == "https://x.noodl3.net/thsottiaux" else {
            throw URLError(.cannotParseResponse)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return reader.items.compactMap { item -> ResetAnnouncement? in
            guard item["dc:creator"]?.lowercased() == "@thsottiaux",
                  let text = item["title"], text.count <= 10_000,
                  !text.hasPrefix("RT by "),
                  let link = item["link"], let url = URLComponents(string: link),
                  url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
                  ["x.noodl3.net", "x.com", "twitter.com"].contains(url.host?.lowercased() ?? ""),
                  let rawDate = item["pubDate"], let date = formatter.date(from: rawDate),
                  date <= now.addingTimeInterval(300), now.timeIntervalSince(date) <= maximumAge else { return nil }
            let parts = url.path.split(separator: "/")
            guard parts.count == 3, parts[0].lowercased() == "thsottiaux", parts[1] == "status",
                  (1...25).contains(parts[2].count), parts[2].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            let words = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            guard words.range(of: "\\breset\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
            return ResetAnnouncement(id: String(parts[2]), text: text, date: date)
        }.max { $0.date < $1.date }
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var items: [[String: String]] = []
        var channelLink = ""
        private var path: [String] = []
        private var item: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            path.append(elementName)
            if path == ["rss", "channel", "item"] { item = [:] }
            if path.count > 16 || items.count > 1000 { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) { append(text) }
        }
        private func append(_ text: String) {
            if path == ["rss", "channel", "link"] { channelLink += text }
            if path.count == 4, Array(path.prefix(3)) == ["rss", "channel", "item"],
               let field = path.last, ["title", "link", "dc:creator", "pubDate"].contains(field) {
                item[field, default: ""] += text
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if path == ["rss", "channel", "item"] {
                items.append(item.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            }
            if path == ["rss", "channel", "link"] { channelLink = channelLink.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !path.isEmpty { path.removeLast() }
        }
    }
}

@MainActor
final class ResetAnnouncements: ObservableObject {
    @Published private(set) var latest: ResetAnnouncement? {
        didSet {
            if latest?.id != oldValue?.id { resetObservation = nil }
            onChange?()
        }
    }
    private var resetObservation: (postID: String, count: Int, date: Date)?

    /// A later increase only acknowledges the notice; it does not establish causation.
    /// Missing data, failed reads, or gaps longer than the quota freshness window break the comparison.
    func observeResetCount(_ count: Int?, at date: Date = Date()) {
        guard hasUnread, let post = latest, let count, count >= 0, date >= post.date else {
            resetObservation = nil
            return
        }
        defer { resetObservation = (post.id, count, date) }
        guard let previous = resetObservation, previous.postID == post.id,
              date > previous.date, date.timeIntervalSince(previous.date) <= 600 else { return }
        if count > previous.count { markRead() }
    }
    @Published private(set) var lastReadID: String?
    var onChange: (() -> Void)?
    private let preferences: UserDefaults
    var hasUnread: Bool {
        guard enabled, let latest, Date().timeIntervalSince(latest.date) <= ResetFeed.maximumAge else { return false }
        guard let lastReadID else { return true }
        return latest.id.count == lastReadID.count ? latest.id > lastReadID : latest.id.count > lastReadID.count
    }
    init(preferences: UserDefaults = .standard, latest: ResetAnnouncement? = nil) {
        self.preferences = preferences
        self.latest = latest
        lastReadID = preferences.string(forKey: "lastReadTiboPostID")
        enabled = preferences.object(forKey: "resetAnnouncements") as? Bool ?? true
    }
    func markRead() {
        guard hasUnread, let latest else { return }
        lastReadID = latest.id
        preferences.set(latest.id, forKey: "lastReadTiboPostID")
        onChange?()
    }
    func openLatest() {
        guard let latest else { return }
        if NSWorkspace.shared.open(latest.url) { markRead() }
    }
    @Published private(set) var unavailable = false
    @Published var enabled: Bool {
        didSet {
            preferences.set(enabled, forKey: "resetAnnouncements")
            if enabled { refresh() }
            else { cancel(); latest = nil; unavailable = false }
        }
    }
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID = 0
    private var lastAttempt: Date?

    func start() {
        guard timer == nil else { return }
        refreshIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshIfDue),
            name: NSWorkspace.didWakeNotification, object: nil)
    }
    func stop() { timer?.invalidate(); timer = nil; cancel(); NSWorkspace.shared.notificationCenter.removeObserver(self) }
    private func cancel() { requestID += 1; task?.cancel(); task = nil }
    @objc private func refreshIfDue() {
        guard lastAttempt.map({ Date().timeIntervalSince($0) >= 1800 }) ?? true else { return }
        refresh()
    }
    func refresh() {
        guard enabled, task == nil else { return }
        lastAttempt = Date()
        requestID += 1
        let id = requestID
        task = Task {
            defer { if requestID == id { task = nil } }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.timeoutIntervalForResource = 20
                let session = URLSession(configuration: configuration, delegate: ReleaseRedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: ResetFeed.endpoint)
                request.timeoutInterval = 15
                request.setValue("application/rss+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url == ResetFeed.endpoint,
                      response.expectedContentLength <= ResetFeed.maximumBytes else { throw URLError(.badServerResponse) }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < ResetFeed.maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                try Task.checkCancellation()
                guard enabled else { return }
                latest = try ResetFeed.latest(data: data)
                unavailable = false
            } catch {
                guard !Task.isCancelled, enabled else { return }
                unavailable = true
                if let latest, Date().timeIntervalSince(latest.date) > ResetFeed.maximumAge { self.latest = nil }
            }
        }
    }
}
