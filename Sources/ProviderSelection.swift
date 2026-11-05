import Combine
import Foundation

enum MeterProvider: String, CaseIterable {
    case codex
    case claude

    var title: String { self == .codex ? "Codex" : "Claude" }
    var windowPreferenceKey: String { self == .codex ? "selectedWindow" : "claudeSelectedWindow" }
}

/// Owns provider selection and shared display preferences; usage stays in each store.
@MainActor
final class ProviderSelection: ObservableObject {
    let codex: MeterStore
    let claude: MeterStore
    private let defaults: UserDefaults
    private var started = false
    var onChange: (() -> Void)?

    @Published var claudeEnabled: Bool {
        didSet {
            defaults.set(claudeEnabled, forKey: "claudeEnabled")
            if !claudeEnabled, selectedProvider == .claude { selectedProvider = .codex }
            if started, oldValue != claudeEnabled {
                if claudeEnabled { claude.start() } else { claude.stop() }
            }
            onChange?()
        }
    }

    @Published var selectedProvider: MeterProvider {
        didSet {
            if selectedProvider == .claude, !claudeEnabled { selectedProvider = .codex }
            defaults.set(selectedProvider.rawValue, forKey: "selectedProvider")
            onChange?()
        }
    }

    @Published var iconOnly: Bool {
        didSet {
            defaults.set(iconOnly, forKey: "iconOnly")
            if codex.iconOnly != iconOnly { codex.iconOnly = iconOnly }
            if claude.iconOnly != iconOnly { claude.iconOnly = iconOnly }
            onChange?()
        }
    }

    var activeStore: MeterStore { selectedProvider == .claude && claudeEnabled ? claude : codex }
    var enabledProviders: [MeterProvider] { claudeEnabled ? [.codex, .claude] : [.codex] }

    init(codex: MeterStore? = nil, claude: MeterStore? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.codex = codex ?? MeterStore(provider: .codex)
        self.claude = claude ?? MeterStore(provider: .claude)
        let enabled = defaults.bool(forKey: "claudeEnabled")
        claudeEnabled = enabled
        let savedProvider = defaults.string(forKey: "selectedProvider").flatMap(MeterProvider.init(rawValue:)) ?? .codex
        selectedProvider = savedProvider == .claude && !enabled ? .codex : savedProvider
        iconOnly = defaults.bool(forKey: "iconOnly")
        self.codex.iconOnly = iconOnly
        self.claude.iconOnly = iconOnly
        self.codex.onChange = { [weak self] in self?.storeChanged(.codex) }
        self.claude.onChange = { [weak self] in self?.storeChanged(.claude) }
    }

    func start() {
        guard !started else { return }
        started = true
        codex.start()
        if claudeEnabled { claude.start() }
    }

    func stop() {
        guard started else { return }
        started = false
        codex.stop()
        claude.stop()
    }

    func refreshAll() {
        codex.refresh()
        if claudeEnabled { claude.refresh() }
    }

    private func storeChanged(_ provider: MeterProvider) {
        let store = provider == .codex ? codex : claude
        // Existing detail-panel toggles still write the store's display preference.
        if store.iconOnly != iconOnly { iconOnly = store.iconOnly }
        objectWillChange.send()
        onChange?()
    }
}
