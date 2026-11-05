import AppKit
import SwiftUI

let meterLocale = Locale(identifier: "en_GB")

func percentage(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return "\(Int(value.rounded()))%"
}

func postDateLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
    return date.formatted(.dateTime.locale(meterLocale).day().month(.abbreviated))
}

func remainingTime(_ reset: Double?, now: Date = Date()) -> String {
    guard let reset, reset.isFinite else { return "Reset time unavailable" }
    let seconds = reset - now.timeIntervalSince1970
    guard seconds > 0 else { return "Waiting for reset" }
    let minutes = Int(ceil(seconds / 60))
    if minutes >= 1440 {
        let hours = (minutes % 1440) / 60
        return "\(minutes / 1440) d" + (hours > 0 ? " \(hours) h" : "")
    }
    if minutes >= 60 {
        let remainder = minutes % 60
        return "\(minutes / 60) h" + (remainder > 0 ? " \(remainder) min" : "")
    }
    return "\(minutes) min"
}

func resetDate(_ timestamp: Double?) -> String? {
    guard let timestamp, timestamp.isFinite else { return nil }
    let formatter = DateFormatter()
    formatter.locale = meterLocale
    formatter.dateFormat = "d MMM, HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

func meterColor(_ value: Double?) -> Color {
    guard let value else { return .secondary }
    if value >= 95 { return .red }
    if value >= 80 { return .orange }
    return .accentColor
}

@MainActor
final class MeterStore: ObservableObject {
    let provider: MeterProvider
    let updater = ReleaseChecker()
    let login = LoginPreference()
    let announcements = ResetAnnouncements()
    @Published var snapshot: UsageSnapshot?
    @Published var updatedAt: Date?
    @Published var error: String?
    @Published var refreshing = false
    @Published var now = Date()
    @Published var selectedID: String? {
        didSet { UserDefaults.standard.set(selectedID, forKey: provider.windowPreferenceKey); onChange?() }
    }
    @Published var iconOnly = UserDefaults.standard.bool(forKey: "iconOnly") {
        didSet { UserDefaults.standard.set(iconOnly, forKey: "iconOnly"); onChange?() }
    }
    var onChange: (() -> Void)?
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var resetRequestedFor: Double?
    private let client = CodexClient()
    private let claudeFileURL: URL
    init(provider: MeterProvider = .codex, claudeFileURL: URL = ClaudeUsage.defaultFileURL) {
        self.provider = provider
        self.claudeFileURL = claudeFileURL
        selectedID = UserDefaults.standard.string(forKey: provider.windowPreferenceKey)
    }
    var creditPace = CreditPace()
    var creditBucket: RateLimitBucket? { snapshot?.buckets.first { $0.limitId == "codex" } }
    var credits: CreditBalance? { creditBucket?.credits }
    var creditBalanceText: String {
        guard let credits else { return "Unavailable" }
        let text = credits.unlimited ? "Unlimited" : credits.amount.map { creditAmount($0) } ?? "Unavailable"
        return stale && text != "Unavailable" ? text + " · Out of date" : text
    }
    var creditRate: Double? { stale || snapshot?.creditScope == nil ? nil : creditPace.perHour(at: now) }
    var creditRateText: String {
        if stale || snapshot?.creditScope == nil { return "Unavailable" }
        if let rate = creditRate { return creditAmount(rate) + " cr/h" }
        return creditPace.idle(at: now) ? "Awaiting balance updates" : "Estimating…"
    }
    var creditRunwayText: String {
        guard !stale, let amount = credits?.amount else { return "—" }
        if amount == 0 { return "Exhausted" }
        guard let rate = creditRate else { return "—" }
        let seconds = amount / rate * 3600
        guard seconds.isFinite else { return "—" }
        if seconds > 31_536_000 { return ">1 year" }
        let duration = remainingTime(now.timeIntervalSince1970 + seconds, now: now)
            .replacingOccurrences(of: " 0 min", with: "")
            .replacingOccurrences(of: " 0 h", with: "")
        return "≈" + duration
    }
    var creditInUse: Bool {
        guard !stale, snapshot?.creditScope != nil,
              let amount = credits?.amount, amount > 0, credits?.hasCredits == true,
              let bucket = creditBucket,
              [bucket.primary, bucket.secondary].compactMap({ $0 }).contains(where: {
                  ($0.usedPercent ?? 0) >= 100 && ($0.resetsAt.map { $0 > now.timeIntervalSince1970 } ?? true)
              }) else { return false }
        return creditPace.hasRecentDecrease(at: now)
    }
    var creditBalanceLabel: String { creditInUse ? "Credits in use" : "Credits available" }

    var entry: UsageEntry? {
        if let selectedID, let selected = snapshot?.windows.first(where: { $0.id == selectedID }) {
            return selected
        }
        return snapshot?.preferredEntry
    }
    var stale: Bool { error != nil || (updatedAt.map { now.timeIntervalSince($0) > 600 } ?? false) }
    var resetPending: Bool { entry?.window.resetsAt.map { $0 <= now.timeIntervalSince1970 } ?? false }
    var uncertain: Bool { stale || resetPending }
    var statusResetCount: Int? { stale ? nil : snapshot?.availableResetCount }
    var resetAvailabilityText: String {
        guard let count = snapshot?.availableResetCount else { return "Unavailable" }
        return stale ? "\(count) · Out of date" : "\(count) available"
    }

    func start() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if self.provider == .claude { self.refresh() }
                if let reset = self.entry?.window.resetsAt, reset <= self.now.timeIntervalSince1970,
                   self.resetRequestedFor != reset {
                    self.resetRequestedFor = reset
                    self.refresh()
                }
                self.onChange?()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
            name: NSWorkspace.didWakeNotification, object: nil)
    }
    @objc private func woke() { now = Date(); refresh() }
    func stop() {
        refreshTimer?.invalidate(); refreshTimer = nil
        clockTimer?.invalidate(); clockTimer = nil
        fetchTask?.cancel(); refreshing = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func observeCredits(at date: Date) {
        if let scope = snapshot?.creditScope {
            creditPace.observe(credits?.amount, scope: scope, at: date)
        } else { creditPace.reset() }
    }
    func refresh() {
        guard !refreshing else { return }
        if provider == .claude {
            do {
                let observation = try ClaudeUsage.read(fileURL: claudeFileURL)
                snapshot = observation.snapshot
                updatedAt = observation.observedAt
                error = nil
            } catch {
                // Local bridge errors never expose file contents or account data.
                self.error = "No Claude Code snapshot. Set up the bridge, then use Claude Code."
            }
            now = Date()
            onChange?()
            return
        }
        refreshing = true
        onChange?()
        fetchTask = Task {
            do {
                let data = try await client.readLimits()
                guard !Task.isCancelled else { return }
                snapshot = try UsageSnapshot(data: data)
                let receivedAt = Date()
                updatedAt = receivedAt
                error = nil
                observeCredits(at: receivedAt)
                announcements.observeResetCount(snapshot?.availableResetCount, at: receivedAt)
            } catch {
                guard !Task.isCancelled else { return }
                creditPace.reset()
                announcements.observeResetCount(nil)
                self.error = (error as? CodexClientError)?.errorDescription ?? "Could not read usage limits. Try again shortly."
            }
            now = Date()
            refreshing = false
            onChange?()
        }
    }
}

func creditAmount(_ value: Double) -> String {
    if value > 0 && value < 0.1 { return "<0.1" }
    return value.formatted(.number.locale(meterLocale).precision(.fractionLength(0...1)))
}

func quotaAmount(_ value: Double) -> String {
    if value > 0 && value < 0.1 { return "<0.1%" }
    return value.formatted(.number.locale(meterLocale).precision(.fractionLength(0...1))) + "%"
}

struct ConsumptionTrack: View {
    let used: Double?
    let elapsed: Double?
    let faded: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                if let used {
                    Capsule().fill(meterColor(used)).frame(width: geometry.size.width * used / 100)
                }
                if let elapsed {
                    Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1, height: 9)
                        .offset(x: max(0, min(geometry.size.width - 1, geometry.size.width * elapsed)))
                }
            }
        }.frame(height: 4).opacity(faded ? 0.4 : 1)
            .help(elapsed == nil ? "The bar shows used quota in the selected period." : "The bar shows usage. The marker shows how much quota you would have used at a uniform pace throughout the period.")
            .accessibilityLabel("Used \(percentage(used))")
    }
}

@MainActor
final class MeterDelegate: NSObject, NSApplicationDelegate {
    private let selection = ProviderSelection()
    private var store: MeterStore { selection.codex }
    private var statusItem: NSStatusItem!
    private lazy var panel = StatusPanel(content: AnyView(UnifiedMeterPanel(selection: selection)),
                                         anchor: { [weak self] in self?.statusItem?.button?.window })
    private var pendingPanelOpen = false
    private var openAttempts = 0
    private var appearanceObservation: StatusAppearanceObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusItem.button?.imagePosition = .imageLeading
        if let button = statusItem.button {
            appearanceObservation = StatusAppearanceObserver(button: button) { [weak self] in
                self?.updateStatus()
            }
        }
        selection.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        selection.start()
        store.updater.onChange = { [weak self] in self?.updateStatus() }
        store.updater.start()
        store.announcements.onChange = { [weak self] in self?.updateStatus() }
        store.announcements.start()
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { requestPanelOpen() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestPanelOpen()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { selection.stop(); store.updater.stop(); store.announcements.stop() }
    @objc private func togglePanel() {
        if panel.isVisible {
            pendingPanelOpen = false
            panel.hide()
        } else { requestPanelOpen() }
    }
    private func requestPanelOpen() {
        store.login.refresh()
        guard !panel.isVisible else { return }
        pendingPanelOpen = true
        openAttempts = 0
        attemptPanelOpen()
    }
    private func attemptPanelOpen() {
        guard pendingPanelOpen, let button = statusItem?.button else { return }
        // Wait for AppKit to position the status item before using screen coordinates.
        if let window = button.window, window.isVisible, window.frame.height > 0 {
            pendingPanelOpen = false
            store.now = Date()
            if selection.claudeEnabled { selection.claude.now = Date(); selection.claude.refresh() }
            if store.updatedAt.map({ Date().timeIntervalSince($0) > 180 }) ?? true { store.refresh() }
            if panel.show() { return }
            pendingPanelOpen = true
        }
        guard openAttempts < 10 else { return }
        openAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.attemptPanelOpen() }
    }
    private func updateStatus() {
        guard let button = statusItem.button else { return }
        let entry = store.entry
        let used = entry?.window.usedPercent
        button.title = store.uncertain && !store.iconOnly && entry != nil ? " !" : ""
        button.image = StatusIndicator.image(used: used, uncertain: store.uncertain,
                                 showPercentage: !store.iconOnly && (!selection.claudeEnabled || !store.uncertain), refreshing: store.refreshing,
                                 resetCount: store.statusResetCount,
                                 appearance: button.effectiveAppearance,
                                 unreadAnnouncement: store.announcements.hasUnread)
        if selection.claudeEnabled, let codexImage = button.image {
            let claude = selection.claude
            let claudeImage = StatusIndicator.image(used: claude.entry?.window.usedPercent,
                uncertain: claude.uncertain, showPercentage: !selection.iconOnly && !claude.uncertain,
                refreshing: claude.refreshing, resetCount: nil, appearance: button.effectiveAppearance)
            button.image = StatusIndicator.combined(codex: codexImage, claude: claudeImage)
            button.title = ""
        }
        button.toolTip = entry.map {
            "Codex · \($0.window.label) · \(percentage(used)) used\nReset: \(resetDate($0.window.resetsAt) ?? "unavailable")\(store.uncertain ? "\nData needs refreshing" : "")"
        } ?? "Codex Meter · usage limits unavailable"
        button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUsage limit resets: " + store.resetAvailabilityText
        if store.credits != nil {
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\n" + store.creditBalanceLabel + ": " + store.creditBalanceText
        }
        if let release = store.updater.availableRelease {
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUpdate available: " + release.version.text
        }
        if store.announcements.hasUnread {
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUnread Tibo post mentioning reset"
        }
        if selection.claudeEnabled {
            let claude = selection.claude
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\n\nClaude Code · "
                + (claude.entry?.window.label ?? "No data") + " · " + percentage(claude.entry?.window.usedPercent) + " used"
                + "\nReset: " + (resetDate(claude.entry?.window.resetsAt) ?? "unavailable")
                + (claude.uncertain ? "\nClaude data needs updating" : "")
                + "\nSource: last Claude Code capture"
        }
        button.setAccessibilityLabel(button.toolTip)
        panel.schedulePosition()
        if pendingPanelOpen { attemptPanelOpen() }
    }

}

#if !METER_TESTS
@main
struct CodexMeterApp {
    static func main() {
        if CommandLine.arguments.contains("--capture-claude-usage") {
            do { print(try ClaudeBridge.captureStandardInput()); exit(0) }
            catch { fputs("Codex Meter: could not capture Claude quota.\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--install-claude-bridge") {
            Task {
                do {
                    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
                    if let cli = ClaudeDesktopBridge.desktopCLI() {
                        try await ClaudeDesktopBridge.install(cli: cli, executable: executable)
                        print("Claude Desktop bridge enabled. Run /reload-plugins in the Code session, or open a new session.")
                    } else {
                        _ = try ClaudeBridge.install(executableURL: executable)
                        print("Claude terminal bridge ready. Open or restart Claude Code to receive quota.")
                    }
                    exit(0)
                } catch {
                    fputs(((error as? LocalizedError)?.errorDescription ?? "Could not configure Claude bridge.") + "\n", stderr)
                    exit(1)
                }
            }
            RunLoop.main.run()
        } else if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let data = try await CodexClient().readLimits()
                    let snapshot = try UsageSnapshot(data: data)
                    guard let entry = snapshot.preferredEntry else {
                        print("No usage window is available.")
                        exit(2)
                    }
                    print("OK · \(entry.bucketName) · \(entry.window.label) · \(percentage(entry.window.usedPercent)) used · reset \(resetDate(entry.window.resetsAt) ?? "unavailable")")
                    exit(0)
                } catch {
                    print("ERROR · \((error as? CodexClientError)?.errorDescription ?? "Could not read usage limits. Try again shortly.")")
                    exit(1)
                }
            }
            RunLoop.main.run()
        } else {
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                let delegate = MeterDelegate()
                app.delegate = delegate
                withExtendedLifetime(delegate) { app.run() }
            }
        }
    }
}
#endif
