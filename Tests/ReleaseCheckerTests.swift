import Foundation

@main struct ReleaseCheckerTests {
    @MainActor static func main() async throws {
        let name = "CodexMeterTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: name)!
        defer { preferences.removePersistentDomain(forName: name) }
        func release(_ version: String) throws -> ReleaseInfo {
            let data = Data("{\"tag_name\":\"v\(version)\",\"draft\":false,\"prerelease\":false}".utf8)
            let response = HTTPURLResponse(url: ReleaseInfo.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return try ReleaseInfo(data: data, response: response)
        }
        var calls = 0
        var changes = 0
        var latest = "0.5.0"
        var fail = false
        let checker = ReleaseChecker(preferences: preferences, installed: "0.4.0") {
            calls += 1
            if fail { throw URLError(.notConnectedToInternet) }
            return try release(latest)
        }
        checker.onChange = { changes += 1 }
        func finish() async throws {
            let deadline = Date().addingTimeInterval(5)
            while checker.checking && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
            precondition(!checker.checking)
        }
        precondition(checker.automaticChecks)
        checker.check(automatically: true)
        checker.check(automatically: true)
        try await finish()
        precondition(calls == 1 && changes == 1)
        precondition(checker.availableRelease?.version.text == "0.5.0")
        fail = true
        checker.check(automatically: true)
        try await finish()
        precondition(checker.availableRelease?.version.text == "0.5.0", "Offline failure must retain known update")
        fail = false
        latest = "0.4.0"
        checker.check(automatically: true)
        try await finish()
        precondition(checker.availableRelease == nil)
        latest = "0.3.3"
        checker.check(automatically: true)
        try await finish()
        precondition(checker.availableRelease == nil)
        checker.automaticChecks = false
        precondition(preferences.bool(forKey: "automaticUpdateChecks") == false)
        let before = calls
        checker.start()
        try await finish()
        precondition(calls == before, "Disabled automatic checks must not start a network operation")
        checker.stop()
        print("Silent update checks, deduplication, failures, version changes and preferences passed")
    }
}
