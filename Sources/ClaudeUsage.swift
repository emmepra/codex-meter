import Foundation

/// A small, sanitized observation from Claude Code's documented statusLine input.
/// `observedAt` records receipt by the bridge, not a guaranteed server refresh.
enum ClaudeUsage {
    static let maximumInputBytes = 256 * 1024
    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Codex Meter", isDirectory: true)
        .appendingPathComponent("claude-usage.json")

    struct Observation {
        let snapshot: UsageSnapshot
        let observedAt: Date
    }

    struct Window: Codable {
        let usedPercentage: Double?
        let resetsAt: Double?

        init(usedPercentage: Double?, resetsAt: Double?) {
            self.usedPercentage = usedPercentage.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
            self.resetsAt = resetsAt.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        }

        private enum CodingKeys: String, CodingKey { case usedPercentage, resetsAt }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(usedPercentage: try? values.decode(Double.self, forKey: .usedPercentage),
                      resetsAt: try? values.decode(Double.self, forKey: .resetsAt))
        }
    }

    struct StoredObservation: Codable {
        let schemaVersion: Int
        let observedAt: Double
        let fiveHour: Window?
        let sevenDay: Window?
    }

    enum ReadError: LocalizedError {
        case invalidObservation
        case oversizedInput

        var errorDescription: String? {
            switch self {
            case .invalidObservation: return "The Claude Code observation is invalid. Use the bridge again from Claude Code."
            case .oversizedInput: return "The Claude Code status line input is too large."
            }
        }
    }

    static func read(fileURL: URL = defaultFileURL, now: Date = Date()) throws -> Observation {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumInputBytes + 1) ?? Data()
        guard data.count <= maximumInputBytes else { throw ReadError.oversizedInput }
        return try decode(data: data, now: now)
    }

    static func decode(data: Data, now: Date = Date()) throws -> Observation {
        guard data.count <= maximumInputBytes else { throw ReadError.oversizedInput }
        let stored = try JSONDecoder().decode(StoredObservation.self, from: data)
        guard stored.schemaVersion == 1, stored.observedAt.isFinite,
              stored.observedAt > 0, stored.observedAt <= now.timeIntervalSince1970 + 60 else {
            throw ReadError.invalidObservation
        }

        func normalized(_ window: Window?, minutes: Int) -> [String: Any]? {
            guard let window else { return nil }
            var value: [String: Any] = ["windowDurationMins": minutes]
            if let usage = window.usedPercentage { value["usedPercent"] = usage }
            if let reset = window.resetsAt { value["resetsAt"] = reset }
            return value
        }
        var bucket: [String: Any] = ["limitName": "Claude"]
        if let primary = normalized(stored.fiveHour, minutes: 300) { bucket["primary"] = primary }
        if let secondary = normalized(stored.sevenDay, minutes: 10080) { bucket["secondary"] = secondary }
        let normalizedData = try JSONSerialization.data(withJSONObject: ["rateLimitsByLimitId": ["claude": bucket]])
        return Observation(snapshot: try UsageSnapshot(data: normalizedData),
                           observedAt: Date(timeIntervalSince1970: stored.observedAt))
    }
}
