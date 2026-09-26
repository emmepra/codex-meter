import Foundation
import Darwin
import AppKit

/// A short-lived connection to the installed Codex CLI. No model turns are started.
struct CodexClient {
    var executableURL: URL? = nil
    var timeout: TimeInterval = 20

    func readLimits() async throws -> Data {
        let operation = CodexReadOperation(executableURL: executableURL, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try operation.run() })
                }
            }
        }, onCancel: {
            operation.cancel()
        })
    }

    static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        let appLocations = ([codexApp].compactMap { $0 } + [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/ChatGPT.app")
        ])
        let paths = executablePaths(home: home,
                                    path: ProcessInfo.processInfo.environment["PATH"] ?? "",
                                    codexApps: appLocations)
        return firstExecutable(in: paths)
    }

    static func executablePaths(home: URL, path: String, codexApps: [URL]) -> [URL] {
        let standalone = [home.appendingPathComponent(".local/bin/codex"),
                          URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
                          URL(fileURLWithPath: "/usr/local/bin/codex")]
        let inherited = path.split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        }
        // Finder does not inherit the shell's PATH. Codex desktop includes a CLI,
        // and its location can change when the desktop app is updated or moved.
        let bundled = codexApps.flatMap { app in
            [app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
             app.appendingPathComponent("Contents/Resources/codex")]
        }
        return standalone + inherited + bundled
    }

    static func firstExecutable(in paths: [URL]) -> URL? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

enum CodexClientError: LocalizedError {
    case cliNotFound
    case couldNotStart
    case timeout
    case disconnected
    case invalidResponse
    case requestFailed
    case loginRequired

    var errorDescription: String? {
        switch self {
        case .cliNotFound: return "Codex CLI not found. Install or update Codex CLI or the Codex desktop app, then refresh."
        case .couldNotStart: return "Could not start Codex CLI. Check that it works in Terminal."
        case .timeout: return "Codex did not respond in time."
        case .disconnected: return "The connection to Codex closed before a response arrived."
        case .invalidResponse: return "Codex returned an unrecognized response."
        case .requestFailed: return "Could not read usage limits. Check your connection and Codex sign-in."
        case .loginRequired: return "Sign in to Codex CLI with your ChatGPT account to read usage limits."
        }
    }
}

private final class CodexReadOperation: @unchecked Sendable {
    private let executableURL: URL?
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var cancelled = false

    init(executableURL: URL?, timeout: TimeInterval) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private func checkCancellation() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }

    func run() throws -> Data {
        try checkCancellation()
        guard let executable = executableURL ?? CodexClient.findExecutable() else {
            throw CodexClientError.cliNotFound
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        // Diagnostics can contain account/configuration details; never retain or display them.
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        do { try process.run() }
        catch { throw CodexClientError.couldNotStart }
        // A child that exits between two writes must produce an error, never SIGPIPE in the UI.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            finish(process)
            try? output.fileHandleForReading.close()
        }

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, timeout)
        try send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "codex_meter", "title": "Codex Meter", "version": "0.1.0"]]
        ], to: input.fileHandleForWriting)

        var expectedID = 1
        var buffer = Data()
        let descriptor = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            try checkCancellation()
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw CodexClientError.timeout }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let status = poll(&pollDescriptor, 1, Int32(min(100, ceil(remaining * 1_000))))
            if status < 0 {
                if errno == EINTR { continue }
                throw CodexClientError.disconnected
            }
            if status == 0 { continue }
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw CodexClientError.disconnected
            }
            guard count > 0 else { throw CodexClientError.disconnected }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 2_097_152 else { throw CodexClientError.invalidResponse }
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
                    throw CodexClientError.invalidResponse
                }
                // Ignore unrelated notifications. Only two read-only protocol requests are sent.
                guard (message["id"] as? Int) == expectedID else { continue }
                if let error = message["error"] as? [String: Any] {
                    let reason = (error["message"] as? String ?? "").lowercased()
                    if reason.contains("not authenticated") || reason.contains("not logged in") || reason.contains("requires chatgpt") {
                        throw CodexClientError.loginRequired
                    }
                    throw CodexClientError.requestFailed
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw CodexClientError.invalidResponse
                }
                if expectedID == 1 {
                    try send(["method": "initialized", "params": [:]], to: input.fileHandleForWriting)
                    try send(["id": 2, "method": "account/rateLimits/read"], to: input.fileHandleForWriting)
                    expectedID = 2
                } else {
                    try checkCancellation()
                    return try JSONSerialization.data(withJSONObject: result)
                }
            }
        }
    }

    private func send(_ message: [String: Any], to handle: FileHandle) throws {
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        } catch {
            throw CodexClientError.disconnected
        }
    }

    private func finish(_ process: Process) {
        // EOF normally closes app-server immediately; bounded fallbacks prevent orphan processes.
        let gracefulDeadline = ProcessInfo.processInfo.systemUptime + 0.3
        while process.isRunning && ProcessInfo.processInfo.systemUptime < gracefulDeadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            let terminateDeadline = ProcessInfo.processInfo.systemUptime + 0.3
            while process.isRunning && ProcessInfo.processInfo.systemUptime < terminateDeadline { usleep(10_000) }
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
