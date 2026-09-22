import Foundation

@main
enum UsageSnapshotTests {
    static func main() throws {
        func read(_ json: String) throws -> UsageSnapshot { try UsageSnapshot(data: Data(json.utf8)) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        func rejects(_ json: String) {
            do { _ = try read(json); fatalError("Accepted malformed payload: \(json)") } catch {}
        }

        let mapped = try read(#"{"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":10080}}}}}"#)
        check(mapped.windows.count == 1, "Map must not duplicate legacy usage")
        check(mapped.preferredEntry?.window.usedPercent == 12, "Map must override legacy")
        check(mapped.preferredEntry?.window.label == "Settimana", "Primary can be weekly")
        let empty = try read(#"{"rateLimitsByLimitId":{},"rateLimits":{"primary":{"usedPercent":99}}}"#)
        check(empty.windows.isEmpty, "Empty map is authoritative")
        let divergent = try read(#"{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":8}}},"rateLimits":"obsolete"}"#)
        check(divergent.preferredEntry?.window.usedPercent == 8, "Ignore malformed obsolete legacy when map exists")

        for prefix in ["", #""rateLimitsByLimitId":null,"#] {
            let legacy = try read("{" + prefix + #""rateLimits":{"primary":{"usedPercent":15,"windowDurationMins":300},"secondary":{"usedPercent":70,"windowDurationMins":10080}}}"#)
            check(legacy.windows.count == 2, "Legacy should expose both windows")
            check(legacy.windows[0].window.label == "5 ore", "Five-hour label")
            check(legacy.preferredEntry?.id == "codex/secondary", "Choose highest known consumption")
        }
        let unknown = try read(#"{"rateLimits":{"primary":{"resetsAt":1800000000},"secondary":{"usedPercent":0}}}"#)
        check(unknown.windows[0].window.usedPercent == nil, "Missing consumption is not zero")
        check(unknown.windows[1].window.usedPercent == 0, "Explicit zero remains known")
        check(unknown.preferredEntry?.id == "codex/secondary", "Known zero beats unknown")
        check(unknown.windows[0].window.label == "Periodo non specificato", "Never infer missing duration")
        let clamped = try read(#"{"rateLimits":{"primary":{"usedPercent":-4},"secondary":{"usedPercent":123}}}"#)
        check(clamped.windows[0].window.usedPercent == 0, "Clamp negative usage")
        check(clamped.windows[1].window.usedPercent == 100, "Clamp excessive usage")
        check(RateLimitWindow(usedPercent: .infinity, windowDurationMins: 60, resetsAt: nil).usedPercent == nil, "Nonfinite usage is unknown")
        check(RateLimitWindow(usedPercent: .nan, windowDurationMins: 90, resetsAt: nil).label == "90 minuti", "Report actual duration")

        let additional = try read(#"{"rateLimitsByLimitId":{"zeta":{"primary":{"usedPercent":100}},"codex":{"limitId":"wrong","limitName":"Codex","primary":{"usedPercent":5},"secondary":{"usedPercent":5}},"alpha":{"primary":{"usedPercent":80}}}}"#)
        check(additional.buckets.map(\.limitId) == ["codex", "alpha", "zeta"], "Stable bucket order, keys authoritative")
        check(additional.windows.count == 4, "Preserve additional buckets")
        check(Set(additional.windows.map(\.id)).count == 4, "Stable unique window IDs")
        check(additional.preferredEntry?.id == "codex/primary", "Codex first; primary wins ties")
        let other = try read(#"{"rateLimitsByLimitId":{"zeta":{"primary":{"usedPercent":100}},"alpha":{"primary":{"usedPercent":20},"secondary":{"usedPercent":80}}}}"#)
        check(other.preferredEntry?.id == "alpha/secondary", "Without Codex choose first bucket highest usage")
        let emptyCodex = try read(#"{"rateLimitsByLimitId":{"codex":{"primary":null,"secondary":null},"alpha":{},"zeta":{"primary":{"usedPercent":30},"secondary":{"usedPercent":80}}}}"#)
        check(emptyCodex.preferredEntry?.id == "zeta/secondary", "Skip buckets without windows so available limits remain accessible")
        let unavailable = try read(#"{"rateLimits":null}"#)
        check(unavailable.preferredEntry == nil, "No usage yields no preferred entry")

        for json in ["not json", "[]", "{}", #"{"result":null}"#, #"{"error":{"message":"Unauthorized"}}"#,
                     #"{"rateLimitsByLimitId":[]}"#, #"{"rateLimits":{"primary":{"usedPercent":"12"}}}"#] {
            rejects(json)
        }
        print("UsageSnapshot tests passed")
    }
}
