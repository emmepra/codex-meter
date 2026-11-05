import Foundation
import Darwin

/// Installs the bundled, local-only plugin through Claude Code's own plugin manager.
enum ClaudeDesktopBridge {
    private static let installQueue = DispatchQueue(label: "CodexMeter.ClaudeSetup", qos: .utility)
    enum SetupError: LocalizedError {
        case missingResources, unsafeDestination, commandFailed, setupIncomplete
        var errorDescription: String? {
            switch self {
            case .missingResources: return "This build is missing the Claude Desktop bridge. Reinstall Meter."
            case .unsafeDestination: return "The Claude bridge destination is a symbolic link or contains an unrelated plugin."
            case .commandFailed: return "Claude Code could not complete the local bridge command. Try setup again."
            case .setupIncomplete:
                return "Claude setup is incomplete. Bridge files and private recovery backups were kept. Retry Set Up Claude; reload plugins after setup succeeds."
            }
        }
    }

    static func desktopCLI() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code", isDirectory: true)
        let versions = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.first?.isNumber == true && $0.lastPathComponent.compare("2.1.299", options: .numeric) != .orderedAscending }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        for version in versions {
            for build in (try? FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)) ?? [] {
                let candidate = build.appendingPathComponent("claude.app/Contents/MacOS/claude")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    static func install(cli: URL, executable: URL,
                        source: URL? = Bundle.main.resourceURL?.appendingPathComponent("ClaudeBridgePlugin"),
                        supportDirectory: URL = ClaudeUsage.defaultFileURL.deletingLastPathComponent(),
                        settingsURL: URL = ClaudeBridge.defaultSettingsURL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            installQueue.async {
                continuation.resume(with: Result {
                    guard let source else { throw SetupError.missingResources }
                    try installFilesAndRegister(cli: cli, executable: executable, source: source, support: supportDirectory, settings: settingsURL)
                })
            }
        }
    }

    private static func installFilesAndRegister(cli: URL, executable: URL, source: URL, support: URL, settings: URL) throws {
        let files = FileManager.default
        let destination = support.appendingPathComponent("ClaudeDesktopBridge", isDirectory: true)
        let manifest = ".claude-plugin/marketplace.json"
        guard files.fileExists(atPath: source.appendingPathComponent(manifest).path) else { throw SetupError.missingResources }
        for url in [support, destination] {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw SetupError.unsafeDestination }
        }
        try files.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep source and config recovery copies private; never copy authentication files.
        let backup = support.appendingPathComponent("bridge-backup-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: backup, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let configFiles = [settings, settings.deletingLastPathComponent().appendingPathComponent("plugins/known_marketplaces.json"),
                           settings.deletingLastPathComponent().appendingPathComponent("plugins/installed_plugins.json")]
        for (index, url) in configFiles.enumerated() where files.fileExists(atPath: url.path) {
            let copy = backup.appendingPathComponent("\(index)-\(url.lastPathComponent)")
            try files.copyItem(at: url, to: copy)
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
        }
        if files.fileExists(atPath: destination.path) {
            guard let data = try? Data(contentsOf: destination.appendingPathComponent(manifest)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == "codex-meter-local" else { throw SetupError.unsafeDestination }
            try files.moveItem(at: destination, to: backup.appendingPathComponent("previous-plugin"))
        }
        var configurationCommandAttempted = false
        do {
            try files.copyItem(at: source, to: destination)
            let module = destination.appendingPathComponent("plugins/codex-meter-claude/hooks/register.js")
            let marker = #""/Applications/Codex Meter.app/Contents/MacOS/CodexMeter""#
            let text = try String(contentsOf: module, encoding: .utf8)
            guard text.contains(marker) else { throw SetupError.missingResources }
            let quoted = String(decoding: try JSONSerialization.data(withJSONObject: executable.path, options: [.fragmentsAllowed]), as: UTF8.self)
            try text.replacingOccurrences(of: marker, with: quoted).write(to: module, atomically: true, encoding: .utf8)
            try run(cli, ["plugin", "validate", destination.appendingPathComponent("plugins/codex-meter-claude").path])
            // From this point a failed/timed-out CLI may already have changed its
            // registries. Keep their source path valid; never overwrite global
            // metadata with an old backup that could erase concurrent changes.
            configurationCommandAttempted = true
            try run(cli, ["plugin", "marketplace", "add", destination.path])
            try run(cli, ["plugin", "install", "codex-meter-claude@codex-meter-local", "--scope", "user"])
            // Reinstalling preserves a prior disabled entry. Explicit setup must
            // enable our own user-scoped plugin before reporting success.
            try run(cli, ["plugin", "enable", "codex-meter-claude@codex-meter-local", "--scope", "user"])
        } catch {
            if configurationCommandAttempted { throw SetupError.setupIncomplete }
            try? files.removeItem(at: destination)
            let previous = backup.appendingPathComponent("previous-plugin")
            if files.fileExists(atPath: previous.path) { try? files.moveItem(at: previous, to: destination) }
            throw error
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            usleep(100_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw SetupError.commandFailed
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SetupError.commandFailed }
    }
}
