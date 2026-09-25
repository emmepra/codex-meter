import Foundation
import Darwin

/// Offline checks for the subprocess boundary; never contacts Codex or reads account data.
/// From the project root: swiftc -swift-version 5 Sources/CodexClient.swift Tests/CodexClientTests.swift -o /tmp/codex-client-tests
/// Run the resulting /tmp/codex-client-tests executable (or scripts/test.sh).
@main struct CodexClientTests {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("codex-meter-client-tests-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let fixture = root.appendingPathComponent("fake-codex")
        let modeURL = root.appendingPathComponent("fake.mode")
        let pidURL = root.appendingPathComponent("fake.pid")
        let script = #"""
        #!/bin/sh
        task_dir=${0%/*}
        printf '%s' "$$" > "$task_dir/fake.pid"
        task_mode=$(/bin/cat "$task_dir/fake.mode")
        case "$task_mode" in
          timeout) trap '' TERM; exec /bin/sleep 30 ;;
          disconnect) exit 0 ;;
        esac
        while IFS= read -r task_request; do
          case "$task_request" in
            *'"initialize"'*) printf '%s\n' '{"id":1,"result":{}}' ;;
            *'rateLimits'*)
              case "$task_mode" in
                error) printf '%s\n' '{"id":2,"error":{"code":-1,"message":"not authenticated"}}' ;;
                malformed) printf '%s\n' 'unexpected text' ;;
                *) printf '%s\n' '{"method":"irrelevant","params":{}}' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":32}},"rateLimitResetCredits":{"availableCount":2}}}' ;;
              esac
              ;;
          esac
        done
        """#
        try script.write(to: fixture, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)

        func setMode(_ value: String) throws {
            try? manager.removeItem(at: pidURL)
            try value.write(to: modeURL, atomically: true, encoding: .utf8)
        }
        func assertStopped(allowNeverStarted: Bool = false) throws {
            if allowNeverStarted && !manager.fileExists(atPath: pidURL.path) { return }
            let pidString = try String(contentsOf: pidURL, encoding: .utf8)
            guard let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                fatalError("Fixture did not save a process ID")
            }
            precondition(kill(pid, 0) != 0, "Child process still alive")
        }

        for scenario in ["ok", "error", "malformed", "disconnect", "timeout"] {
            try setMode(scenario)
            do {
                let data = try await CodexClient(executableURL: fixture, timeout: 0.7).readLimits()
                precondition(scenario == "ok", "Unexpected success for \(scenario)")
                let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let limits = object["rateLimits"] as! [String: Any]
                let primary = limits["primary"] as! [String: Any]
                precondition(primary["usedPercent"] as? Int == 32)
                let resets = object["rateLimitResetCredits"] as! [String: Any]
                precondition(resets["availableCount"] as? Int == 2, "Transport preserves reset metadata")
            } catch let error as CodexClientError {
                switch (scenario, error) {
                case ("error", .loginRequired), ("malformed", .invalidResponse),
                     ("disconnect", .disconnected), ("timeout", .timeout): break
                default: fatalError("Wrong error for \(scenario): \(error)")
                }
            }
            try assertStopped()
            print("PASS client \(scenario); child stopped")
        }

        try setMode("timeout")
        let task = Task { try await CodexClient(executableURL: fixture).readLimits() }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do { _ = try await task.value; fatalError("Cancellation returned success") }
        catch is CancellationError { }
        try assertStopped(allowNeverStarted: true)
        print("PASS client cancellation; child stopped")
    }
}
