import Foundation

@main struct ReleaseInfoTests {
    static func main() async throws {
        final class Counter { var reads = 0 }
        struct Bytes: AsyncSequence, AsyncIteratorProtocol {
            typealias Element = UInt8
            var remaining: Int
            let counter: Counter
            func makeAsyncIterator() -> Self { self }
            mutating func next() async -> UInt8? {
                guard remaining > 0 else { return nil }
                remaining -= 1
                counter.reads += 1
                return 32
            }
        }
        let exact = try await ReleaseInfo.readBody(Bytes(remaining: ReleaseInfo.maximumBytes, counter: Counter()))
        precondition(exact.count == ReleaseInfo.maximumBytes)
        let counter = Counter()
        do {
            _ = try await ReleaseInfo.readBody(Bytes(remaining: ReleaseInfo.maximumBytes + 100, counter: counter))
            preconditionFailure("Oversized streams must fail before draining the response")
        } catch let error as URLError {
            precondition(error.code == .dataLengthExceedsMaximum)
            precondition(counter.reads == ReleaseInfo.maximumBytes + 1)
        }
        for invalid in ["", "1", "1.2", "1.2.3.4", "1..3", "1.2.3.", "01.2.3", "-1.2.3", "+1.2.3", "1.2.3-beta", "١.2.3", "1.2/../3", "99999999999999999999.2.3"] {
            precondition(ReleaseVersion(invalid) == nil, invalid)
        }
        precondition(ReleaseVersion("0.4.0")! > ReleaseVersion("0.3.3")!)
        precondition(ReleaseVersion("0.10.0")! > ReleaseVersion("0.9.9")!)
        precondition(ReleaseVersion("0.4.0")! == ReleaseVersion("0.4.0")!)
        func response(_ code: Int = 200, url: URL = ReleaseInfo.endpoint) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        }
        let valid = Data(#"{"tag_name":"v0.4.0","draft":false,"prerelease":false,"html_url":"https://untrusted.example"}"#.utf8)
        let release = try ReleaseInfo(data: valid, response: response())
        precondition(release.url.absoluteString == "https://github.com/emmepra/codex-meter/releases/tag/v0.4.0")
        for code in [301, 302, 404, 403, 429, 500] {
            precondition((try? ReleaseInfo(data: valid, response: response(code))) == nil)
        }
        precondition((try? ReleaseInfo(data: valid, response: response(url: URL(string: "https://untrusted.example")!))) == nil)
        for json in ["{}", "bad JSON", #"{"tag_name":"v0.4.0","draft":true,"prerelease":false}"#, #"{"tag_name":"v0.4.0","draft":false,"prerelease":true}"#, #"{"tag_name":"../../etc","draft":false,"prerelease":false}"#] {
            precondition((try? ReleaseInfo(data: Data(json.utf8), response: response())) == nil)
        }
        precondition((try? ReleaseInfo(data: Data(repeating: 32, count: 2_097_153), response: response())) == nil)
        var redirectRejected = false
        let policy = ReleaseRedirectPolicy()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: ReleaseInfo.endpoint)
        policy.urlSession(session, task: task, willPerformHTTPRedirection: response(302), newRequest: URLRequest(url: ReleaseInfo.repository)) { redirectRejected = $0 == nil }
        precondition(redirectRejected)
        session.invalidateAndCancel()
        print("Release version, response, URL and redirect tests passed")
    }
}
