import AppKit
import SwiftUI

private let overviewLocale = Locale(identifier: "en_GB")

/// Both services stay visible; only the optional detail section is expanded.
@MainActor
struct UnifiedMeterPanel: View {
    @ObservedObject var selection: ProviderSelection
    private let staticPreview: Bool
    private let announcements: ResetAnnouncements
    @State private var expandedProvider: MeterProvider?

    init(selection: ProviderSelection, staticPreview: Bool = false,
         announcements: ResetAnnouncements? = nil, expandedProvider: MeterProvider? = nil) {
        self.selection = selection
        self.staticPreview = staticPreview
        self.announcements = announcements ?? selection.codex.announcements
        _expandedProvider = State(initialValue: expandedProvider == .claude && !selection.claudeEnabled ? nil : expandedProvider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                MeterBrandMark()
                Text("Codex Meter").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 2) {
                    Button { selection.refreshAll() } label: {
                        ZStack {
                            if selection.codex.refreshing { ProgressView().controlSize(.mini) }
                            else { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                        }.frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(selection.codex.refreshing)
                        .help(selection.claudeEnabled ? "Refresh Codex and Claude usage." : "Refresh usage limits.")
                        .accessibilityLabel("Refresh usage")
                    MeterOptions(selection: selection, staticPreview: staticPreview).frame(width: 24, height: 24)
                }.foregroundStyle(.secondary)
            }.frame(minHeight: 30).padding(.bottom, 12)

            section(selection.codex)
            if selection.claudeEnabled {
                section(selection.claude).padding(.top, 10)
            }
        }
        .padding(14).frame(width: 300)
        .environment(\.locale, overviewLocale)
        .onChange(of: selection.claudeEnabled) { enabled in
            if !enabled, expandedProvider == .claude { expandedProvider = nil }
        }
    }

    private func section(_ store: MeterStore) -> some View {
        ProviderOverview(store: store, announcements: announcements, staticPreview: staticPreview, expanded: Binding(
            get: { expandedProvider == store.provider },
            set: { expanded in
                if expanded { expandedProvider = store.provider }
                else if expandedProvider == store.provider { expandedProvider = nil }
            }
        ))
    }
}

/// The header mark is independent of either provider's logo.
@MainActor
private struct MeterBrandMark: View {
    private static let bundledMark: NSImage? = {
        if let url = Bundle.main.url(forResource: "MeterMark", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        #if METER_TESTS
        let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/MeterMark.png")
        return NSImage(contentsOf: source)
        #else
        return nil
        #endif
    }()

    var body: some View {
        Group {
            if let mark = Self.bundledMark {
                Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
            } else {
                HStack(spacing: 2) {
                    ring(.codex, through: 0.7)
                    ring(.claude, through: 0.45)
                }
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }

    private func ring(_ accent: ProviderAccent, through progress: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(Color(nsColor: accent.color).opacity(0.25), lineWidth: 1.3)
            Circle().trim(from: 0, to: progress)
                .stroke(Color(nsColor: accent.color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(0.65)
        }.frame(width: 7.5, height: 7.5)
    }
}

@MainActor
private struct ProviderOverview: View {
    @ObservedObject var store: MeterStore
    @ObservedObject var announcements: ResetAnnouncements
    let staticPreview: Bool
    @Binding var expanded: Bool

    private var used: Double? { store.entry?.window.usedPercent }
    private var faded: Bool { store.uncertain }
    private var accent: Color { Color(nsColor: (store.provider == .codex ? ProviderAccent.codex : .claude).color) }
    private var windowTitle: String {
        guard let entry = store.entry else { return "No data" }
        return entry.bucketId == store.provider.rawValue ? entry.window.label : "\(entry.bucketName) · \(entry.window.label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(store.provider.title).font(.system(size: 13, weight: .semibold))
                    }
                    if store.entry != nil { windowSelector.padding(.leading, 11) }
                }
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percentage(used))
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 10)).foregroundStyle(.secondary)
                }.opacity(faded ? 0.5 : 1)
                    .layoutPriority(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(percentage(used)) used\(faded ? ", last known reading" : "")")
            }

            ConsumptionTrack(used: used, elapsed: nil, faded: faded,
                             accent: store.provider == .codex ? .codex : .claude)
                .accessibilityHidden(true)

            if let entry = store.entry {
                HStack(spacing: 4) {
                    Text(used == 100 ? "Quota exhausted" : "\(percentage(used.map { 100 - $0 })) remaining")
                    Spacer(minLength: 4)
                    Text(entry.window.resetsAt == nil ? "Reset time unavailable" :
                         (store.resetPending ? "Reset unconfirmed" : "Resets in \(remainingTime(entry.window.resetsAt, now: store.now))"))
                        .help(resetDate(entry.window.resetsAt).map { "Scheduled reset: " + $0 } ?? "Reset time unavailable")
                }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .opacity(faded ? 0.6 : 1)
            } else {
                Text(missingReading).font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(store.error ?? (store.provider == .claude ? "Use Claude Code to receive a capture. Bridge setup is in Options." : "Refresh to read usage limits."))
            }

            if store.entry != nil, faded {
                Label(store.resetPending ? "Estimates paused" : "Out of date · estimates paused",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(store.error ?? "Estimates resume after a fresh quota reading.")
            }

            if store.provider == .codex, !expanded {
                if store.creditInUse || announcements.hasUnread {
                    HStack(spacing: 12) {
                        if store.creditInUse {
                            Button("Credits in use") { expanded = true }
                                .help("Open details for the observed credit balance and recent consumption.")
                        }
                        if announcements.hasUnread {
                            Button { expanded = true } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.orange).frame(width: 4, height: 4)
                                    Text("New Tibo post")
                                }
                            }.help("Show details for a new post mentioning reset. A post does not confirm an account reset.")
                        }
                    }.buttonStyle(.plain).font(.system(size: 10)).frame(minHeight: 20)
                }
            }

            HStack(spacing: 6) {
                Text(freshness).help(freshnessHelp)
                Spacer(minLength: 4)
                Button { expanded.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 8))
                    }.frame(minHeight: 20).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(expanded ? "Hide" : "Show") \(store.provider.title) details")
                    .help("Quota budget and provider details")
            }.font(.system(size: 9.5)).foregroundStyle(.secondary).padding(.top, 2)

            if expanded {
                Divider().padding(.top, 2)
                UsageDetails(store: store, announcements: announcements).padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1))
    }

    @ViewBuilder private var windowSelector: some View {
        if let windows = store.snapshot?.windows, windows.count > 1 {
            Group {
                if staticPreview {
                    windowMenuLabel
                } else {
                    Menu {
                        ForEach(windows) { entry in
                            Button { store.selectedID = entry.id } label: {
                                if store.entry?.id == entry.id {
                                    Label("\(entry.bucketName) · \(entry.window.label)", systemImage: "checkmark")
                                } else { Text("\(entry.bucketName) · \(entry.window.label)") }
                            }
                        }
                    } label: {
                        windowMenuLabel
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                }
            }.fixedSize(horizontal: false, vertical: true)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .accessibilityLabel("Select \(store.provider.title) quota window, \(windowTitle)")
                .help("Select quota window · \(windowTitle)")
        } else {
            Text(windowTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var windowMenuLabel: some View {
        HStack(spacing: 3) {
            Text(windowTitle).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.down").font(.system(size: 8))
        }.frame(minHeight: 16).contentShape(Rectangle())
    }

    private var missingReading: String {
        if store.refreshing { return "Reading usage limits…" }
        if store.provider == .claude, store.updatedAt == nil { return store.error ?? "Waiting for Claude quota" }
        return "Usage limits unavailable"
    }

    private var freshness: String {
        guard let date = store.freshnessDate else { return store.provider == .claude ? "No capture yet" : "Not updated yet" }
        let age = max(0, store.now.timeIntervalSince(date))
        let relative: String
        if age < 60 { relative = "just now" }
        else if age < 3_600 { relative = "\(Int(age / 60)) min ago" }
        else if age < 86_400 { relative = "\(Int(age / 3_600)) h ago" }
        else { relative = "\(Int(age / 86_400)) d ago" }
        let label = store.syncsClaudeDesktop ? "Synced " : (store.provider == .claude && store.claudeSource != .cli ? "Captured " : "Updated ")
        return label + relative
    }

    private var freshnessHelp: String {
        let timestamp = store.updatedAt?.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(overviewLocale))
        if store.provider == .claude {
            if store.claudeSource == .cli, let timestamp {
                return "Claude CLI subscription quota read at \(timestamp)."
            }
            if store.syncsClaudeDesktop, let checked = store.claudeCheckedAt {
                let time = checked.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(overviewLocale))
                return "Synced with Claude Code's local session: \(time).\nLast quota observation: \(timestamp ?? "unavailable").\nClaude may return cached values. Sync does not poll the server."
            }
            return timestamp.map { "Captured from Claude Code: \($0).\nMeter reads the latest local capture. Capture time does not guarantee a new server measurement." }
                ?? "No Claude Code capture received. Choose Set Up Claude in Options if needed, then open or reload a local Code session."
        }
        return timestamp.map { "Last successful quota reading: \($0)." } ?? "No successful quota reading yet."
    }
}
