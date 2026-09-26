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
        SparkleInstaller.shared.check()
    }

    func check(automatically: Bool = false) {
        if !automatically { SparkleInstaller.shared.check(); return }
        guard !checking else { return }
        checking = true
        lastAttempt = Date()
        task = Task {
            defer { checking = false }
            do {
                let release = try await fetch()
                try Task.checkCancellation()
                guard let installed, let installedVersion = ReleaseVersion(installed) else { throw URLError(.cannotParseResponse) }
                let available = release.version > installedVersion
                availableRelease = available ? release : nil
                onChange?()
            } catch {
                // Background availability failures stay quiet and retain the last known release.
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
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == ReleaseInfo.endpoint,
              response.expectedContentLength <= ReleaseInfo.maximumBytes else { throw URLError(.badServerResponse) }
        let data = try await ReleaseInfo.readBody(bytes)
        try Task.checkCancellation()
        return try ReleaseInfo(data: data, response: response)
    }

}
