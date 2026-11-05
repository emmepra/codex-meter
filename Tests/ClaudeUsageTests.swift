import Foundation
import Darwin

@main
enum ClaudeUsageTests {
    static func main() throws {
        // A synthetic capture subprocess lets the test exercise the same file lock
        // between real processes. It never uses a default path or starts the app UI.
        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--fixture-capture" {
            do {
                _ = try ClaudeBridge.capture(input: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])),
                                             fileURL: URL(fileURLWithPath: CommandLine.arguments[2]),
                                             now: Date(timeIntervalSince1970: Double(CommandLine.arguments[4])!))
                exit(0)
            } catch ClaudeBridge.BridgeError.supersededCache { exit(3) }
            catch ClaudeBridge.BridgeError.captureBusy { exit(4) }
            catch { exit(1) }
        }
        func check(_ condition: Bool, _ message: String) { precondition(condition, message) }
        func rejects(_ operation: () throws -> Void, _ message: String) {
            do { try operation(); fatalError(message) } catch {}
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meter-claude-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("observations/claude-usage.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let full = Data(#"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1800000600},"seven_day":{"used_percentage":64.5,"resets_at":1800500000},"extra_usage":{"used_credits":200}},"transcript_path":"PRIVATE_TRANSCRIPT","session_id":"PRIVATE_SESSION","model":{"display_name":"PRIVATE_MODEL"}}"#.utf8)
        let output = try ClaudeBridge.capture(input: full, fileURL: file, now: now)
        let observation = try ClaudeUsage.read(fileURL: file, now: now)
        check(observation.observedAt == now, "Keep the capture time, not the read time")
        check(observation.source == nil && observation.checkedAt == nil, "Legacy captures have no Desktop freshness metadata")
        check(observation.snapshot.windows.count == 2, "Read both known quota windows")
        check(observation.snapshot.windows[0].id == "claude/primary", "Stable Claude window identity")
        check(observation.snapshot.windows[0].window.usedPercent == 0, "Zero quota usage is known")
        check(observation.snapshot.windows[0].window.windowDurationMins == 300, "Five-hour duration")
        check(observation.snapshot.windows[1].window.windowDurationMins == 10080, "Weekly duration")
        check(observation.snapshot.preferredEntry?.window.usedPercent == 64.5, "Reuse quota selection")
        check(observation.snapshot.availableResetCount == nil, "Never invent banked resets")
        check(output.contains("5h 0% used"), "Status line output describes used quota")
        let saved = try Data(contentsOf: file)
        let text = String(decoding: saved, as: UTF8.self)
        check(!text.contains("PRIVATE") && !text.contains("extra_usage"), "Persist only allowlisted quota fields")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        check(mode?.intValue == 0o600, "Snapshots are private before their atomic replacement")

        // A valid input without rate_limits must clear the previous account/session's quota.
        try ClaudeBridge.capture(input: Data(#"{"context_window":{"used_percentage":80}}"#.utf8), fileURL: file, now: now)
        check(try ClaudeUsage.read(fileURL: file, now: now).snapshot.windows.isEmpty, "Missing quota clears old windows")
        let badValues = Data(#"{"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":false},"seven_day":{"used_percentage":1000000000,"resets_at":-1}}}"#.utf8)
        try ClaudeBridge.capture(input: badValues, fileURL: file, now: now)
        let unknown = try ClaudeUsage.read(fileURL: file, now: now)
        check(unknown.snapshot.windows.allSatisfy { $0.window.usedPercent == nil && $0.window.resetsAt == nil }, "Boolean or invalid quota never becomes a number")
        rejects({ _ = try ClaudeBridge.capture(input: Data("[]".utf8), fileURL: file, now: now) }, "Reject a nonobject status line")
        rejects({ _ = try ClaudeBridge.capture(input: Data(repeating: 32, count: ClaudeUsage.maximumInputBytes + 1), fileURL: file, now: now) }, "Bound the producer's payload")
        rejects({ _ = try ClaudeUsage.decode(data: Data(#"{"schemaVersion":1,"observedAt":1800000061}"#.utf8), now: now) }, "Reject a capture more than one minute in the future")
        rejects({ _ = try ClaudeUsage.decode(data: Data(#"{"schemaVersion":2,"observedAt":1800000000}"#.utf8), now: now) }, "Reject unsupported schema")
        let old = try ClaudeUsage.decode(data: Data(#"{"schemaVersion":1,"observedAt":1799000000}"#.utf8), now: now)
        check(old.observedAt < now, "Retain age so the store can label old data")

        // Desktop polling has a separate local synchronization time. It must not
        // disguise an unchanged engine cache as a new quota observation.
        func desktopInput(_ marker: String?, used: Double = 64.5, reset: Double = 1_800_500_000,
                          expected: [String: Any]? = nil) throws -> Data {
            var payload: [String: Any] = [
                "rate_limits": ["seven_day": ["used_percentage": used, "resets_at": reset]],
                "source": "PRIVATE_UNTRUSTED_SOURCE", "checkedAt": 9_999_999_999,
                "observedAt": 9_999_999_999, "session_id": "PRIVATE_SESSION"
            ]
            if let marker { payload["meterSource"] = marker }
            if let expected { payload["meterExpectedLimits"] = expected }
            return try JSONSerialization.data(withJSONObject: payload)
        }
        func baseline(_ used: Double, reset: Double = 1_800_500_000) -> [String: Any] {
            ["seven_day": ["used_percentage": used, "resets_at": reset]]
        }
        try FileManager.default.removeItem(at: file)
        let initialTime = now.addingTimeInterval(100)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache"), fileURL: file, now: initialTime)
        let desktopInitial = try ClaudeUsage.read(fileURL: file, now: initialTime)
        check(desktopInitial.source == .desktop && desktopInitial.checkedAt == initialTime,
              "Only an allowlisted Desktop marker supplies local synchronization metadata")
        check(desktopInitial.observedAt == initialTime, "The first Desktop capture starts a new observation")
        let pollTime = initialTime.addingTimeInterval(1_000)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache"), fileURL: file, now: pollTime)
        let polled = try ClaudeUsage.read(fileURL: file, now: pollTime)
        check(polled.observedAt == initialTime && polled.checkedAt == pollTime,
              "An unchanged poll advances checkedAt while preserving the actual observation age")
        check(pollTime.timeIntervalSince(polled.observedAt) > 600, "A live bridge cannot fabricate a recent quota change")
        let changedTime = pollTime.addingTimeInterval(100)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 65, expected: baseline(64.5)), fileURL: file, now: changedTime)
        let changed = try ClaudeUsage.read(fileURL: file, now: changedTime)
        check(changed.observedAt == changedTime && changed.checkedAt == changedTime,
              "A changed normalized quota starts a new observation")
        let eventTime = changedTime.addingTimeInterval(100)
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 65), fileURL: file, now: eventTime)
        check(try ClaudeUsage.read(fileURL: file, now: eventTime).observedAt == eventTime,
              "An explicit measurement event refreshes the observation even when the percentage is unchanged")
        let resetTime = eventTime.addingTimeInterval(100)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 65, reset: 1_800_600_000,
                                                     expected: baseline(65)), fileURL: file, now: resetTime)
        check(try ClaudeUsage.read(fileURL: file, now: resetTime).observedAt == resetTime,
              "A reset-time change is part of the normalized fingerprint")
        let clearTime = resetTime.addingTimeInterval(100)
        let emptyDesktop = try JSONSerialization.data(withJSONObject: ["meterSource": "desktop-cache", "rate_limits": [:],
                                                                       "meterExpectedLimits": baseline(65, reset: 1_800_600_000)])
        try ClaudeBridge.capture(input: emptyDesktop, fileURL: file, now: clearTime)
        let cleared = try ClaudeUsage.read(fileURL: file, now: clearTime)
        check(cleared.snapshot.windows.isEmpty && cleared.observedAt == clearTime,
              "An authoritative empty poll clears earlier windows and records the change")
        try ClaudeBridge.capture(input: emptyDesktop, fileURL: file, now: clearTime.addingTimeInterval(60))
        check(try ClaudeUsage.read(fileURL: file, now: clearTime.addingTimeInterval(60)).observedAt == clearTime,
              "Repeated empty polls retain the original absence observation")
        let desktopBytes = try Data(contentsOf: file)
        let desktopJSON = try JSONSerialization.jsonObject(with: desktopBytes) as! [String: Any]
        check(Set(desktopJSON.keys) == ["schemaVersion", "observedAt", "source", "checkedAt"],
              "Persist only the allowlisted Desktop source and native timestamps")
        check(desktopJSON["source"] as? String == "desktop" && !String(decoding: desktopBytes, as: UTF8.self).contains("PRIVATE"),
              "Never persist the input marker, supplied timestamps, identity or arbitrary source labels")

        for marker: String? in [nil, "PRIVATE_UNKNOWN_MARKER"] {
            let legacyTime = clearTime.addingTimeInterval(200)
            try ClaudeBridge.capture(input: desktopInput(marker), fileURL: file, now: legacyTime)
            let legacy = try ClaudeUsage.read(fileURL: file, now: legacyTime)
            check(legacy.source == nil && legacy.checkedAt == nil && legacy.observedAt == legacyTime,
                  "Terminal and unknown markers retain legacy behavior and remove previous Desktop metadata")
        }
        let migratedTime = clearTime.addingTimeInterval(300)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache"), fileURL: file, now: migratedTime)
        check(try ClaudeUsage.read(fileURL: file, now: migratedTime).observedAt == migratedTime,
              "Do not inherit observation age from a prior terminal capture")

        for metadata in [
            #", "source":"PRIVATE_SOURCE""#,
            #", "source":true"#,
            #", "checkedAt":1800000000"#,
            #", "source":"desktop", "checkedAt":1799999999"#,
            #", "source":"desktop", "checkedAt":1800000061"#,
            #", "source":"desktop", "checkedAt":1e400"#,
            #", "source":"desktop", "checkedAt":true"#,
            #", "source":"desktop", "checkedAt":"1800000000""#
        ] {
            let json = #"{"schemaVersion":1,"observedAt":1800000000"# + metadata + "}"
            rejects({ _ = try ClaudeUsage.decode(data: Data(json.utf8), now: now) },
                    "Reject unknown source values, wrong timestamp types and invalid timestamp ordering")
        }
        let noCheck = try ClaudeUsage.decode(data: Data(#"{"schemaVersion":1,"observedAt":1800000000,"source":"desktop"}"#.utf8), now: now)
        check(noCheck.source == .desktop && noCheck.checkedAt == nil, "Optional check metadata remains backward compatible")
        let beforeFailure = try Data(contentsOf: file)
        rejects({ _ = try ClaudeBridge.capture(input: Data("invalid JSON".utf8), fileURL: file, now: migratedTime) },
                "Malformed producer input cannot replace a valid observation")
        rejects({ _ = try ClaudeBridge.capture(input: desktopInput("desktop-cache"), fileURL: file,
                                               now: Date(timeIntervalSince1970: .infinity)) }, "Reject a nonfinite local capture clock")
        check(try Data(contentsOf: file) == beforeFailure, "Failed capture preserves the last valid snapshot")

        // Clock corrections must not preserve an observation newer than this poll.
        let futureFile = directory.appendingPathComponent("future/claude-usage.json")
        try ClaudeBridge.capture(input: desktopInput("desktop-event"), fileURL: futureFile,
                                 now: now.addingTimeInterval(30))
        try ClaudeBridge.capture(input: desktopInput("desktop-cache"), fileURL: futureFile, now: now)
        let corrected = try ClaudeUsage.read(fileURL: futureFile, now: now)
        check(corrected.observedAt == now && corrected.checkedAt == now,
              "A backward clock adjustment cannot produce observedAt later than checkedAt")

        // Old cache polls from another session cannot roll back a newer event or
        // make their stale reading look freshly synchronized.
        let casFile = directory.appendingPathComponent("cas/claude-usage.json")
        let eventAt = now.addingTimeInterval(2_000)
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 97), fileURL: casFile, now: eventAt)
        let newerBytes = try Data(contentsOf: casFile)
        do {
            _ = try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 96, expected: baseline(96)),
                                         fileURL: casFile, now: eventAt.addingTimeInterval(60))
            fatalError("An older cache must lose its comparison")
        } catch ClaudeBridge.BridgeError.supersededCache {}
        check(try Data(contentsOf: casFile) == newerBytes, "Rejected cache leaves quota and both timestamps byte-for-byte unchanged")
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 97, expected: baseline(96)),
                                 fileURL: casFile, now: eventAt.addingTimeInterval(120))
        let converged = try ClaudeUsage.read(fileURL: casFile, now: eventAt.addingTimeInterval(120))
        check(converged.observedAt == eventAt && converged.checkedAt == eventAt.addingTimeInterval(120),
              "A converged reading can renew only the local synchronization time")
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 98, expected: baseline(97)),
                                 fileURL: casFile, now: eventAt.addingTimeInterval(180))
        check(try ClaudeUsage.read(fileURL: casFile, now: eventAt.addingTimeInterval(180)).snapshot.preferredEntry?.window.usedPercent == 98,
              "A matching baseline permits a changed cache value")
        let beforeEmpty = try Data(contentsOf: casFile)
        rejects({ _ = try ClaudeBridge.capture(input: Data(#"{"meterSource":"desktop-cache","rate_limits":{}}"#.utf8),
                                               fileURL: casFile, now: eventAt.addingTimeInterval(240)) },
                "A new session with no reading must not erase another session's quota")
        check(try Data(contentsOf: casFile) == beforeEmpty, "A rejected empty startup cannot renew checkedAt")
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 0, reset: 1_800_700_000),
                                 fileURL: casFile, now: eventAt.addingTimeInterval(300))
        check(try ClaudeUsage.read(fileURL: casFile, now: eventAt.addingTimeInterval(300)).snapshot.preferredEntry?.window.usedPercent == 0,
              "An authoritative event can report a legitimate reset, with no monotonic-percentage rule")
        let afterReset = try Data(contentsOf: casFile)
        rejects({ _ = try ClaudeBridge.capture(input: Data(#"{"meterSource":"desktop-cache","meterExpectedLimits":[],"rate_limits":{"seven_day":{"used_percentage":99,"resets_at":1800500000}}}"#.utf8),
                                               fileURL: casFile, now: eventAt.addingTimeInterval(360)) },
                "Malformed expected limits cannot authorize a different cache value")
        check(try Data(contentsOf: casFile) == afterReset, "Invalid comparison metadata is never written")
        check(!String(decoding: afterReset, as: UTF8.self).contains("meterExpectedLimits"), "Comparison baselines are input only")

        // A fresh plugin can recover a safely advancing reading without having
        // to publish a measurement event merely to establish its CAS baseline.
        let bootstrapFile = directory.appendingPathComponent("bootstrap/claude-usage.json")
        let bootstrapAt = now.addingTimeInterval(4_000)
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 96), fileURL: bootstrapFile, now: bootstrapAt)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 97), fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(10))
        check(try ClaudeUsage.read(fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(10)).snapshot.preferredEntry?.window.usedPercent == 97,
              "A new plugin may recover 97 from 96 without an existing local baseline")
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 98, expected: baseline(90)),
                                 fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(20))
        let bootstrapBytes = try Data(contentsOf: bootstrapFile)
        check(try ClaudeUsage.read(fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(20)).snapshot.preferredEntry?.window.usedPercent == 98,
              "A conservatively advancing whole snapshot can recover from a mismatched baseline")
        rejects({ _ = try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 96, expected: baseline(96)),
                                               fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(30)) },
                "An older session must not bootstrap a lower percentage into the same quota window")
        rejects({ _ = try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 99, reset: 1_800_500_600),
                                               fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(40)) },
                "Do not bootstrap a reset correction while the old reset is still in the future")
        check(try Data(contentsOf: bootstrapFile) == bootstrapBytes, "Rejected bootstrap leaves the whole snapshot and timestamps unchanged")
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 20, expected: baseline(98)),
                                 fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(50))
        check(try ClaudeUsage.read(fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(50)).snapshot.preferredEntry?.window.usedPercent == 20,
              "A matching CAS baseline can still deliver a legitimate decrease")
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 0), fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(60))
        check(try ClaudeUsage.read(fileURL: bootstrapFile, now: bootstrapAt.addingTimeInterval(60)).snapshot.preferredEntry?.window.usedPercent == 0,
              "A real measurement can report a banked reset even with the same scheduled reset time")

        let expiredFile = directory.appendingPathComponent("expired-bootstrap/claude-usage.json")
        let oldReset = bootstrapAt.timeIntervalSince1970 - 10
        let newReset = bootstrapAt.timeIntervalSince1970 + 3_600
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 90, reset: oldReset), fileURL: expiredFile, now: bootstrapAt)
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 91, reset: oldReset), fileURL: expiredFile, now: bootstrapAt)
        check(try ClaudeUsage.read(fileURL: expiredFile, now: bootstrapAt).snapshot.preferredEntry?.window.usedPercent == 91,
              "Comparable consumption can advance in the same expired window without synthesizing a reset")
        try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 3, reset: newReset), fileURL: expiredFile, now: bootstrapAt)
        let newWindow = try ClaudeUsage.read(fileURL: expiredFile, now: bootstrapAt).snapshot.preferredEntry?.window
        check(newWindow?.usedPercent == 3 && newWindow?.resetsAt == newReset,
              "An expired window can bootstrap a valid later future reset with lower consumption")

        let completeFile = directory.appendingPathComponent("complete-bootstrap/claude-usage.json")
        let bothWindows: [String: Any] = [
            "five_hour": ["used_percentage": 25, "resets_at": newReset],
            "seven_day": ["used_percentage": 96, "resets_at": 1_800_500_000]
        ]
        try ClaudeBridge.capture(input: JSONSerialization.data(withJSONObject: ["meterSource": "desktop-event", "rate_limits": bothWindows]),
                                 fileURL: completeFile, now: bootstrapAt)
        let completeBytes = try Data(contentsOf: completeFile)
        rejects({ _ = try ClaudeBridge.capture(input: desktopInput("desktop-cache", used: 97), fileURL: completeFile, now: bootstrapAt) },
                "One advancing window must not bootstrap a whole snapshot that drops another known window")
        check(try Data(contentsOf: completeFile) == completeBytes, "Never synthesize a merge or partially accept a bootstrap snapshot")
        var addedWindows = bothWindows
        addedWindows["seven_day"] = ["used_percentage": 3, "resets_at": newReset]
        try ClaudeBridge.capture(input: JSONSerialization.data(withJSONObject: ["meterSource": "desktop-cache", "rate_limits": addedWindows]),
                                 fileURL: expiredFile, now: bootstrapAt)
        check(try ClaudeUsage.read(fileURL: expiredFile, now: bootstrapAt).snapshot.windows.count == 2,
              "A previously missing window can bootstrap when its usage and future reset are valid and other windows are unchanged")

        // Hold the same lock while starting an event and an old cached poll. Both
        // children must wait; whichever obtains the lock first, the event wins.
        let contentionFile = directory.appendingPathComponent("contention/claude-usage.json")
        let contentionNow = now.addingTimeInterval(3_000)
        try ClaudeBridge.capture(input: desktopInput("desktop-event", used: 96), fileURL: contentionFile, now: contentionNow)
        let lock = contentionFile.deletingLastPathComponent().appendingPathComponent(".claude-usage.lock")
        let held = open(lock.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        check(held >= 0 && flock(held, LOCK_EX) == 0, "Acquire the real capture lock for the contention fixture")
        var lockHeld = true
        defer { if lockHeld { _ = flock(held, LOCK_UN) }; close(held) }
        let lockMode = try FileManager.default.attributesOfItem(atPath: lock.path)[.posixPermissions] as? NSNumber
        check(lockMode?.intValue == 0o600, "The sibling capture lock is private")
        func child(_ name: String, input: Data) throws -> Process {
            let payload = directory.appendingPathComponent(name + ".json")
            try input.write(to: payload)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["--fixture-capture", contentionFile.path, payload.path, String(contentionNow.timeIntervalSince1970)]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        let eventChild = try child("event-child", input: desktopInput("desktop-event", used: 97))
        let oldCacheChild = try child("cache-child", input: desktopInput("desktop-cache", used: 96, expected: baseline(96)))
        let beforeContention = try Data(contentsOf: contentionFile)
        usleep(150_000)
        check(eventChild.isRunning && oldCacheChild.isRunning, "Separate event and cache processes must both honor the held lock")
        check(try Data(contentsOf: contentionFile) == beforeContention, "No writer can replace the snapshot before obtaining its lock")
        _ = flock(held, LOCK_UN)
        lockHeld = false
        for process in [eventChild, oldCacheChild] {
            let deadline = ProcessInfo.processInfo.systemUptime + 4
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit(); fatalError("Fixture capture did not finish") }
            process.waitUntilExit()
        }
        check(eventChild.terminationStatus == 0 && [Int32(0), Int32(3)].contains(oldCacheChild.terminationStatus),
              "The event succeeds; the old cache either precedes it or loses the comparison")
        check(try ClaudeUsage.read(fileURL: contentionFile, now: contentionNow).snapshot.preferredEntry?.window.usedPercent == 97,
              "A real two-process race cannot roll the newer event back to the old cached percentage")
        check(flock(held, LOCK_EX) == 0, "Reacquire the fixture lock to exercise bounded waiting")
        lockHeld = true
        let beforeTimeout = try Data(contentsOf: contentionFile)
        let blocked = try child("blocked-child", input: desktopInput("desktop-event", used: 98))
        let timeoutDeadline = ProcessInfo.processInfo.systemUptime + 3
        while blocked.isRunning && ProcessInfo.processInfo.systemUptime < timeoutDeadline { usleep(10_000) }
        if blocked.isRunning { kill(blocked.processIdentifier, SIGKILL); blocked.waitUntilExit(); fatalError("Capture lock wait exceeded its bound") }
        blocked.waitUntilExit()
        check(blocked.terminationStatus == 4, "A blocked writer must return captureBusy inside the capture process timeout")
        check(try Data(contentsOf: contentionFile) == beforeTimeout, "Lock contention must not alter a snapshot")
        _ = flock(held, LOCK_UN)
        lockHeld = false

        let linkedCapture = directory.appendingPathComponent("linked-lock/claude-usage.json")
        try FileManager.default.createDirectory(at: linkedCapture.deletingLastPathComponent(), withIntermediateDirectories: true)
        let unrelatedLockTarget = directory.appendingPathComponent("unrelated-lock-target")
        let unrelatedBytes = Data("synthetic unrelated file".utf8)
        try unrelatedBytes.write(to: unrelatedLockTarget)
        try FileManager.default.createSymbolicLink(at: linkedCapture.deletingLastPathComponent().appendingPathComponent(".claude-usage.lock"),
                                                  withDestinationURL: unrelatedLockTarget)
        rejects({ _ = try ClaudeBridge.capture(input: desktopInput("desktop-event"), fileURL: linkedCapture, now: now) },
                "Never acquire a lock through a symbolic link")
        check(try Data(contentsOf: unrelatedLockTarget) == unrelatedBytes && !FileManager.default.fileExists(atPath: linkedCapture.path),
              "Refusing a linked lock preserves its target and creates no observation")

        let settings = directory.appendingPathComponent("claude/settings.json")
        let executable = URL(fileURLWithPath: "/Applications/Example's Meter.app/Contents/MacOS/CodexMeter")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"permissions":{"allow":["Read"]},"env":{"EXAMPLE":"preserve"},"theme":"dark"}"#.utf8)
        try original.write(to: settings)
        let backup = try ClaudeBridge.install(executableURL: executable, settingsURL: settings)
        check(backup != nil, "Back up existing settings")
        check(try Data(contentsOf: backup!) == original, "Backup preserves the exact original bytes")
        let updated = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        check(updated["theme"] as? String == "dark", "Preserve other settings")
        check((updated["permissions"] as? [String: Any])?["allow"] as? [String] == ["Read"], "Preserve nested configuration")
        let statusLine = updated["statusLine"] as! [String: Any]
        check(statusLine["command"] as? String == ClaudeBridge.shellQuoted(executable.path) + " --capture-claude-usage", "Quote paths safely for the shell")
        let configured = try Data(contentsOf: settings)
        check(try ClaudeBridge.install(executableURL: executable, settingsURL: settings) == nil, "Repeated setup is idempotent")
        check(try Data(contentsOf: settings) == configured, "Idempotent setup does not rewrite settings")
        let moved = URL(fileURLWithPath: "/Applications/Codex Meter.app/Contents/MacOS/CodexMeter")
        _ = try ClaudeBridge.install(executableURL: moved, settingsURL: settings)
        let conflicting = Data(#"{"statusLine":{"type":"command","command":"existing-custom-statusline"},"theme":"dark"}"#.utf8)
        try conflicting.write(to: settings)
        rejects({ _ = try ClaudeBridge.install(executableURL: moved, settingsURL: settings) }, "Never replace the user's existing status line")
        check(try Data(contentsOf: settings) == conflicting, "Conflicting configuration is unchanged")
        try Data("invalid JSON".utf8).write(to: settings)
        rejects({ _ = try ClaudeBridge.install(executableURL: moved, settingsURL: settings) }, "Refuse malformed existing settings")
        let linked = directory.appendingPathComponent("linked-settings.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: settings)
        rejects({ _ = try ClaudeBridge.install(executableURL: moved, settingsURL: linked) }, "Refuse a symbolic-link settings destination")
        let fresh = directory.appendingPathComponent("fresh/settings.json")
        check(try ClaudeBridge.install(executableURL: moved, settingsURL: fresh) == nil, "First installation creates settings without a backup")
        let freshMode = try FileManager.default.attributesOfItem(atPath: fresh.path)[.posixPermissions] as? NSNumber
        check(freshMode?.intValue == 0o600, "Configuration is written privately")
        print("Claude usage and bridge tests passed")
    }
}
