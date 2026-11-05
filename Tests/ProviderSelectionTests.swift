import Combine
import Foundation

// Compile with ProviderSelection.swift alone so lifecycle tests never launch a CLI.
@MainActor
final class MeterStore: ObservableObject {
    let provider: MeterProvider
    var iconOnly = false { didSet { onChange?() } }
    var onChange: (() -> Void)?
    var starts = 0
    var stops = 0
    var refreshes = 0
    init(provider: MeterProvider = .codex) { self.provider = provider }
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func refresh() { refreshes += 1 }
}

@main
enum ProviderSelectionTests {
    @MainActor static func main() {
        let suite = "ProviderSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = ProviderSelection(defaults: defaults)
        precondition(!selection.claudeEnabled && selection.selectedProvider == .codex)
        precondition(selection.activeStore === selection.codex)
        precondition(MeterProvider.codex.windowPreferenceKey == "selectedWindow")
        precondition(MeterProvider.claude.windowPreferenceKey != MeterProvider.codex.windowPreferenceKey)
        selection.selectedProvider = .claude
        precondition(selection.selectedProvider == .codex, "Disabled providers cannot be selected")

        selection.start()
        selection.start()
        precondition(selection.codex.starts == 1 && selection.claude.starts == 0)
        selection.refreshAll()
        precondition(selection.codex.refreshes == 1 && selection.claude.refreshes == 0)
        selection.claudeEnabled = true
        precondition(selection.claude.starts == 1)
        selection.selectedProvider = .claude
        precondition(selection.activeStore === selection.claude)
        precondition(defaults.string(forKey: "selectedProvider") == "claude")
        selection.refreshAll()
        precondition(selection.codex.refreshes == 2 && selection.claude.refreshes == 1)

        var forwarded = 0
        selection.onChange = { forwarded += 1 }
        selection.claude.onChange?()
        precondition(forwarded == 1, "Usage changes must redraw the unified status item")
        selection.codex.iconOnly = true
        precondition(selection.iconOnly && selection.claude.iconOnly)
        selection.claude.iconOnly = false
        precondition(!selection.iconOnly && !selection.codex.iconOnly)
        precondition(!defaults.bool(forKey: "iconOnly"))

        selection.claudeEnabled = false
        precondition(selection.claude.stops == 1 && selection.selectedProvider == .codex)
        selection.claudeEnabled = true
        precondition(selection.claude.starts == 2)
        selection.stop()
        selection.stop()
        precondition(selection.codex.stops == 1 && selection.claude.stops == 2)

        defaults.set(false, forKey: "claudeEnabled")
        defaults.set("claude", forKey: "selectedProvider")
        let restored = ProviderSelection(defaults: defaults)
        precondition(restored.selectedProvider == .codex && restored.activeStore === restored.codex)
        defaults.set(true, forKey: "claudeEnabled")
        let enabled = ProviderSelection(defaults: defaults)
        precondition(enabled.selectedProvider == .claude && enabled.activeStore === enabled.claude)
        print("Provider selection tests passed")
    }
}
