import Foundation

struct RateLimitWindow: Codable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?

    init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt.flatMap { $0.isFinite ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey { case usedPercent, windowDurationMins, resetsAt }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(usedPercent: try values.decodeIfPresent(Double.self, forKey: .usedPercent),
                  windowDurationMins: try values.decodeIfPresent(Int.self, forKey: .windowDurationMins),
                  resetsAt: try values.decodeIfPresent(Double.self, forKey: .resetsAt))
    }

    var label: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "Unspecified period" }
        if minutes == 300 { return "5 hours" }
        if minutes == 10080 { return "Week" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) \(minutes == 1440 ? "day" : "days")" }
        if minutes % 60 == 0 { return "\(minutes / 60) \(minutes == 60 ? "hour" : "hours")" }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}

struct RateLimitBucket: Codable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    fileprivate func identified(by id: String) -> RateLimitBucket {
        RateLimitBucket(limitId: id, limitName: limitName, planType: planType,
                        primary: primary, secondary: secondary)
    }
}

struct UsageEntry: Identifiable {
    let id: String
    let bucketId: String
    let bucketName: String
    let window: RateLimitWindow
}

struct UsageSnapshot {
    let buckets: [RateLimitBucket]

    init(data: Data) throws {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let map = response.payload.map {
            buckets = map.keys.sorted {
                if $0 == "codex" { return $1 != "codex" }
                if $1 == "codex" { return false }
                return $0 < $1
            }.map { map[$0]!.identified(by: $0) }
        } else if let legacy = response.payload.legacy {
            buckets = [legacy.identified(by: legacy.limitId ?? "codex")]
        } else {
            buckets = []
        }
    }

    var windows: [UsageEntry] {
        buckets.flatMap { bucket in
            let id = bucket.limitId ?? "codex"
            let name = bucket.limitName?.isEmpty == false ? bucket.limitName! : (id == "codex" ? "Codex" : id)
            return [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, window in
                window.map { UsageEntry(id: "\(id)/\(slot)", bucketId: id, bucketName: name, window: $0) }
            }
        }
    }

    var preferredEntry: UsageEntry? {
        let available = windows
        guard let bucketId = available.first?.bucketId else { return nil }
        let candidates = available.filter { $0.bucketId == bucketId }
        // Preserve primary/secondary order on ties; missing usage stays unknown.
        return candidates.reduce(nil as UsageEntry?) { best, next in
            guard let best else { return next }
            guard let nextUsage = next.window.usedPercent else { return best }
            guard let bestUsage = best.window.usedPercent else { return next }
            return nextUsage > bestUsage ? next : best
        }
    }

    private struct Response: Decodable {
        let payload: Payload
        private enum CodingKeys: String, CodingKey { case result }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            payload = container.contains(.result)
                ? try container.decode(Payload.self, forKey: .result)
                : try Payload(from: decoder)
        }
    }

    private struct Payload: Decodable {
        let map: [String: RateLimitBucket]?
        let legacy: RateLimitBucket?
        private enum CodingKeys: String, CodingKey { case rateLimitsByLimitId, rateLimits }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.rateLimitsByLimitId) || container.contains(.rateLimits) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                    debugDescription: "The response does not contain usage limits."))
            }
            map = try container.decodeIfPresent([String: RateLimitBucket].self, forKey: .rateLimitsByLimitId)
            // The map, including an empty map, is authoritative when supplied.
            legacy = map == nil ? try container.decodeIfPresent(RateLimitBucket.self, forKey: .rateLimits) : nil
        }
    }
}
