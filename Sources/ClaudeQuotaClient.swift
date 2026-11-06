import Foundation
import Darwin

/// Uses the embedded CLI's experimental structured /usage request. Never sends a model turn.
struct ClaudeQuotaClient {
    enum ReadError: LocalizedError {
        case missingCLI, unavailable, invalidResponse, timeout

        var errorDescription: String? {
            switch self {
            case .missingCLI: return "Update Claude Desktop or connect a local Code session in Set Up Claude."
            case .unavailable: return "Claude Code could not read a subscription quota. Check its sign-in and connection."
            case .invalidResponse: return "Claude Code returned an unsupported quota response."
            case .timeout: return "Claude Code timed out while reading subscription usage."
            }
        }
    }

    // This version shipped the safe-mode and skip_behaviors combination verified with Desktop.
    static func read() async throws -> ClaudeUsage.Observation {
        let task = Task.detached(priority: .utility) {
            guard let executable = ClaudeDesktopBridge.desktopCLI(minimumVersion: "2.1.317") else {
                throw ReadError.missingCLI
            }
            return try run(executable: executable)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value },
                                                     onCancel: { task.cancel() })
    }

    static func run(executable: URL, timeout: TimeInterval = 20) throws -> ClaudeUsage.Observation {
        try Task.checkCancellation()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json",
                             "--verbose", "--safe-mode", "--no-session-persistence", "--tools", "",
                             "--permission-mode", "dontAsk"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let writer = input.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? writer.close()
            process.finishMeterRead()
            try? output.fileHandleForReading.close()
        }
        func send(_ id: String, _ request: [String: Any]) throws {
            let frame: [String: Any] = ["type": "control_request", "request_id": id, "request": request]
            try writer.write(contentsOf: JSONSerialization.data(withJSONObject: frame) + Data([10]))
        }

        try send("meter-init", ["subtype": "initialize"])
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fd = output.fileHandleForReading.fileDescriptor
        var buffer = Data(), bytes = [UInt8](repeating: 0, count: 16_384)
        var total = 0, expected = "meter-init"
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            guard ready > 0 else { throw ReadError.unavailable }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ReadError.unavailable }
            total += count
            guard total <= 2_097_152 else { throw ReadError.invalidResponse }
            buffer.append(contentsOf: bytes.prefix(count))
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                if line.isEmpty { continue }
                guard let frame = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw ReadError.invalidResponse
                }
                guard frame["type"] as? String == "control_response",
                      let reply = frame["response"] as? [String: Any],
                      reply["request_id"] as? String == expected else { continue }
                guard reply["subtype"] as? String == "success" else { throw ReadError.unavailable }
                if expected == "meter-init" {
                    expected = "meter-usage"
                    try send(expected, ["subtype": "get_usage", "skip_behaviors": true])
                } else {
                    guard let payload = reply["response"] as? [String: Any] else { throw ReadError.invalidResponse }
                    return try observation(from: payload)
                }
            }
        }
        throw ReadError.timeout
    }

    static func observation(from payload: [String: Any]) throws -> ClaudeUsage.Observation {
        guard let available = payload["rate_limits_available"] as? NSNumber,
              CFGetTypeID(available) == CFBooleanGetTypeID(), available.boolValue,
              let limits = payload["rate_limits"] as? [String: Any] else { throw ReadError.unavailable }
        func window(_ name: String) -> ClaudeUsage.Window? {
            guard let row = limits[name] as? [String: Any], let used = row["utilization"] as? NSNumber,
                  CFGetTypeID(used) != CFBooleanGetTypeID(), (0...100).contains(used.doubleValue) else { return nil }
            var reset: Date?
            if let iso = row["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                reset = formatter.date(from: iso)
                if reset == nil {
                    formatter.formatOptions.insert(.withFractionalSeconds)
                    reset = formatter.date(from: iso)
                }
            }
            return ClaudeUsage.Window(usedPercentage: used.doubleValue, resetsAt: reset?.timeIntervalSince1970)
        }
        let five = window("five_hour"), week = window("seven_day")
        guard five != nil || week != nil else { throw ReadError.unavailable }
        return try ClaudeUsage.observation(from: .init(schemaVersion: 1, observedAt: Date().timeIntervalSince1970,
                                                       fiveHour: five, sevenDay: week, source: .cli))
    }
}
