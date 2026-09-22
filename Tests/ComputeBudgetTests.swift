import Foundation

@main
enum ComputeBudgetTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0

        func window(_ used: Double?, duration: Int? = 10_080, left: Double? = 3.5 * 86_400) -> RateLimitWindow {
            RateLimitWindow(usedPercent: used, windowDurationMins: duration,
                            resetsAt: left.map { now.timeIntervalSince1970 + $0 })
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        func close(_ actual: Double?, _ expected: Double, _ message: String) {
            guard let actual else { preconditionFailure(message + " (missing value)") }
            check(abs(actual - expected) < 0.000_001, message)
        }

        let slow = ComputeBudget(window: window(25), now: now)!
        close(slow.remainingPercent, 75, "25 used leaves 75 points")
        close(slow.remainingSeconds, 3.5 * day, "Half a week remains")
        close(slow.budgetPerDay, 75 / 3.5, "Divide residual quota by remaining days")
        close(slow.budgetPerHour, 75 / (3.5 * 24), "Hourly allowance")
        close(slow.elapsedFraction, 0.5, "Half the window elapsed")
        close(slow.averagePerDay, 25 / 3.5, "Average uses elapsed days")
        close(slow.pacingDifference, -25, "Below uniform consumption")
        close(slow.projectedRemainingAtReset, 50, "Half quota left at unchanged pace")
        close(slow.projectedExhaustion?.timeIntervalSince(now), 10.5 * day, "Hypothetical depletion lies beyond reset")
        check(slow.projectionReliable, "Established window permits estimates")

        let fast = ComputeBudget(window: window(75), now: now)!
        close(fast.budgetPerDay, 25 / 3.5, "75 used leaves 7.14 points per day")
        close(fast.pacingDifference, 25, "Ahead of uniform consumption")
        close(fast.projectedRemainingAtReset, 0, "Cannot project negative quota")
        close(fast.projectedExhaustion?.timeIntervalSince(now), 25 / (75 / 3.5) * day,
              "Fast pace depletes before reset")
        check(fast.projectedExhaustion! < now.addingTimeInterval(fast.remainingSeconds), "Insufficient at current pace")

        let zero = ComputeBudget(window: window(0), now: now)!
        close(zero.averagePerDay, 0, "Explicit zero is a known average")
        close(zero.projectedRemainingAtReset, 100, "Zero pace leaves full quota")
        check(zero.projectedExhaustion == nil, "Zero pace has no depletion date")
        let full = ComputeBudget(window: window(100), now: now)!
        close(full.budgetPerDay, 0, "No allowance at full consumption")
        close(full.projectedRemainingAtReset, 0, "Full consumption leaves no quota")
        check(full.projectedExhaustion == now, "Already exhausted")

        for candidate in [window(nil), window(20, left: nil), window(20, left: 0), window(20, left: -1)] {
            check(ComputeBudget(window: candidate, now: now) == nil, "Unknown or expired snapshots have no budget")
        }
        check(ComputeBudget(window: window(20), now: Date(timeIntervalSince1970: .infinity)) == nil,
              "Reject invalid clock values")

        for duration: Int? in [nil, 0, -1] {
            let unspecified = ComputeBudget(window: window(25, duration: duration), now: now)!
            close(unspecified.budgetPerDay, 75 / 3.5, "Forward allowance survives unknown duration")
            check(unspecified.elapsedFraction == nil && unspecified.pacingDifference == nil,
                  "Unknown duration has no elapsed fraction or pace comparison")
            check(unspecified.averagePerDay == nil && unspecified.projectedRemainingAtReset == nil
                  && unspecified.projectedExhaustion == nil && !unspecified.projectionReliable,
                  "Unknown duration has no projections")
        }
        let futureStart = ComputeBudget(window: window(25, duration: 60, left: 7_200), now: now)!
        check(futureStart.elapsedFraction == nil && futureStart.averagePerDay == nil
              && futureStart.projectedRemainingAtReset == nil && futureStart.pacingDifference == nil,
              "Future inferred start must not create negative elapsed time")
        close(futureStart.budgetPerHour, 37.5, "Forward allowance remains useful with invalid duration")

        let start = ComputeBudget(window: window(0, duration: 300, left: 18_000), now: now)!
        close(start.elapsedFraction, 0, "Exact start is valid")
        check(start.averagePerDay == nil && start.projectedExhaustion == nil, "Avoid division by zero at start")
        let early = ComputeBudget(window: window(30, duration: 300, left: 17_880), now: now)!
        check(early.elapsedFraction != nil && early.pacingDifference != nil, "Time comparison is available early")
        check(early.averagePerDay == nil && early.projectedExhaustion == nil
              && early.projectedRemainingAtReset == nil && !early.projectionReliable,
              "Initial burst must not create an extreme projection")
        let justBefore = ComputeBudget(window: window(20, duration: 300, left: 14_401), now: now)!
        check(!justBefore.projectionReliable, "Five-hour window waits a full hour")
        let fiveHours = ComputeBudget(window: window(20, duration: 300, left: 14_400), now: now)!
        close(fiveHours.budgetPerHour, 20, "Five-hour hourly allowance")
        close(fiveHours.averagePerDay, 480, "Average expresses quota points, so may exceed 100 per day")
        close(fiveHours.pacingDifference, 0, "Uniform five-hour pace")
        close(fiveHours.projectedExhaustion?.timeIntervalSince(now), 14_400, "Depletion exactly at reset")
        check(fiveHours.projectionReliable, "One-hour threshold includes its boundary")
        let shortWindow = ComputeBudget(window: window(20, duration: 60, left: 2_880), now: now)!
        check(shortWindow.projectionReliable, "Short window threshold is 20 percent, or 12 minutes here")

        close(ComputeBudget(window: window(-20), now: now)!.remainingPercent, 100,
              "Use model-clamped negative consumption")
        close(ComputeBudget(window: window(150), now: now)!.remainingPercent, 0,
              "Use model-clamped excessive consumption")
        print("ComputeBudget tests passed")
    }
}
