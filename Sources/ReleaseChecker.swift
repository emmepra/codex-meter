import AppKit
import SwiftUI

@MainActor
final class ReleaseChecker: ObservableObject {
    static let repository = ReleaseInfo.repository
    @Published private(set) var checking = false
    @Published private(set) var availableRelease: ReleaseInfo?
    @Published var automaticChecks: Bool {
        didSet {
            preferences.set(automaticChecks, forKey: "automaticUpdateChecks")
            if automaticChecks { check(automatically: true) }
        }
    }
    private let preferences: UserDefaults
    private let installed: String?
    private let fetch: () async throws -> ReleaseInfo

    init(preferences: UserDefaults = .standard,
         installed: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
         fetch: @escaping () async throws -> ReleaseInfo = ReleaseChecker.fetchLatest) {
        self.preferences = preferences
        self.installed = installed
        self.fetch = fetch
        automaticChecks = preferences.object(forKey: "automaticUpdateChecks") as? Bool ?? true
    }

    var onChange: (() -> Void)?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var lastAttempt: Date?
    private var presentResult = false

    func start() {
        guard timer == nil else { return }
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkIfDue),
            name: NSWorkspace.didWakeNotification, object: nil)
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    @objc private func checkIfDue() {
        guard automaticChecks, lastAttempt.map({ Date().timeIntervalSince($0) >= 6 * 3600 }) ?? true else { return }
        check(automatically: true)
    }
    func openRelease() {
        guard let availableRelease else { return }
        NSWorkspace.shared.open(availableRelease.url)
    }

    func check(automatically: Bool = false) {
        if !automatically { presentResult = true }
        guard !checking else { return }
        checking = true
        lastAttempt = Date()
        task = Task {
            defer { checking = false; presentResult = false }
            do {
                let release = try await fetch()
                try Task.checkCancellation()
                guard let installed, let installedVersion = ReleaseVersion(installed) else { throw URLError(.cannotParseResponse) }
                let latest = release.version.text
                let available = release.version > installedVersion
                availableRelease = available ? release : nil
                onChange?()
                guard presentResult else { return }
                let alert = NSAlert()
                alert.icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
                alert.messageText = available ? "Codex Meter \(latest) is available" : "You’re up to date"
                alert.informativeText = available
                    ? "Installed: \(installed). Open the release page to download the update and read the installation instructions."
                    : "Installed: \(installed). Latest release: \(latest)."
                alert.addButton(withTitle: available ? "Open Release" : "OK")
                if available { alert.addButton(withTitle: "Later") }
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn && available {
                    NSWorkspace.shared.open(release.url)
                }
            } catch {
                guard !Task.isCancelled, presentResult else { return }
                let alert = NSAlert()
                alert.icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
                alert.messageText = "Could not check for updates"
                alert.informativeText = "Check your internet connection and try again. You can also view releases on GitHub."
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "View Releases")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(Self.repository.appendingPathComponent("releases"))
                }
            }
        }
    }
    nonisolated private static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: ReleaseInfo.endpoint)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration, delegate: ReleaseRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        return try ReleaseInfo(data: data, response: response)
    }

}
