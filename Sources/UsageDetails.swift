import AppKit
import SwiftUI

/// Supporting estimates and Codex extras; the overview owns the quota summary.
struct UsageDetails: View {
    @ObservedObject var store: MeterStore
    @ObservedObject var announcements: ResetAnnouncements

    private var budget: ComputeBudget? {
        guard !store.uncertain, let window = store.entry?.window else { return nil }
        return ComputeBudget(window: window, now: store.now)
    }
    private var daily: Bool { (budget?.remainingSeconds ?? 0) >= 86_400 }
    private var resetAvailabilityColor: Color {
        guard let count = store.snapshot?.availableResetCount else { return .secondary }
        if store.stale { return .orange }
        return Color(nsColor: count > 0 ? .systemGreen : .systemRed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            quotaDetails
            if store.provider == .codex {
                Divider()
                VStack(spacing: 7) {
                    if store.credits != nil {
                        stat(store.creditBalanceLabel, store.creditBalanceText)
                            .help("Account credit balance, separate from included quota and banked resets. A recent decrease may also reflect expiry or adjustments.")
                    }
                    if let amount = store.credits?.amount, amount > 0 {
                        stat("Recent consumption", store.creditRateText)
                            .help("Observed balance decrease over up to 30 minutes, after at least 15 minutes of readings. Additions, account changes or long gaps restart the estimate.")
                        if store.creditRate != nil {
                            stat("Credit runway", store.creditRunwayText)
                                .help("Remaining balance divided by recent observed consumption; an estimate at that pace.")
                        }
                    }
                    stat("Banked resets", store.resetAvailabilityText, valueColor: resetAvailabilityColor)
                        .help("Banked resets for the Codex CLI account. Availability does not mean a quota window is eligible. Redeem resets in Codex.")
                }
                announcementRow
            }
        }.accessibilityElement(children: .contain)
    }

    @ViewBuilder private var quotaDetails: some View {
        if let budget {
            VStack(spacing: 7) {
                stat(daily ? "Daily budget" : "Hourly budget",
                     quotaAmount(daily ? budget.budgetPerDay : budget.budgetPerHour), prominent: true)
                    .help("Remaining quota divided by time until reset. Percentage points of the total quota available every \(daily ? "24 hours" : "hour"), starting now.")
                if let endOfDay = Calendar.current.dateInterval(of: .day, for: store.now)?.end,
                   endOfDay.timeIntervalSince(store.now) < budget.remainingSeconds {
                    let todayBudget = budget.remainingPercent * endOfDay.timeIntervalSince(store.now) / budget.remainingSeconds
                    stat("Today, from now", quotaAmount(todayBudget))
                        .help("Quota available from now until midnight at the budgeted pace.")
                }
                stat(daily ? "Average / day" : "Average / hour",
                     budget.averagePerDay.map { quotaAmount(daily ? $0 : $0 / 24) } ?? "—")
                    .help("Estimated average since the inferred start of the period, rather than a measured usage history.")
                if budget.remainingPercent > 0 {
                    if let exhaustion = budget.projectedExhaustion,
                       exhaustion.timeIntervalSince(store.now) < budget.remainingSeconds {
                        stat("Runway at this pace", remainingTime(exhaustion.timeIntervalSince1970, now: store.now), warning: true)
                            .help("Estimate at the average pace since the start of the period. Future usage may change.")
                    } else if let remaining = budget.projectedRemainingAtReset {
                        stat("Projected at reset", "\(quotaAmount(remaining)) remaining")
                            .help("Quota that would remain at reset at the same average pace.")
                    } else {
                        stat("Pace estimate", "Not enough data")
                    }
                }
            }
        } else {
            Text(store.uncertain ? "Quota estimates paused until a fresh read." : "Estimates need quota and reset time.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var announcementRow: some View {
        if announcements.enabled {
            if let post = announcements.latest,
               store.now.timeIntervalSince(post.date) <= ResetFeed.maximumAge {
                HStack(spacing: 6) {
                    Button { announcements.openLatest() } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                if announcements.hasUnread { Circle().fill(Color.orange).frame(width: 4, height: 4) }
                                Text("𝕏").font(.system(size: 11)).accessibilityHidden(true)
                                Text("Tibo")
                                if announcements.unavailable { Text("· cached").foregroundStyle(.secondary) }
                                Spacer(minLength: 2)
                                Text(postDateLabel(post.date, now: store.now))
                                Image(systemName: "arrow.up.right").font(.system(size: 8))
                            }
                            Text(post.excerpt)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 11)).foregroundStyle(.primary)
                    }.buttonStyle(.plain).help("\(post.date.formatted(Date.FormatStyle(date: .complete, time: .shortened).locale(meterLocale)))\n\(post.text.prefix(500))\nVia x.noodl3.net · Keyword match, not confirmation of an account reset.")
                    if announcements.hasUnread {
                        Button { announcements.markRead() } label: {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .medium))
                                .frame(width: 20, height: 20).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Mark as seen").accessibilityLabel("Mark Tibo post as seen")
                    }
                }
            } else if announcements.unavailable {
                Text("Tibo posts unavailable").font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("The public RSS source x.noodl3.net could not be refreshed. Quota data is unaffected.")
            }
        }
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
