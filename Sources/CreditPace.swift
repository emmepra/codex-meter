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
    func perHour(at now: Date) -> Double? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last,
              now.timeIntervalSince(last.date) >= 0, now.timeIntervalSince(last.date) <= 600,
              let lastDecrease, now.timeIntervalSince(lastDecrease) <= 600 else { return nil }
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
