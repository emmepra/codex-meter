import AppKit
import SwiftUI

@MainActor
final class ReleaseChecker: ObservableObject {
    static let repository = ReleaseInfo.repository
    @Published private(set) var checking = false

    func check() {
        guard !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
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
                let release = try ReleaseInfo(data: data, response: response)
                guard let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      let installedVersion = ReleaseVersion(installed) else { throw URLError(.cannotParseResponse) }
                let latest = release.version.text
                let available = release.version > installedVersion
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
}
