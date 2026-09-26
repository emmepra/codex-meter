import Foundation

struct ReleaseVersion: Comparable {
    let components: [Int]
    let text: String

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9,
                  part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  part.count == 1 || part.first != "0", let value = Int(part) else { return nil }
            values.append(value)
        }
        components = values
        self.text = text
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct ReleaseInfo {
    static let maximumBytes = 2_097_152
    static let repository = URL(string: "https://github.com/emmepra/codex-meter")!
    static let endpoint = URL(string: "https://api.github.com/repos/emmepra/codex-meter/releases/latest")!
    let version: ReleaseVersion
    let url: URL

    init(data: Data, response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == Self.endpoint, data.count <= Self.maximumBytes else { throw URLError(.badServerResponse) }
        struct Payload: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let text = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        guard !payload.draft, !payload.prerelease, let version = ReleaseVersion(text) else {
            throw URLError(.cannotParseResponse)
        }
        self.version = version
        // Never trust response-supplied links, executable paths, or release body HTML.
        url = Self.repository.appendingPathComponent("releases/tag").appendingPathComponent(payload.tag_name)
    }

    static func readBody<Bytes: AsyncSequence>(_ bytes: Bytes) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

final class ReleaseRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
