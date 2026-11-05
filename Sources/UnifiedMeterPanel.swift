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
            HStack(spacing: 6) {
                Text("Usage").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { selection.refreshAll() } label: {
                    ZStack {
                        if selection.codex.refreshing { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                    }.frame(width: 20, height: 20).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(selection.codex.refreshing)
                    .help(selection.claudeEnabled ? "Refresh Codex and read the latest Claude capture." : "Refresh usage limits.")
                    .accessibilityLabel("Refresh usage")
                MeterOptions(selection: selection, staticPreview: staticPreview)
            }.frame(minHeight: 20).padding(.bottom, 14)

            section(selection.codex)
            if selection.claudeEnabled {
                Divider().padding(.vertical, 14)
                section(selection.claude)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(width: 300)
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

@MainActor
private struct ProviderOverview: View {
    @ObservedObject var store: MeterStore
    @ObservedObject var announcements: ResetAnnouncements
    let staticPreview: Bool
    @Binding var expanded: Bool

    private var used: Double? { store.entry?.window.usedPercent }
    private var faded: Bool { store.uncertain }
    private var windowTitle: String {
        guard let entry = store.entry else { return "No data" }
        return entry.bucketId == store.provider.rawValue ? entry.window.label : "\(entry.bucketName) · \(entry.window.label)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.provider.title).font(.system(size: 12, weight: .semibold))
                if store.entry != nil { windowSelector }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percentage(used))
                        .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 10)).foregroundStyle(.secondary)
                }.opacity(faded ? 0.5 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(percentage(used)) used\(faded ? ", last known reading" : "")")
            }

            ConsumptionTrack(used: used, elapsed: nil, faded: faded)
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
            }.font(.system(size: 10)).foregroundStyle(.secondary)

            if expanded {
                Divider().padding(.top, 2)
                UsageDetails(store: store, announcements: announcements).padding(.top, 2)
            }
        }
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
        }.frame(minHeight: 20).contentShape(Rectangle())
    }

    private var missingReading: String {
        if store.refreshing { return "Reading usage limits…" }
        if store.provider == .claude, store.updatedAt == nil { return "Waiting for Claude Code" }
        return "Usage limits unavailable"
    }

    private var freshness: String {
        guard let date = store.updatedAt else { return store.provider == .claude ? "No capture yet" : "Not updated yet" }
        let age = max(0, store.now.timeIntervalSince(date))
        let relative: String
        if age < 60 { relative = "just now" }
        else if age < 3_600 { relative = "\(Int(age / 60)) min ago" }
        else if age < 86_400 { relative = "\(Int(age / 3_600)) h ago" }
        else { relative = "\(Int(age / 86_400)) d ago" }
        return (store.provider == .claude ? "Captured " : "Updated ") + relative
    }

    private var freshnessHelp: String {
        let timestamp = store.updatedAt?.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(overviewLocale))
        if store.provider == .claude {
            return timestamp.map { "Captured from Claude Code: \($0).\nMeter reads the latest local capture. Capture time does not guarantee a new server measurement." }
                ?? "No Claude Code capture received. Choose Set Up Claude in Options if needed, then open or reload a local Code session."
        }
        return timestamp.map { "Last successful quota reading: \($0)." } ?? "No successful quota reading yet."
    }
}
