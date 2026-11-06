import Foundation

/// Sanitized quota observations from Claude Code's documented local interfaces.
/// Desktop cache checks can advance `checkedAt` without renewing `observedAt`.
/// Neither timestamp guarantees a new server measurement.
enum ClaudeUsage {
    static let maximumInputBytes = 256 * 1024
    static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Codex Meter", isDirectory: true)
        .appendingPathComponent("claude-usage.json")

    enum Source: String, Codable { case desktop, cli }

    struct Observation {
        let snapshot: UsageSnapshot
        let observedAt: Date
        let source: Source?
        let checkedAt: Date?
    }

    struct Window: Codable, Equatable {
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
        let source: Source?
        let checkedAt: Double?

        init(schemaVersion: Int, observedAt: Double, fiveHour: Window?, sevenDay: Window?,
             source: Source? = nil, checkedAt: Double? = nil) {
            self.schemaVersion = schemaVersion
            self.observedAt = observedAt
            self.fiveHour = fiveHour
            self.sevenDay = sevenDay
            self.source = source
            self.checkedAt = checkedAt
        }
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
        try observation(from: readStored(fileURL: fileURL, now: now))
    }

    /// Shared with capture so unchanged desktop cache polls retain their quota age.
    static func readStored(fileURL: URL, now: Date) throws -> StoredObservation {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumInputBytes + 1) ?? Data()
        guard data.count <= maximumInputBytes else { throw ReadError.oversizedInput }
        return try decodeStored(data: data, now: now)
    }

    static func decode(data: Data, now: Date = Date()) throws -> Observation {
        try observation(from: decodeStored(data: data, now: now))
    }

    private static func decodeStored(data: Data, now: Date) throws -> StoredObservation {
        guard data.count <= maximumInputBytes else { throw ReadError.oversizedInput }
        let stored = try JSONDecoder().decode(StoredObservation.self, from: data)
        guard now.timeIntervalSince1970.isFinite,
              stored.schemaVersion == 1, stored.observedAt.isFinite,
              stored.observedAt > 0, stored.observedAt <= now.timeIntervalSince1970 + 60 else {
            throw ReadError.invalidObservation
        }
        if let checkedAt = stored.checkedAt {
            guard stored.source == .desktop, checkedAt.isFinite, checkedAt > 0,
                  checkedAt >= stored.observedAt, checkedAt <= now.timeIntervalSince1970 + 60 else {
                throw ReadError.invalidObservation
            }
        }
        return stored
    }

    static func observation(from stored: StoredObservation) throws -> Observation {
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
                           observedAt: Date(timeIntervalSince1970: stored.observedAt),
                           source: stored.source,
                           checkedAt: stored.checkedAt.map { Date(timeIntervalSince1970: $0) })
    }
}
