import Foundation
import Darwin

@main struct ClaudeQuotaClientTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("fake-claude")
        let fixture = #"""
        #!/bin/sh
        set -eu
        test "$*" = "-p --input-format stream-json --output-format stream-json --verbose --safe-mode --no-session-persistence --tools  --permission-mode dontAsk"
        IFS= read -r init
        case "$init" in *'"initialize"'*) ;; *) exit 2 ;; esac
        printf '%s\n' '{"type":"control_response","response":{"request_id":"meter-init","subtype":"success","response":{}}}'
        IFS= read -r usage
        case "$usage" in *'"skip_behaviors":true'*) ;; *) exit 3 ;; esac
        case "$usage" in *'"get_usage"'*) ;; *) exit 4 ;; esac
        printf '%s\n' '{"type":"control_response","response":{"request_id":"meter-usage","subtype":"success","response":{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":25,"resets_at":"2030-01-02T03:04:05.123456Z"}}}}}'
        """#
        try fixture.write(to: cli, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let result = try ClaudeQuotaClient.run(executable: cli, timeout: 3)
        precondition(result.source == .cli && result.checkedAt == nil)
        let windows = result.snapshot.windows
        precondition(windows.count == 2)
        precondition(windows.first { $0.window.windowDurationMins == 300 }?.window.usedPercent == 0)
        precondition(windows.first { $0.window.windowDurationMins == 10080 }?.window.resetsAt != nil)
        for payload: [String: Any] in [
            ["rate_limits_available": false],
            ["rate_limits_available": true, "rate_limits": ["five_hour": ["utilization": true]]],
            ["rate_limits_available": true, "rate_limits": ["seven_day": ["utilization": -1]]]
        ] {
            do { _ = try ClaudeQuotaClient.observation(from: payload); fatalError("Invalid reading accepted") }
            catch ClaudeQuotaClient.ReadError.unavailable {}
        }
        let pidFile = root.appendingPathComponent("pid")
        try "#!/bin/sh\necho $$ > \"\(pidFile.path)\"\nexec /bin/sleep 15\n".write(to: cli, atomically: false, encoding: .utf8)
        do { _ = try ClaudeQuotaClient.run(executable: cli, timeout: 0.3); fatalError("Timeout expected") }
        catch ClaudeQuotaClient.ReadError.timeout {}
        let pid = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(kill(Int32(pid)!, 0) == -1 && errno == ESRCH)
        print("Claude independent quota, missing limits, zero usage and timeout cleanup passed")
    }
}
