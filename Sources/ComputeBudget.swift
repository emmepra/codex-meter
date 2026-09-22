import Foundation

/// Budget and constant-pace estimates from the current limit snapshot.
/// Percentages are points of the whole window quota, not tokens or measured history.
struct ComputeBudget {
    let remainingPercent: Double
    let remainingSeconds: Double
    let elapsedFraction: Double?
    let averagePerDay: Double?
    let projectedExhaustion: Date?
    let projectedRemainingAtReset: Double?
    /// Positive means consumption is ahead of an even allowance across the window.
    let pacingDifference: Double?

    var budgetPerDay: Double { remainingPercent / (remainingSeconds / 86_400) }
    var budgetPerHour: Double { remainingPercent / (remainingSeconds / 3_600) }

    /// Enough of the inferred window has elapsed to display a constant-pace estimate.
    /// This guards initial spikes; it does not imply that future usage is predictable.
    var projectionReliable: Bool { averagePerDay != nil }

    init?(window: RateLimitWindow, now: Date) {
        guard let used = window.usedPercent,
              let reset = window.resetsAt,
              now.timeIntervalSince1970.isFinite else { return nil }
        let secondsLeft = reset - now.timeIntervalSince1970
        guard secondsLeft.isFinite, secondsLeft > 0 else { return nil }

        remainingPercent = 100 - used
        remainingSeconds = secondsLeft

        // Duration is optional: the forward allowance needs only quota and reset.
        // An inferred start in the future makes elapsed-window estimates unavailable.
        let duration = window.windowDurationMins.map { Double($0) * 60 }
        guard let duration, duration > 0, secondsLeft <= duration else {
            elapsedFraction = nil
            averagePerDay = nil
            projectedExhaustion = used == 100 ? now : nil
            projectedRemainingAtReset = nil
            pacingDifference = nil
            return
        }

        let elapsedSeconds = duration - secondsLeft
        elapsedFraction = elapsedSeconds / duration
        pacingDifference = used - elapsedSeconds / duration * 100

        // Wait one hour, or 20% of a window shorter than five hours. Before this
        // threshold an initial burst divided by a few minutes would be misleading.
        guard elapsedSeconds >= min(3_600, duration * 0.2) else {
            averagePerDay = nil
            projectedExhaustion = used == 100 ? now : nil
            projectedRemainingAtReset = nil
            return
        }

        let ratePerSecond = used / elapsedSeconds
        averagePerDay = ratePerSecond * 86_400
        projectedRemainingAtReset = min(100, max(0, remainingPercent - ratePerSecond * secondsLeft))
        // Dates beyond reset describe a hypothetical unchanged pace without refill;
        // the UI can compare the date with reset and show the remaining quota instead.
        projectedExhaustion = ratePerSecond > 0
            ? now.addingTimeInterval(remainingPercent / ratePerSecond)
            : nil
    }
}
