import Foundation

@main
enum ClaudeUsageTests {
    static func main() throws {
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
