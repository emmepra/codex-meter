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
        print("Credit balance decoding, recent pace, idle, recharge, gap and account isolation tests passed")
    }
}
