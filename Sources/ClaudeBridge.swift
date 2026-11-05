import Foundation
import Darwin

enum ClaudeBridge {
    static let defaultSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude", isDirectory: true).appendingPathComponent("settings.json")

    enum BridgeError: LocalizedError {
        case invalidInput
        case invalidSettings
        case existingStatusLine
        case unsafePath
        case settingsChanged
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidInput: return "Claude Code did not provide a JSON status line object."
            case .invalidSettings: return "Claude settings are not a valid JSON object; they were left unchanged."
            case .existingStatusLine:
                return "Claude Code already has a status line. Keep it and compose a wrapper that sends the same stdin to CodexMeter --capture-claude-usage and your existing command. Settings were left unchanged."
            case .unsafePath: return "The bridge cannot write through a symbolic link or an invalid file path."
            case .settingsChanged: return "Claude settings changed during setup. Try setup again."
            case .writeFailed: return "The bridge could not safely save its local file."
            }
        }
    }

    /// Run only when Claude Code invokes the explicitly configured command.
    /// Bound stdin so an unexpected producer cannot exhaust the app's memory.
    static func captureStandardInput(fileURL: URL = ClaudeUsage.defaultFileURL, now: Date = Date()) throws -> String {
        var input = Data()
        while input.count <= ClaudeUsage.maximumInputBytes {
            let remaining = ClaudeUsage.maximumInputBytes + 1 - input.count
            guard let part = try FileHandle.standardInput.read(upToCount: min(16 * 1024, remaining)), !part.isEmpty else { break }
            input.append(part)
        }
        return try capture(input: input, fileURL: fileURL, now: now)
    }

    @discardableResult
    static func capture(input: Data, fileURL: URL = ClaudeUsage.defaultFileURL, now: Date = Date()) throws -> String {
        guard input.count <= ClaudeUsage.maximumInputBytes else { throw ClaudeUsage.ReadError.oversizedInput }
        guard let root = try JSONSerialization.jsonObject(with: input) as? [String: Any] else { throw BridgeError.invalidInput }
        let limits = root["rate_limits"] as? [String: Any]

        func number(_ value: Any?) -> Double? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        func window(_ name: String) -> ClaudeUsage.Window? {
            guard let value = limits?[name] as? [String: Any] else { return nil }
            return ClaudeUsage.Window(usedPercentage: number(value["used_percentage"]), resetsAt: number(value["resets_at"]))
        }
        let observation = ClaudeUsage.StoredObservation(schemaVersion: 1, observedAt: now.timeIntervalSince1970,
                                                        fiveHour: window("five_hour"), sevenDay: window("seven_day"))
        guard observation.observedAt.isFinite, observation.observedAt > 0 else { throw ClaudeUsage.ReadError.invalidObservation }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Missing rate_limits is authoritative: replace any previous observation with unknown quota.
        try writePrivate(encoder.encode(observation), to: fileURL)
        let parts = [("5h", observation.fiveHour), ("week", observation.sevenDay)].compactMap { label, window -> String? in
            window?.usedPercentage.map { "\(label) \(Int($0.rounded()))% used" }
        }
        return parts.isEmpty ? "Claude usage unavailable" : "Claude · " + parts.joined(separator: " · ")
    }

    /// Explicit setup only. It never replaces another status line command.
    /// Returns a backup URL when existing settings were changed, otherwise nil.
    @discardableResult
    static func install(executableURL: URL, settingsURL: URL = defaultSettingsURL) throws -> URL? {
        guard executableURL.isFileURL, executableURL.path.hasPrefix("/"), !executableURL.path.contains("\n") else { throw BridgeError.unsafePath }
        try rejectSymbolicLink(settingsURL)
        let existing: Data? = FileManager.default.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
        var settings: [String: Any]
        if let existing {
            guard existing.count <= 1024 * 1024,
                  let decoded = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else { throw BridgeError.invalidSettings }
            settings = decoded
        } else { settings = [:] }
        let command = shellQuoted(executableURL.path) + " --capture-claude-usage"
        if let value = settings["statusLine"] {
            guard let statusLine = value as? [String: Any], statusLine["type"] as? String == "command",
                  let oldCommand = statusLine["command"] as? String,
                  isOwnCommand(oldCommand, executableName: executableURL.lastPathComponent) else { throw BridgeError.existingStatusLine }
            if oldCommand == command { return nil }
            var updated = statusLine
            updated["command"] = command
            settings["statusLine"] = updated
        } else {
            settings["statusLine"] = ["type": "command", "command": command]
        }

        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) + Data([0x0A])
        var backupURL: URL?
        if let existing {
            let candidate = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.codex-meter-backup-\(UUID().uuidString).json")
            try writePrivate(existing, to: candidate)
            backupURL = candidate
        }
        // Avoid overwriting changes made while the backup was being saved.
        let current: Data? = FileManager.default.fileExists(atPath: settingsURL.path) ? try Data(contentsOf: settingsURL) : nil
        guard current == existing else { throw BridgeError.settingsChanged }
        try writePrivate(newData, to: settingsURL)
        return backupURL
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isOwnCommand(_ command: String, executableName: String) -> Bool {
        let suffix = " --capture-claude-usage"
        guard command.hasSuffix(suffix) else { return false }
        let word = String(command.dropLast(suffix.count))
        guard word.first == "'", word.last == "'", word.count >= 2 else { return false }
        let path = String(word.dropFirst().dropLast()).replacingOccurrences(of: "'\\''", with: "'")
        return path.hasPrefix("/") && URL(fileURLWithPath: path).lastPathComponent == executableName && shellQuoted(path) == word
    }

    private static func rejectSymbolicLink(_ url: URL) throws {
        guard url.isFileURL else { throw BridgeError.unsafePath }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { throw BridgeError.unsafePath }
    }

    /// Create the temporary file with mode 0600 before writing any bytes, then rename atomically.
    private static func writePrivate(_ data: Data, to fileURL: URL) throws {
        try rejectSymbolicLink(fileURL)
        let directory = fileURL.deletingLastPathComponent()
        try rejectSymbolicLink(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".codex-meter-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BridgeError.writeFailed }
        var closed = false
        defer {
            if !closed { close(descriptor) }
            try? FileManager.default.removeItem(at: temporary)
        }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw BridgeError.writeFailed }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw BridgeError.writeFailed }
        let closeResult = close(descriptor)
        closed = true
        guard closeResult == 0 else { throw BridgeError.writeFailed }
        guard rename(temporary.path, fileURL.path) == 0 else { throw BridgeError.writeFailed }
    }
}
