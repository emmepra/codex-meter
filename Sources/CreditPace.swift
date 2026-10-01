import Foundation

/// A short-lived observation of balance changes, never a per-task billing ledger.
struct CreditPace {
    private struct Sample { let date: Date; let amount: Double }
    private var samples: [Sample] = []
    private var scope: String?
    private var lastDecrease: Date?

    mutating func reset() { samples.removeAll(); scope = nil; lastDecrease = nil }
    mutating func observe(_ amount: Double?, scope: String, at date: Date) {
        guard let amount, amount.isFinite, amount >= 0 else { reset(); return }
        if self.scope != scope { reset(); self.scope = scope }
        if let previous = samples.last {
            let gap = date.timeIntervalSince(previous.date)
            if gap <= 0 { return }
            if gap > 600 || amount > previous.amount { reset(); self.scope = scope }
            else if amount < previous.amount { lastDecrease = date }
        }
        samples.append(Sample(date: date, amount: amount))
        samples.removeAll { date.timeIntervalSince($0.date) > 1800 }
    }
    /// A recent balance decrease is useful before there is enough history for a pace estimate.
    func hasRecentDecrease(at now: Date) -> Bool {
        guard scope != nil, let last = samples.last, let lastDecrease else { return false }
        let sampleAge = now.timeIntervalSince(last.date)
        let decreaseAge = now.timeIntervalSince(lastDecrease)
        return sampleAge >= 0 && sampleAge <= 600 && decreaseAge >= 0 && decreaseAge <= 600
    }
    func perHour(at now: Date) -> Double? {
        guard scope != nil, samples.count >= 3,
              let first = samples.first, let last = samples.last else { return nil }
        let sampleAge = now.timeIntervalSince(last.date)
        guard sampleAge >= 0 && sampleAge <= 600 else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed >= 900, first.amount > last.amount else { return nil }
        let rate = (first.amount - last.amount) * 3600 / elapsed
        return rate.isFinite && rate > 0 ? rate : nil
    }
    func idle(at now: Date) -> Bool {
        guard let first = samples.first, let last = samples.last,
              now.timeIntervalSince(last.date) >= 0, now.timeIntervalSince(last.date) <= 600,
              last.date.timeIntervalSince(first.date) >= 900 else { return false }
        return lastDecrease.map { now.timeIntervalSince($0) > 600 } ?? true
    }
}

/// Observed balance decreases while included Codex quota is exhausted.
/// Only two aggregates are retained; gaps cannot be reconstructed as billing history.
struct CreditSpendTracker {
    struct Period {
        let startedAt: Date
        var observedSpend: Double
        var isPartial: Bool
        var endedAt: Date?
    }

    private struct Blocker {
        let id: String
        let reset: Double?
    }

    private(set) var current: Period?
    private(set) var previous: Period?
    private var scope: String?
    private var lastObservation: Date?
    private var lastBalance: Double?
    private var wasAvailable = false
    private var blockers: [Blocker] = []
    private var deadline: Date?

    mutating func observe(balance: Double?, scope: String?, windows: [UsageEntry], at date: Date) {
        let previousObservation = lastObservation
        guard let scope, !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self = CreditSpendTracker()
            return
        }
        if self.scope != scope {
            self = CreditSpendTracker()
            self.scope = scope
        }
        // Identity changes clear account data even if the incoming timestamp is unusable.
        guard date.timeIntervalSince1970.isFinite else { return }
        if let previousObservation, date <= previousObservation { return }

        let continuous = lastObservation.map { date.timeIntervalSince($0) <= 600 } ?? false
        let knownAvailable = continuous && wasAvailable
        lastObservation = date
        let amount = balance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let codex = windows.filter { $0.bucketId == "codex" }
        let allKnown = !codex.isEmpty && codex.allSatisfy { $0.window.usedPercent != nil }
        let exhausted = codex.filter { ($0.window.usedPercent ?? 0) >= 100 }

        // An unknown window is not evidence that included quota recovered.
        if exhausted.isEmpty {
            if allKnown {
                if !continuous || amount == nil { current?.isPartial = true }
                close(at: date)
                blockers.removeAll()
                wasAvailable = amount != nil
                lastBalance = amount
                deadline = nil
            } else {
                markUnavailable()
            }
            return
        }

        let nextBlockers = exhausted.map { Blocker(id: $0.id, reset: $0.window.resetsAt) }
        let hasPersistingBlocker = blockers.contains { blocker in
            guard let next = nextBlockers.first(where: { $0.id == blocker.id }) else { return false }
            guard let oldReset = blocker.reset, let newReset = next.reset else { return true }
            // A future timestamp correction is not an observed or elapsed reset.
            return !(oldReset <= date.timeIntervalSince1970 && newReset > oldReset)
        }
        let replacedBlockers = !blockers.isEmpty && !hasPersistingBlocker
        let rolledOver = replacedBlockers && blockers.allSatisfy {
            $0.reset.map { $0 <= date.timeIntervalSince1970 } ?? false
        }
        if current == nil || rolledOver {
            if rolledOver {
                current?.isPartial = true
                close(at: date)
            }
            current = Period(startedAt: date, observedSpend: 0,
                             isPartial: rolledOver || !knownAvailable || amount == nil,
                             endedAt: nil)
        } else if replacedBlockers {
            // Separate exhausted endpoints do not prove quota stayed exhausted in between.
            current?.isPartial = true
        } else if let amount, let lastBalance, continuous {
            if amount < lastBalance {
                let total = (current?.observedSpend ?? 0) + (lastBalance - amount)
                if total.isFinite { current?.observedSpend = total }
                else { current?.isPartial = true }
            } else if amount > lastBalance {
                // Purchases or adjustments cannot undo already observed decreases.
                current?.isPartial = true
            }
        } else {
            current?.isPartial = true
        }

        wasAvailable = false
        lastBalance = amount
        blockers = nextBlockers
        deadline = nil
        if amount != nil && allKnown,
           nextBlockers.allSatisfy({ $0.reset.map { $0 > date.timeIntervalSince1970 } ?? false }),
           let latest = nextBlockers.compactMap(\.reset).max() {
            deadline = Date(timeIntervalSince1970: latest)
        }
    }

    mutating func markUnavailable() {
        current?.isPartial = true
        lastBalance = nil
        wasAvailable = false
        deadline = nil
    }

    func resetDeadline(at now: Date) -> Date? {
        guard current != nil, let lastObservation, let deadline,
              now.timeIntervalSince1970.isFinite,
              now >= lastObservation, now.timeIntervalSince(lastObservation) <= 600,
              blockers.allSatisfy({ $0.reset.map { $0 > now.timeIntervalSince1970 } ?? false }),
              deadline > now else { return nil }
        return deadline
    }

    private mutating func close(at date: Date) {
        guard var completed = current else { return }
        completed.endedAt = date
        previous = completed
        current = nil
    }
}
