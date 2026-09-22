import AppKit
import SwiftUI

func percentage(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    return "\(Int(value.rounded()))%"
}

func remainingTime(_ reset: Double?, now: Date = Date()) -> String {
    guard let reset, reset.isFinite else { return "Orario non disponibile" }
    let seconds = reset - now.timeIntervalSince1970
    guard seconds > 0 else { return "In attesa del reset" }
    let minutes = Int(ceil(seconds / 60))
    if minutes >= 1440 { return "\(minutes / 1440) g \((minutes % 1440) / 60) h" }
    if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min" }
    return "\(minutes) min"
}

func resetDate(_ timestamp: Double?) -> String? {
    guard let timestamp, timestamp.isFinite else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "it_IT")
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
                self.error = (error as? LocalizedError)?.errorDescription ?? "Impossibile leggere i limiti. Riprova tra poco."
            }
            now = Date()
            refreshing = false
            onChange?()
        }
    }
}

func quotaAmount(_ value: Double) -> String {
    if value > 0 && value < 0.1 { return "<0,1%" }
    return value.formatted(.number.locale(Locale(identifier: "it_IT")).precision(.fractionLength(0...1))) + "%"
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
            .help("La barra è il consumo. Il segno indica la quota che avresti usato distribuendola uniformemente nel periodo.")
            .accessibilityLabel("Consumo \(percentage(used))")
    }
}

struct MeterPanel: View {
    @ObservedObject var store: MeterStore
    private var budget: ComputeBudget? {
        guard !store.uncertain, let window = store.entry?.window else { return nil }
        return ComputeBudget(window: window, now: store.now)
    }
    private var daily: Bool { (budget?.remainingSeconds ?? 0) >= 86_400 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Codex").font(.system(size: 11, weight: .semibold))
                if let entry = store.entry {
                    Text(entry.bucketId == "codex" ? entry.window.label : entry.bucketName)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if store.refreshing { ProgressView().controlSize(.mini) }
                Menu {
                    Toggle("Solo anello nella barra", isOn: $store.iconOnly)
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
                    Button("Aggiorna") { store.refresh() }.disabled(store.refreshing)
                    Button("Esci") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .medium))
                        .frame(width: 18, height: 14).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Opzioni")
                    .accessibilityLabel("Opzioni")
            }

            if let entry = store.entry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(percentage(entry.window.usedPercent.map { 100 - $0 }))
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("disponibile").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(percentage(entry.window.usedPercent)) usato")
                            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }.opacity(store.uncertain ? 0.55 : 1)
                    ConsumptionTrack(used: entry.window.usedPercent, elapsed: budget?.elapsedFraction, faded: store.uncertain)
                    HStack(spacing: 3) {
                        Text(entry.window.resetsAt == nil ? "Reset non disponibile" : (store.resetPending ? "Reset da confermare" : "Reset tra \(remainingTime(entry.window.resetsAt, now: store.now))"))
                        Spacer(minLength: 2)
                        if let date = resetDate(entry.window.resetsAt) { Text(date).foregroundStyle(.secondary) }
                    }.font(.system(size: 10)).lineLimit(1)
                }
                Divider()
                if let budget {
                    VStack(spacing: 7) {
                        stat(daily ? "Budget al giorno" : "Budget all’ora",
                             quotaAmount(daily ? budget.budgetPerDay : budget.budgetPerHour),
                             prominent: true)
                            .help("Quota residua divisa per il tempo al reset. Percentuale della quota totale distribuibile ogni \(daily ? "24 ore" : "ora"), da adesso.")
                        if let endOfDay = Calendar.current.dateInterval(of: .day, for: store.now)?.end,
                           endOfDay.timeIntervalSince(store.now) < budget.remainingSeconds {
                            let todayBudget = budget.remainingPercent * endOfDay.timeIntervalSince(store.now) / budget.remainingSeconds
                            stat("Oggi, da ora", quotaAmount(todayBudget))
                                .help("Quota distribuibile da adesso a mezzanotte, al ritmo del budget indicato.")
                        }
                        stat(daily ? "Media del periodo / giorno" : "Media del periodo / ora",
                             budget.averagePerDay.map { quotaAmount(daily ? $0 : $0 / 24) } ?? "—")
                            .help("Media stimata dall’inizio del periodo: consumo diviso per tempo trascorso. L’inizio è ricavato da reset e durata; non è uno storico delle giornate.")
                        if budget.remainingPercent == 0 {
                            stat("Quota esaurita", "Attendi il reset", warning: true)
                        } else if let exhaustion = budget.projectedExhaustion,
                                  exhaustion.timeIntervalSince(store.now) < budget.remainingSeconds {
                            stat("Autonomia a questo ritmo", remainingTime(exhaustion.timeIntervalSince1970, now: store.now), warning: true)
                                .help("Stima se mantenessi la media dall’inizio del periodo. Il consumo futuro può cambiare.")
                        } else if let remaining = budget.projectedRemainingAtReset {
                            stat("Al reset, a questo ritmo", "\(quotaAmount(remaining)) residuo")
                                .help("Quota che resterebbe al reset se mantenessi la media dall’inizio del periodo.")
                        } else {
                            stat("Stima del ritmo", "Dati insufficienti")
                        }
                    }
                } else if !store.uncertain {
                    Text("Statistiche disponibili con quota e reset noti.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Text(store.refreshing ? "Lettura dei limiti…" : "Limiti non disponibili")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 8)
            }

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if store.uncertain {
                Text(store.resetPending ? "Reset da confermare. Statistiche in pausa." : "Dati non aggiornati. Statistiche in pausa.")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack {
                Text(budget == nil ? "" : "Budget uniforme · stime del periodo")
                Spacer(minLength: 3)
                if let date = store.updatedAt { Text(date.formatted(date: .omitted, time: .shortened)) }
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 14, height: 14)
                }.buttonStyle(.plain).disabled(store.refreshing).help("Aggiorna adesso").accessibilityLabel("Aggiorna adesso")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(14).frame(width: 270)
    }
    private func stat(_ label: String, _ value: String, prominent: Bool = false, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).fontWeight(prominent ? .semibold : .regular)
                .foregroundStyle(warning ? Color.orange : (prominent ? Color.accentColor : Color.primary))
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
        store.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        store.start()
        requestPanelOpen()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestPanelOpen()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) { store.stop() }
    @objc private func togglePanel() {
        if panel.isVisible {
            pendingPanelOpen = false
            panel.hide()
        } else { requestPanelOpen() }
    }
    private func requestPanelOpen() {
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
        var title = entry == nil ? (store.refreshing ? "…" : "—") : percentage(used)
        if store.uncertain { title += " !" }
        button.title = store.iconOnly ? "" : " " + title
        button.image = ringImage(used: used, uncertain: store.uncertain)
        button.toolTip = entry.map {
            "Codex · \($0.window.label) · \(percentage(used)) consumato\nReset: \(resetDate($0.window.resetsAt) ?? "non disponibile")\(store.uncertain ? "\nDati da aggiornare" : "")"
        } ?? "Codex Meter · limiti non disponibili"
        button.setAccessibilityLabel(button.toolTip)
        panel.schedulePosition()
        if pendingPanelOpen { attemptPanelOpen() }
    }
    private func ringImage(used: Double?, uncertain: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { _ in
            let background = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 9, height: 9))
            background.lineWidth = 1.5
            NSColor.labelColor.withAlphaComponent(uncertain ? 0.45 : 0.22).setStroke()
            background.stroke()
            if let used, used > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: NSPoint(x: 6, y: 6), radius: 4.5,
                              startAngle: 90, endAngle: CGFloat(90 - min(100, max(0, used)) * 3.6), clockwise: true)
                arc.lineWidth = 1.7
                arc.lineCapStyle = .round
                NSColor.labelColor.withAlphaComponent(uncertain ? 0.45 : 1).setStroke()
                arc.stroke()
            }
            if uncertain {
                let dot = NSBezierPath(ovalIn: NSRect(x: 4.5, y: 4.5, width: 3, height: 3))
                NSColor.labelColor.setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

@main
struct CodexMeterApp {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let data = try await CodexClient().readLimits()
                    let snapshot = try UsageSnapshot(data: data)
                    guard let entry = snapshot.preferredEntry else {
                        print("Nessuna finestra di consumo disponibile.")
                        exit(2)
                    }
                    print("OK · \(entry.bucketName) · \(entry.window.label) · \(percentage(entry.window.usedPercent)) consumato · reset \(resetDate(entry.window.resetsAt) ?? "non disponibile")")
                    exit(0)
                } catch {
                    print("ERRORE · \(error.localizedDescription)")
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
