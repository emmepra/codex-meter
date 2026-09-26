import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class LoginPreference: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    var enabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "Keep Codex Meter in Applications and check its permission in System Settings → General → Login Items."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Login Items")
            if alert.runModal() == .alertSecondButtonReturn { Self.openSettings() }
        }
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
