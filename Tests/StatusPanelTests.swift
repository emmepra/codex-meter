import AppKit
import SwiftUI

@MainActor
private final class LayoutModel: ObservableObject {
    @Published var height: CGFloat = 107
}

private struct TestContent: View {
    @ObservedObject var model: LayoutModel
    var body: some View {
        Text("Codex Meter layout check")
            .frame(width: 270, height: model.height)
    }
}

@MainActor
private final class TestDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panel: StatusPanel!
    private let model = LayoutModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Layout check"
        panel = StatusPanel(content: AnyView(TestContent(model: model)),
                            anchor: { [weak self] in self?.item.button?.window })
        Task { await runChecks() }
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func require(_ value: Bool, _ message: String) {
        guard value else {
            print("FAIL: \(message)")
            panel.hide()
            NSStatusBar.system.removeStatusItem(item)
            exit(1)
        }
    }

    private func geometryMatches(height: CGFloat) -> Bool {
        guard panel.isVisible, let anchor = item.button?.window, anchor.isVisible,
              let screen = anchor.screen else { return false }
        let frame = panel.frame
        let anchorFrame = anchor.frame
        let expected = PanelPlacement.frame(anchor: anchorFrame,
            size: NSSize(width: 270, height: height), screen: screen.frame)
        return abs(frame.maxY - anchorFrame.minY) < 0.01
            && abs(frame.height - height) < 0.01
            && abs(frame.width - 270) < 0.01
            && screen.frame.contains(frame)
            && abs(frame.midX - expected.midX) <= 0.5
    }

    private func checkPosition(height: CGFloat) {
        require(panel.isVisible, "panel must remain visible")
        guard let anchor = item.button?.window, let screen = anchor.screen else {
            require(false, "status item must retain an anchor display")
            return
        }
        require(anchor.isVisible, "status item must remain visible")
        let frame = panel.frame
        let anchorFrame = anchor.frame
        let expected = PanelPlacement.frame(anchor: anchorFrame,
            size: NSSize(width: 270, height: height), screen: screen.frame)
        require(abs(frame.maxY - anchorFrame.minY) < 0.01,
                "panel top must touch menu bar: panel=\(frame), anchor=\(anchorFrame)")
        require(abs(frame.height - height) < 0.01,
                "content height must update: expected \(height), got \(frame.height)")
        require(abs(frame.width - 270) < 0.01, "panel width must stay compact")
        require(screen.frame.contains(frame), "panel must stay on anchor display")
        require(abs(frame.midX - expected.midX) <= 0.5, "panel must align with the status item")
        print("PASS: native panel height \(Int(height)), menu bar gap 0 pt")
    }

    private func runChecks() async {
        let anchorReady = await waitUntil {
            self.item.button?.window.map { $0.isVisible && $0.frame.height > 0 && $0.screen != nil } ?? false
        }
        require(anchorReady, "status item must be visible in an interactive macOS session")
        let opened = await waitUntil { self.panel.show() }
        require(opened, "panel must open")
        let initial = await waitUntil { self.geometryMatches(height: 107) }
        require(initial, "initial content must lay out at the menu bar")
        checkPosition(height: 107)

        // Exercise the production hosting view's automatic layout callback. No
        // manual position request after changing SwiftUI's content height.
        model.height = 230
        // SwiftUI content sizing and the system-hosted anchor can settle in
        // separate passes. Height alone is not sufficient to assert placement.
        let grew = await waitUntil { self.geometryMatches(height: 230) }
        require(grew, "panel must grow and settle at the menu bar: frame=\(panel.frame), visible=\(panel.isVisible)")
        checkPosition(height: 230)
        model.height = 140.5
        let shrank = await waitUntil { self.geometryMatches(height: 141) }
        require(shrank, "panel must shrink when content changes: frame=\(panel.frame), visible=\(panel.isVisible)")
        checkPosition(height: 141)

        // A menu bar preference changes the anchor width while the panel is open.
        let previousAnchor = item.button!.window!.frame
        item.button?.title = "◉"
        let followed = await waitUntil {
            guard let anchor = self.item.button?.window else { return false }
            guard anchor.frame != previousAnchor else { return false }
            return self.geometryMatches(height: 141)
        }
        require(followed, "panel must follow status item movement")
        checkPosition(height: 141)
        panel.hide()
        require(!panel.isVisible, "panel must hide")
        require(panel.show(), "panel must reopen")
        let reopened = await waitUntil { self.geometryMatches(height: 141) }
        require(reopened, "reopened panel must settle at the menu bar")
        checkPosition(height: 141)
        panel.hide()
        NSStatusBar.system.removeStatusItem(item)
        print("Status panel integration tests passed")
        NSApplication.shared.terminate(nil)
    }
}

@main
struct StatusPanelTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = TestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
