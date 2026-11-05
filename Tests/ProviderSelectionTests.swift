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
        precondition(selection.statusBarProviders == .both && selection.effectiveStatusBarProviders == .codex)
        precondition(selection.visibleStatusProviders == [.codex], "An existing Codex-only setup must retain its status item")
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
        precondition(enabled.statusBarProviders == .both && enabled.visibleStatusProviders == [.codex, .claude],
                     "Existing Claude monitoring defaults to both counters without a new preference")

        let displaySuite = suite + ".display"
        let displayDefaults = UserDefaults(suiteName: displaySuite)!
        defer { displayDefaults.removePersistentDomain(forName: displaySuite) }
        let display = ProviderSelection(defaults: displayDefaults)
        display.start()
        display.setStatusBarProviders(.claude)
        precondition(display.claudeEnabled && display.claude.starts == 1)
        precondition(display.statusBarProviders == .claude && display.effectiveStatusBarProviders == .claude)
        precondition(display.visibleStatusProviders == [.claude])
        precondition(display.enabledProviders == [.codex, .claude], "A display choice must not remove providers from the panel")
        precondition(displayDefaults.string(forKey: "statusBarProviders") == "claude")
        let restoredClaude = ProviderSelection(defaults: displayDefaults)
        precondition(restoredClaude.claudeEnabled && restoredClaude.visibleStatusProviders == [.claude])

        display.setStatusBarProviders(.codex)
        precondition(display.visibleStatusProviders == [.codex])
        precondition(display.claudeEnabled && display.claude.stops == 0,
                     "Codex only changes the menu bar and must preserve Claude monitoring")
        precondition(display.enabledProviders == [.codex, .claude])
        display.refreshAll()
        precondition(display.codex.refreshes == 1 && display.claude.refreshes == 1,
                     "A hidden Claude counter must keep receiving updates")
        let restoredCodex = ProviderSelection(defaults: displayDefaults)
        precondition(restoredCodex.statusBarProviders == .codex && restoredCodex.visibleStatusProviders == [.codex])
        precondition(restoredCodex.claudeEnabled)

        display.setStatusBarProviders(.both)
        precondition(display.visibleStatusProviders == [.codex, .claude])
        let restoredBoth = ProviderSelection(defaults: displayDefaults)
        precondition(restoredBoth.statusBarProviders == .both && restoredBoth.visibleStatusProviders == [.codex, .claude])
        display.claudeEnabled = false
        precondition(display.statusBarProviders == .both && display.effectiveStatusBarProviders == .codex)
        precondition(display.visibleStatusProviders == [.codex])
        display.setStatusBarProviders(.both)
        precondition(display.claudeEnabled && display.visibleStatusProviders == [.codex, .claude],
                     "Choosing both must enable Claude monitoring")

        display.setStatusBarProviders(.claude)
        display.claudeEnabled = false
        precondition(display.statusBarProviders == .claude && display.visibleStatusProviders == [.codex],
                     "Disabling Claude must fall back to a visible Codex counter")
        let restoredDisabled = ProviderSelection(defaults: displayDefaults)
        precondition(!restoredDisabled.claudeEnabled && restoredDisabled.statusBarProviders == .claude)
        precondition(restoredDisabled.effectiveStatusBarProviders == .codex && restoredDisabled.visibleStatusProviders == [.codex])
        restoredDisabled.claudeEnabled = true
        precondition(restoredDisabled.visibleStatusProviders == [.claude], "Re-enabling monitoring restores the saved display choice")
        display.setStatusBarProviders(.codex)
        precondition(!display.claudeEnabled && display.visibleStatusProviders == [.codex])
        display.stop()

        displayDefaults.set(false, forKey: "claudeEnabled")
        displayDefaults.set("invalid", forKey: "statusBarProviders")
        let invalidPreference = ProviderSelection(defaults: displayDefaults)
        precondition(invalidPreference.statusBarProviders == .both && invalidPreference.visibleStatusProviders == [.codex])
        print("Provider selection tests passed")
    }
}
