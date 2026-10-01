import Foundation

@main struct CreditPaceTests {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        var pace = CreditPace()
        pace.observe(1000, scope: "a", at: start)
        pace.observe(980, scope: "a", at: date(300))
        precondition(pace.perHour(at: date(300)) == nil)
        pace.observe(960, scope: "a", at: date(600))
        pace.observe(940, scope: "a", at: date(900))
        precondition(abs(pace.perHour(at: date(900))! - 240) < 0.001)
        pace.observe(940, scope: "a", at: date(1200))
        pace.observe(940, scope: "a", at: date(1500))
        pace.observe(940, scope: "a", at: date(1800))
        precondition(pace.perHour(at: date(1800)) == nil && pace.idle(at: date(1800)))
        precondition(pace.perHour(at: date(2500)) == nil)
        pace.observe(1200, scope: "a", at: date(2100))
        precondition(pace.perHour(at: date(2100)) == nil, "A recharge restarts observations")
        pace.observe(100, scope: "b", at: date(2400))
        precondition(pace.perHour(at: date(2400)) == nil, "An account change must not look like spend")
        pace.observe(90, scope: "b", at: date(3301))
        precondition(pace.perHour(at: date(3301)) == nil, "Long gaps restart observations")
        pace.observe(nil, scope: "b", at: date(3500))
        precondition(pace.perHour(at: date(3500)) == nil)
        func read(_ credits: String) throws -> UsageSnapshot {
            try UsageSnapshot(data: Data(("{\"rateLimits\":{\"primary\":{\"usedPercent\":100},\"credits\":" + credits + "}}").utf8))
        }
        let valid = try read(#"{"hasCredits":true,"unlimited":false,"balance":"840.5"}"#)
        precondition(valid.buckets.first?.credits?.amount == 840.5)
        let zero = try read(#"{"hasCredits":false,"unlimited":false,"balance":"0"}"#)
        precondition(zero.buckets.first?.credits?.amount == 0)
        for raw in ["null", "[]", #"{"hasCredits":true,"unlimited":false,"balance":"NaN"}"#,
                    #"{"hasCredits":true,"unlimited":false,"balance":"-1"}"#,
                    #"{"hasCredits":true,"unlimited":false,"balance":840}"#,
                    #"{"hasCredits":true,"unlimited":true,"balance":"840"}"#] {
            let value = try read(raw)
            precondition(value.buckets.first?.primary?.usedPercent == 100)
            precondition(value.buckets.first?.credits?.amount == nil)
        }
        testSpendTracker(start: start)
        print("Credit balance decoding, recent pace, exhausted-period spend and account isolation tests passed")
    }

    static func testSpendTracker(start: Date) {
        func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        func entry(_ used: Double?, id: String = "codex/primary", reset: Double? = 86_400,
                   bucket: String = "codex") -> UsageEntry {
            UsageEntry(id: id, bucketId: bucket, bucketName: bucket,
                       window: RateLimitWindow(usedPercent: used, windowDurationMins: 10_080,
                                               resetsAt: reset.map { start.timeIntervalSince1970 + $0 }))
        }
        func spend(_ actual: Double?, _ expected: Double, _ message: String) {
            guard let actual else { preconditionFailure(message + " (missing period)") }
            precondition(abs(actual - expected) < 0.000_001, message)
        }
        func observe(_ tracker: inout CreditSpendTracker, _ amount: Double?, _ seconds: Double,
                     used: Double? = 100, scope: String? = "personal-a", reset: Double? = 86_400) {
            tracker.observe(balance: amount, scope: scope, windows: [entry(used, reset: reset)], at: date(seconds))
        }

        var initiallyExhausted = CreditSpendTracker()
        observe(&initiallyExhausted, 1000, 0)
        precondition(initiallyExhausted.current?.isPartial == true,
                     "Starting while quota is exhausted cannot reconstruct earlier spend")
        spend(initiallyExhausted.current?.observedSpend, 0, "The first balance is only a baseline")
        observe(&initiallyExhausted, 970, 300)
        spend(initiallyExhausted.current?.observedSpend, 30, "Count the first observed decrease")

        var transition = CreditSpendTracker()
        observe(&transition, 1000, 0, used: 99)
        observe(&transition, 990, 300)
        precondition(transition.current?.isPartial == false && transition.current?.startedAt == date(300),
                     "A fresh transition starts an observed exhausted period")
        spend(transition.current?.observedSpend, 0, "Never attribute the pre-start decrease to exhausted quota")
        observe(&transition, 960, 600)
        observe(&transition, 960, 900)
        observe(&transition, 950, 1200)
        spend(transition.current?.observedSpend, 40, "Accumulate decreases without charging unchanged balances")
        observe(&transition, 940, 1200)
        observe(&transition, 930, 1100)
        spend(transition.current?.observedSpend, 40, "Duplicate and older timestamps cannot add spend")
        observe(&transition, 900, 1500, used: 5)
        precondition(transition.current == nil && transition.previous?.endedAt == date(1500),
                     "Recovery closes the period")
        spend(transition.previous?.observedSpend, 40, "The recovery read cannot bill its decrease to exhaustion")
        observe(&transition, 890, 1800)
        precondition(transition.current?.isPartial == false, "A subsequent fresh transition starts a new period")
        spend(transition.current?.observedSpend, 0, "Only the new period's baseline is retained")
        spend(transition.previous?.observedSpend, 40, "Keep only the latest completed aggregate")

        var recharge = CreditSpendTracker()
        observe(&recharge, 1000, 0, used: 50)
        observe(&recharge, 1000, 300)
        observe(&recharge, 970, 600)
        observe(&recharge, 1200, 900)
        precondition(recharge.current?.isPartial == true, "An adjustment makes the observed sum partial")
        spend(recharge.current?.observedSpend, 30, "Recharges preserve observed consumption")
        observe(&recharge, 1180, 1200)
        spend(recharge.current?.observedSpend, 50, "Use the new post-recharge baseline")

        var gap = CreditSpendTracker()
        observe(&gap, 1000, 0, used: 50)
        observe(&gap, 1000, 300)
        observe(&gap, 970, 600)
        observe(&gap, 900, 1201)
        precondition(gap.current?.isPartial == true, "Long gaps make a retained period partial")
        spend(gap.current?.observedSpend, 30, "Do not infer spending across a gap")
        observe(&gap, 890, 1501)
        spend(gap.current?.observedSpend, 40, "Accumulate continuous observations after a gap")
        gap.markUnavailable()
        precondition(gap.resetDeadline(at: date(1501)) == nil, "Failed reads invalidate deadline projections")
        observe(&gap, 850, 1801)
        spend(gap.current?.observedSpend, 40, "Do not infer spending across a failed read")
        observe(&gap, 840, 2101)
        spend(gap.current?.observedSpend, 50, "Continuous reads after failure can add observed spend")
        observe(&gap, nil, 2401)
        observe(&gap, 800, 2701)
        spend(gap.current?.observedSpend, 50, "Unknown balances break attribution")
        observe(&gap, 790, 3001)
        spend(gap.current?.observedSpend, 60, "A new valid baseline resumes observations")

        var staleTransition = CreditSpendTracker()
        observe(&staleTransition, 1000, 0, used: 50)
        observe(&staleTransition, 950, 601)
        precondition(staleTransition.current?.isPartial == true, "A stale available reading cannot prove onset")

        var lateRecovery = CreditSpendTracker()
        observe(&lateRecovery, 1000, 0, used: 50)
        observe(&lateRecovery, 1000, 300)
        observe(&lateRecovery, 970, 600)
        observe(&lateRecovery, 900, 1201, used: 10)
        precondition(lateRecovery.previous?.isPartial == true,
                     "A long gap also marks a period partial when the next read confirms recovery")
        spend(lateRecovery.previous?.observedSpend, 30, "Recovery after a gap preserves the observed aggregate")

        var invalidBalance = CreditSpendTracker()
        observe(&invalidBalance, 1000, 0, used: 50)
        observe(&invalidBalance, 1000, 300)
        observe(&invalidBalance, 970, 600)
        for (index, amount) in [Double.nan, Double.infinity, -1].enumerated() {
            observe(&invalidBalance, amount, Double(900 + index * 600))
            observe(&invalidBalance, 900 - Double(index * 10), Double(1200 + index * 600))
        }
        spend(invalidBalance.current?.observedSpend, 30, "Invalid balances never invent an observed decrease")
        precondition(invalidBalance.current?.isPartial == true)

        var unknownQuota = CreditSpendTracker()
        observe(&unknownQuota, 1000, 0, used: 50)
        observe(&unknownQuota, 1000, 300)
        observe(&unknownQuota, 970, 600)
        observe(&unknownQuota, 950, 900, used: nil)
        precondition(unknownQuota.current != nil && unknownQuota.previous == nil,
                     "Unknown usage must not close the exhausted period")
        precondition(unknownQuota.current?.isPartial == true && unknownQuota.resetDeadline(at: date(900)) == nil)
        observe(&unknownQuota, 900, 1200)
        spend(unknownQuota.current?.observedSpend, 30, "Do not attribute decreases across unknown quota")
        observe(&unknownQuota, 890, 1500)
        spend(unknownQuota.current?.observedSpend, 40, "Known continuous exhaustion resumes observations")
        unknownQuota.observe(balance: 880, scope: "personal-a", windows: [], at: date(1800))
        precondition(unknownQuota.current != nil, "Missing Codex windows are not recovery")
        unknownQuota.observe(balance: 870, scope: "personal-a", windows: [entry(10, bucket: "other")], at: date(2100))
        precondition(unknownQuota.current != nil, "Other buckets cannot close a Codex period")

        var rollover = CreditSpendTracker()
        observe(&rollover, 1000, 0, used: 50)
        observe(&rollover, 1000, 300, reset: 750)
        observe(&rollover, 970, 600, reset: 750)
        observe(&rollover, 900, 900, reset: 172_800)
        precondition(rollover.current?.startedAt == date(900) && rollover.current?.isPartial == true,
                     "An elapsed exhausted reset cycle with a later deadline starts a partial period")
        spend(rollover.previous?.observedSpend, 30, "The old cycle keeps only known decreases")
        precondition(rollover.previous?.endedAt == date(900) && rollover.previous?.isPartial == true)
        spend(rollover.current?.observedSpend, 0, "Do not infer spending across an unobserved reset cycle")
        observe(&rollover, 890, 1200, reset: 172_800)
        spend(rollover.current?.observedSpend, 10, "The new cycle can accumulate observed decreases")

        var futureCorrection = CreditSpendTracker()
        observe(&futureCorrection, 1000, 0, used: 50)
        observe(&futureCorrection, 1000, 300)
        observe(&futureCorrection, 970, 600)
        observe(&futureCorrection, 950, 900, reset: 172_800)
        precondition(futureCorrection.current?.startedAt == date(300) && futureCorrection.previous == nil,
                     "A corrected future deadline does not establish quota recovery")
        spend(futureCorrection.current?.observedSpend, 50, "Future deadline corrections preserve observed spending")
        observe(&futureCorrection, 940, 1200, reset: 86_400)
        precondition(futureCorrection.current?.startedAt == date(300) && futureCorrection.current?.isPartial == false,
                     "A revised future deadline keeps the same observed period")
        spend(futureCorrection.current?.observedSpend, 60, "An earlier future correction also preserves accumulation")

        var multiple = CreditSpendTracker()
        let short = "codex/primary", week = "codex/secondary"

        var replacement = CreditSpendTracker()
        replacement.observe(balance: 1000, scope: "personal-a", windows: [entry(50, id: short), entry(50, id: week)], at: date(0))
        replacement.observe(balance: 1000, scope: "personal-a", windows: [entry(100, id: short), entry(50, id: week)], at: date(300))
        replacement.observe(balance: 970, scope: "personal-a", windows: [entry(100, id: short), entry(50, id: week)], at: date(600))
        replacement.observe(balance: 900, scope: "personal-a", windows: [entry(20, id: short), entry(100, id: week)], at: date(900))
        precondition(replacement.current?.startedAt == date(300) && replacement.current?.isPartial == true,
                     "Replacing every blocker before its reset preserves the known partial aggregate")
        spend(replacement.current?.observedSpend, 30, "Do not attribute the debit between unrelated exhausted endpoints")
        replacement.observe(balance: 890, scope: "personal-a", windows: [entry(20, id: short), entry(100, id: week)], at: date(1200))
        spend(replacement.current?.observedSpend, 40, "The replacement blocker establishes a new balance baseline")

        var elapsedReplacement = CreditSpendTracker()
        elapsedReplacement.observe(balance: 1000, scope: "personal-a", windows: [entry(50, id: short), entry(50, id: week)], at: date(0))
        elapsedReplacement.observe(balance: 1000, scope: "personal-a", windows: [entry(100, id: short, reset: 750), entry(50, id: week)], at: date(300))
        elapsedReplacement.observe(balance: 970, scope: "personal-a", windows: [entry(100, id: short, reset: 750), entry(50, id: week)], at: date(600))
        elapsedReplacement.observe(balance: 900, scope: "personal-a", windows: [entry(20, id: short), entry(100, id: week)], at: date(900))
        precondition(elapsedReplacement.current?.startedAt == date(900) && elapsedReplacement.current?.isPartial == true,
                     "A replacement after all former reset deadlines starts a new partial period")
        precondition(elapsedReplacement.previous?.endedAt == date(900) && elapsedReplacement.previous?.isPartial == true)
        spend(elapsedReplacement.previous?.observedSpend, 30, "The elapsed prior cycle retains its observed total")
        spend(elapsedReplacement.current?.observedSpend, 0, "Do not carry the replacement interval into the new period")

        multiple.observe(balance: 1000, scope: "personal-a", windows: [entry(50, id: short), entry(50, id: week)], at: date(0))
        multiple.observe(balance: 1000, scope: "personal-a", windows: [entry(100, id: short, reset: 3600), entry(50, id: week)], at: date(300))
        multiple.observe(balance: 970, scope: "personal-a", windows: [entry(100, id: short, reset: 3600), entry(100, id: week, reset: 86_400)], at: date(600))
        precondition(multiple.current?.startedAt == date(300) && multiple.current?.isPartial == false,
                     "A new blocker can extend the same exhausted period")
        spend(multiple.current?.observedSpend, 30, "An unchanged blocker preserves continuity")
        precondition(multiple.resetDeadline(at: date(600)) == date(86_400),
                     "Included quota returns only after the last exhausted window resets")
        multiple.observe(balance: 950, scope: "personal-a", windows: [entry(100, id: short, reset: 7200), entry(100, id: week, reset: 86_400)], at: date(900))
        precondition(multiple.current?.startedAt == date(300), "One unchanged exhausted window preserves the episode")
        spend(multiple.current?.observedSpend, 50, "Changing one blocker does not discard continuous spend")
        multiple.observe(balance: 940, scope: "personal-a", windows: [entry(20, id: short, reset: 7200), entry(nil, id: week)], at: date(1200))
        precondition(multiple.current != nil && multiple.resetDeadline(at: date(1200)) == nil,
                     "An unknown remaining window prevents inferred recovery")

        var deadline = CreditSpendTracker()
        observe(&deadline, 1000, 0)
        precondition(deadline.resetDeadline(at: date(600)) == date(86_400), "Freshness includes ten minutes")
        precondition(deadline.resetDeadline(at: date(601)) == nil, "Stale observations cannot project reset spend")
        precondition(deadline.resetDeadline(at: date(-1)) == nil, "Future observations cannot project reset spend")
        observe(&deadline, 990, 300, reset: nil)
        precondition(deadline.resetDeadline(at: date(300)) == nil, "Missing reset timestamps have no deadline")
        observe(&deadline, 980, 600, reset: 600)
        precondition(deadline.resetDeadline(at: date(600)) == nil, "A due but unconfirmed reset has no forecast")
        observe(&deadline, 970, 900, reset: 600)
        precondition(deadline.resetDeadline(at: date(900)) == nil, "Past exhausted resets have no forecast")
        deadline.observe(balance: 960, scope: "personal-a", windows: [entry(100), entry(nil, id: week)], at: date(1200))
        precondition(deadline.resetDeadline(at: date(1200)) == nil, "All present Codex usages must be known")
        deadline.observe(balance: 950, scope: "personal-a", windows: [entry(100), entry(100, id: week, reset: nil)], at: date(1500))
        precondition(deadline.resetDeadline(at: date(1500)) == nil, "Every exhausted window needs a future reset")
        deadline.observe(balance: 940, scope: "personal-a", windows: [entry(100), entry(nil, bucket: "other")], at: date(1800))
        precondition(deadline.resetDeadline(at: date(1800)) == date(86_400), "Unrelated buckets do not block Codex forecasts")

        var awaitingShortReset = CreditSpendTracker()
        awaitingShortReset.observe(balance: 1000, scope: "personal-a",
                                   windows: [entry(100, id: short, reset: 300), entry(100, id: week, reset: 86_400)],
                                   at: date(0))
        precondition(awaitingShortReset.resetDeadline(at: date(299)) == date(86_400),
                     "The forecast uses the latest blocker while every reset is still future")
        precondition(awaitingShortReset.resetDeadline(at: date(300)) == nil,
                     "A due earlier blocker pauses the forecast until fresh quota confirms its reset")
        precondition(awaitingShortReset.resetDeadline(at: date(301)) == nil,
                     "A later future blocker cannot hide an earlier unconfirmed reset")

        var account = CreditSpendTracker()
        observe(&account, 1000, 0, used: 50)
        observe(&account, 1000, 300)
        observe(&account, 970, 600)
        observe(&account, 970, 900, used: 0)
        observe(&account, 100, 1200, scope: "personal-b")
        precondition(account.previous == nil && account.current?.isPartial == true,
                     "Account changes clear both aggregates")
        spend(account.current?.observedSpend, 0, "An account balance change is not spend")
        observe(&account, 90, 1500, scope: nil)
        precondition(account.current == nil && account.previous == nil, "Unknown scope clears account aggregates")
        observe(&account, 80, 1800, scope: "   ")
        precondition(account.current == nil && account.previous == nil, "Blank scope cannot start an account period")
        account.observe(balance: 70, scope: "personal-a", windows: [entry(100, bucket: "other")], at: date(2100))
        precondition(account.current == nil, "Only Codex exhaustion starts a period")

        var oldTimestampAccount = CreditSpendTracker()
        observe(&oldTimestampAccount, 1000, 0, used: 50)
        observe(&oldTimestampAccount, 1000, 300)
        observe(&oldTimestampAccount, 970, 600)
        observe(&oldTimestampAccount, 100, 599, scope: "personal-b")
        precondition(oldTimestampAccount.current == nil && oldTimestampAccount.previous == nil,
                     "An older timestamp cannot retain aggregates from a different account")
        observe(&oldTimestampAccount, 100, 900, scope: "personal-b")
        observe(&oldTimestampAccount, 90, 1200, scope: "personal-b")
        spend(oldTimestampAccount.current?.observedSpend, 10, "The new account starts an independent partial period")
        observe(&oldTimestampAccount, 80, 300, scope: nil)
        precondition(oldTimestampAccount.current == nil && oldTimestampAccount.previous == nil,
                     "An unknown scope clears account aggregates even on an older timestamp")
    }
}
