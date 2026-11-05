import AppKit
import SwiftUI

/// Shared app controls; provider-specific period selection stays beside each quota.
struct MeterOptions: View {
    @ObservedObject var selection: ProviderSelection
    @ObservedObject private var updater: ReleaseChecker
    @ObservedObject private var login: LoginPreference
    @ObservedObject private var announcements: ResetAnnouncements
    var staticPreview: Bool
    @State private var settingUp = false

    init(selection: ProviderSelection, staticPreview: Bool = false) {
        self.selection = selection
        self.staticPreview = staticPreview
        updater = selection.codex.updater
        login = selection.codex.login
        announcements = selection.codex.announcements
    }

    var body: some View {
        if staticPreview {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22).accessibilityLabel("Options")
        } else {
            Menu {
                Toggle("Ring only", isOn: $selection.iconOnly)
                Toggle("Show Claude", isOn: $selection.claudeEnabled)
                if selection.claudeEnabled {
                    Button(settingUp ? "Connecting Claude…" : "Set Up Claude…") { showClaudeSetup() }
                        .disabled(settingUp)
                }
                Divider()
                Toggle("Launch at Login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if login.needsApproval {
                    Button("Approve Launch at Login…") { LoginPreference.openSettings() }
                }
                Toggle("Check Tibo’s Reset Posts", isOn: $announcements.enabled)
                    .help("Read the public RSS feed at x.noodl3.net every 30 minutes. No X login or API key.")
                if announcements.hasUnread {
                    Button("Mark Tibo Post as Read") { announcements.markRead() }
                }
                Divider()
                Toggle("Automatically Check for Updates", isOn: $updater.automaticChecks)
                if let release = updater.availableRelease {
                    Button("Install \(release.version.text)…") { updater.openRelease() }
                }
                Button(updater.checking ? "Checking for Updates…" : "Check for Updates…") { updater.check() }
                    .disabled(updater.checking)
                Button("Open Repository") { NSWorkspace.shared.open(ReleaseChecker.repository) }
                Divider()
                Text("Codex Meter \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                Button("Quit") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Options").accessibilityLabel("Options")
        }
    }

    private func showClaudeSetup() {
        guard !settingUp else { return }
        let alert = NSAlert()
        alert.messageText = "Connect Claude Code"
        alert.informativeText = "Meter installs a small local plugin when Claude Desktop is available; otherwise it connects the terminal status line. Settings are backed up. No credentials are read. Keep Meter in Applications; moving it requires setup again."
        alert.addButton(withTitle: "Enable Bridge")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, let executable = Bundle.main.executableURL else { return }
        settingUp = true
        Task { @MainActor in
            defer { settingUp = false }
            let result = NSAlert()
            do {
                if let cli = ClaudeDesktopBridge.desktopCLI() {
                    try await ClaudeDesktopBridge.install(cli: cli, executable: executable)
                    result.informativeText = "The local plugin is enabled. Run /reload-plugins in the Desktop Code session, or open a new session. The plugin receives quota updates without sending model requests."
                } else {
                    _ = try ClaudeBridge.install(executableURL: executable)
                    result.informativeText = "Open or restart Claude Code in your terminal, then use it to receive the first quota reading."
                }
                result.messageText = "Claude bridge ready"
            } catch {
                result.messageText = "Claude setup needs attention"
                result.informativeText = (error as? LocalizedError)?.errorDescription ?? "Could not update Claude Code settings. See the installation guide for manual setup."
            }
            result.runModal()
        }
    }
}
