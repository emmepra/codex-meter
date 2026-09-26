import AppKit
import SwiftUI

private let meterLocale = Locale(identifier: "en_GB")

func percentage(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return "\(Int(value.rounded()))%"
}

func remainingTime(_ reset: Double?, now: Date = Date()) -> String {
    guard let reset, reset.isFinite else { return "Reset time unavailable" }
    let seconds = reset - now.timeIntervalSince1970
    guard seconds > 0 else { return "Waiting for reset" }
    let minutes = Int(ceil(seconds / 60))
    if minutes >= 1440 { return "\(minutes / 1440) d \((minutes % 1440) / 60) h" }
    if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
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
    let updater = ReleaseChecker()
    let login = LoginPreference()
    let announcements = ResetAnnouncements()
    @Published var snapshot: UsageSnapshot?
    @Published var updatedAt: Date?
    @Published var error: String?
    @Published var refreshing = false
    @Published var now = Date()
    @Published var selectedID = UserDefaults.standard.string(forKey: "selectedWindow") {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedWindow"); onChange?() }
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
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
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
    func stop() { refreshTimer?.invalidate(); clockTimer?.invalidate(); fetchTask?.cancel() }
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        onChange?()
        fetchTask = Task {
            do {
                let data = try await client.readLimits()
                guard !Task.isCancelled else { return }
                snapshot = try UsageSnapshot(data: data)
                updatedAt = Date()
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? CodexClientError)?.errorDescription ?? "Could not read usage limits. Try again shortly."
            }
            now = Date()
            refreshing = false
            onChange?()
        }
    }
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
            .help("The bar shows usage. The marker shows how much quota you would have used at a uniform pace throughout the period.")
            .accessibilityLabel("Used \(percentage(used))")
    }
}

struct MeterPanel: View {
    @ObservedObject var store: MeterStore
    @ObservedObject private var updater: ReleaseChecker
    @ObservedObject private var login: LoginPreference
    @ObservedObject private var announcements: ResetAnnouncements

    init(store: MeterStore) {
        self.store = store
        updater = store.updater
        login = store.login
        announcements = store.announcements
    }
    private var budget: ComputeBudget? {
        guard !store.uncertain, let window = store.entry?.window else { return nil }
        return ComputeBudget(window: window, now: store.now)
    }
    private var daily: Bool { (budget?.remainingSeconds ?? 0) >= 86_400 }
    private var resetAvailabilityColor: Color {
        guard let count = store.snapshot?.availableResetCount else { return .secondary }
        if store.stale { return .orange }
        return Color(nsColor: count > 1 ? .systemGreen : .systemRed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(nsImage: Bundle.main.url(forResource: "OpenAI", withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 16, height: 16))).renderingMode(.template)
                    .resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityLabel("OpenAI")
                Text("Codex Meter").font(.system(size: 11, weight: .semibold))
                if let entry = store.entry {
                    Text(entry.bucketId == "codex" ? entry.window.label : entry.bucketName)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if store.refreshing { ProgressView().controlSize(.mini) }
                Menu {
                    Toggle("Ring only", isOn: $store.iconOnly)
                    Toggle("Launch at Login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                    if login.needsApproval {
                        Button("Approve Launch at Login…") { LoginPreference.openSettings() }
                    }
                    if let windows = store.snapshot?.windows, windows.count > 1 {
                        Divider()
                        ForEach(windows) { entry in
                            Button {
                                store.selectedID = entry.id
                            } label: {
                                if store.entry?.id == entry.id {
                                    Label("\(entry.bucketName) · \(entry.window.label)", systemImage: "checkmark")
                                } else { Text("\(entry.bucketName) · \(entry.window.label)") }
                            }
                        }
                    }
                    Divider()
                    Button("Refresh") { store.refresh() }.disabled(store.refreshing)
                    Divider()
                    Text("Codex Meter \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    if announcements.hasUnread {
                        Button("Mark Tibo Post as Read") { announcements.markRead() }
                    }
                    Toggle("Check Tibo’s Reset Posts", isOn: $announcements.enabled)
                        .help("Read the public RSS feed at x.noodl3.net every 30 minutes. No X login or API key.")
                    Toggle("Automatically Check for Updates", isOn: $updater.automaticChecks)
                    if let release = updater.availableRelease {
                        Button("Update to \(release.version.text)…") { updater.openRelease() }
                    }
                    Button(updater.checking ? "Checking for Updates…" : "Check for Updates…") { updater.check() }
                        .disabled(updater.checking)
                    Button("Open Repository") { NSWorkspace.shared.open(ReleaseChecker.repository) }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium))
                        .frame(width: 18, height: 14).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Options")
                    .accessibilityLabel("Options")
            }

            if let entry = store.entry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(percentage(entry.window.usedPercent.map { 100 - $0 }))
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("remaining").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(percentage(entry.window.usedPercent)) used")
                            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }.opacity(store.uncertain ? 0.55 : 1)
                    ConsumptionTrack(used: entry.window.usedPercent, elapsed: budget?.elapsedFraction, faded: store.uncertain)
                    HStack(spacing: 3) {
                        Text(entry.window.resetsAt == nil ? "Reset time unavailable" : (store.resetPending ? "Reset unconfirmed" : "Resets in \(remainingTime(entry.window.resetsAt, now: store.now))"))
                        Spacer(minLength: 2)
                        if let date = resetDate(entry.window.resetsAt) { Text(date).foregroundStyle(.secondary) }
                    }.font(.system(size: 10)).lineLimit(1)
                }
                if let budget {
                    Divider()
                    VStack(spacing: 7) {
                        stat(daily ? "Daily budget" : "Hourly budget",
                             quotaAmount(daily ? budget.budgetPerDay : budget.budgetPerHour),
                             prominent: true)
                            .help("Remaining quota divided by time until reset. Percentage points of the total quota available every \(daily ? "24 hours" : "hour"), starting now.")
                        if let endOfDay = Calendar.current.dateInterval(of: .day, for: store.now)?.end,
                           endOfDay.timeIntervalSince(store.now) < budget.remainingSeconds {
                            let todayBudget = budget.remainingPercent * endOfDay.timeIntervalSince(store.now) / budget.remainingSeconds
                            stat("Today, from now", quotaAmount(todayBudget))
                                .help("Quota available from now until midnight at the budgeted pace.")
                        }
                        stat(daily ? "Average / day" : "Average / hour",
                             budget.averagePerDay.map { quotaAmount(daily ? $0 : $0 / 24) } ?? "—")
                            .help("Estimated average since the start of the period: usage divided by elapsed time. The start is inferred from the reset and duration; this is not a record of daily usage.")
                        if budget.remainingPercent == 0 {
                            stat("Quota used up", "Wait for reset", warning: true)
                        } else if let exhaustion = budget.projectedExhaustion,
                                  exhaustion.timeIntervalSince(store.now) < budget.remainingSeconds {
                            stat("Runway at this pace", remainingTime(exhaustion.timeIntervalSince1970, now: store.now), warning: true)
                                .help("Estimate at the average pace since the start of the period. Future usage may change.")
                        } else if let remaining = budget.projectedRemainingAtReset {
                            stat("Projected at reset", "\(quotaAmount(remaining)) remaining")
                                .help("Quota that would remain at reset if you kept the average pace since the start of the period.")
                        } else {
                            stat("Pace estimate", "Not enough data")
                        }
                    }
                } else if !store.uncertain {
                    Divider()
                    Text("Stats require known quota and reset time.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Text(store.refreshing ? "Reading usage limits…" : "Usage limits unavailable")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            }

            Divider()
            stat("Usage limit resets", store.resetAvailabilityText,
                 valueColor: resetAvailabilityColor)
                .help("Banked resets for the Codex CLI account. A fresh count above one is green; one or zero is red. Out-of-date counts stay orange. Availability does not mean a quota window is eligible. Redeem resets in Codex.")

            if announcements.enabled {
                if let post = announcements.latest,
                   store.now.timeIntervalSince(post.date) <= ResetFeed.maximumAge {
                    Button { announcements.openLatest() } label: {
                        HStack(spacing: 4) {
                            if announcements.hasUnread { Circle().fill(Color.orange).frame(width: 4, height: 4) }
                            Text("Tibo · “reset”")
                            if announcements.unavailable { Text("· cached").foregroundStyle(.secondary) }
                            Spacer(minLength: 2)
                            Text(post.date.formatted(.dateTime.locale(meterLocale).day().month(.abbreviated)))
                            Image(systemName: "arrow.up.right").font(.system(size: 8))
                        }.font(.system(size: 10)).foregroundStyle(.primary)
                    }.buttonStyle(.plain).help("\(post.text.prefix(500))\nVia x.noodl3.net · Keyword match, not confirmation of an account reset.")
                } else if announcements.unavailable {
                    Text("Tibo posts unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
                        .help("The public RSS source x.noodl3.net could not be refreshed. Quota data is unaffected.")
                }
            }

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if store.uncertain {
                Text(store.resetPending ? "Reset unconfirmed. Stats paused." : "Data is out of date. Stats paused.")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack {
                Link(destination: ReleaseChecker.repository) {
                    HStack(spacing: 5) {
                        Text("Codex Meter").font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.primary)
                }.help("Codex Meter on GitHub")
                Spacer(minLength: 3)
                if let date = store.updatedAt { Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(meterLocale))) }
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 14, height: 14)
                }.buttonStyle(.plain).disabled(store.refreshing).help("Refresh now").accessibilityLabel("Refresh now")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(14).frame(width: 270).environment(\.locale, meterLocale)
    }
    private func stat(_ label: String, _ value: String, prominent: Bool = false, warning: Bool = false,
                      valueColor: Color? = nil) -> some View {
        let color = warning ? Color.orange : (valueColor ?? Color.primary)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).fontWeight(prominent ? .semibold : .regular)
                .foregroundStyle(color)
                .monospacedDigit()
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class MeterDelegate: NSObject, NSApplicationDelegate {
    private let store = MeterStore()
    private var statusItem: NSStatusItem!
    private lazy var panel = StatusPanel(content: AnyView(MeterPanel(store: store)),
                                         anchor: { [weak self] in self?.statusItem?.button?.window })
    private var pendingPanelOpen = false
    private var openAttempts = 0
    private var appearanceObservation: NSKeyValueObservation?

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
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateStatus() }
        }
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        store.start()
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
    func applicationWillTerminate(_ notification: Notification) { store.stop(); store.updater.stop(); store.announcements.stop() }
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
                                 showPercentage: !store.iconOnly, refreshing: store.refreshing,
                                 resetCount: store.statusResetCount,
                                 appearance: button.effectiveAppearance,
                                 updateAvailable: store.updater.availableRelease != nil,
                                 unreadAnnouncement: store.announcements.hasUnread)
        button.toolTip = entry.map {
            "Codex · \($0.window.label) · \(percentage(used)) used\nReset: \(resetDate($0.window.resetsAt) ?? "unavailable")\(store.uncertain ? "\nData needs refreshing" : "")"
        } ?? "Codex Meter · usage limits unavailable"
        button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUsage limit resets: " + store.resetAvailabilityText
        if let release = store.updater.availableRelease {
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUpdate available: " + release.version.text
        }
        if store.announcements.hasUnread {
            button.toolTip = (button.toolTip ?? "Codex Meter") + "\nUnread Tibo post mentioning reset"
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
        if CommandLine.arguments.contains("--check") {
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
