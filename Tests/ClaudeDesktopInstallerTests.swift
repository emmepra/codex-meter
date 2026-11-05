import Foundation

@main
enum ClaudeDesktopInstallerTests {
    private struct Fixture {
        let root: URL
        let support: URL
        let settings: URL
        let cli: URL
        let log: URL
        var destination: URL { support.appendingPathComponent("ClaudeDesktopBridge") }
        var configFiles: [URL] {
            [settings,
             settings.deletingLastPathComponent().appendingPathComponent("plugins/known_marketplaces.json"),
             settings.deletingLastPathComponent().appendingPathComponent("plugins/installed_plugins.json")]
        }
    }

    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("meter-desktop-installer-tests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let source = URL(fileURLWithPath: files.currentDirectoryPath).appendingPathComponent("Resources/ClaudeBridgePlugin")
        let modulePath = "plugins/codex-meter-claude/hooks/register.js"
        let pluginID = "codex-meter-claude@codex-meter-local"
        let bundledManifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            source.appendingPathComponent("plugins/codex-meter-claude/.claude-plugin/plugin.json"))) as! [String: Any]
        let bundledVersion = bundledManifest["version"] as! String
        let originalModule = try Data(contentsOf: source.appendingPathComponent(modulePath))
        let originalSettings = Data(#"{"theme":"dark","statusLine":{"type":"command","command":"my-existing-statusline"},"permissions":{"allow":["Read"]}}"#.utf8)
        let originalMarketplace = Data(#"{"unrelated-marketplace":{"source":{"source":"directory","path":"/synthetic/marketplace"},"installLocation":"/synthetic/marketplace","lastUpdated":"2026-01-01T00:00:00Z"}}"#.utf8)
        let originalPlugins = Data(#"{"version":2,"plugins":{"example@unrelated-marketplace":[{"scope":"user","installPath":"/synthetic/plugin","version":"1.0.0"}]}}"#.utf8)
        let originalConfigs = [originalSettings, originalMarketplace, originalPlugins]

        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
        }
        func mode(_ url: URL) throws -> Int {
            (try files.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
        }
        func writeCLI(_ url: URL, log: URL, failOn: String? = nil, mutating fixture: Fixture? = nil) throws {
            var mutations = ""
            if let fixture {
                // Simulate the official CLI's registry/settings side effects.
                // All inputs and destinations belong to this temporary fixture.
                let templates = fixture.root.appendingPathComponent("synthetic-cli-state")
                try files.createDirectory(at: templates, withIntermediateDirectories: true)
                var marketplace = try JSONSerialization.jsonObject(with: originalMarketplace) as! [String: Any]
                marketplace["codex-meter-local"] = [
                    "source": ["source": "directory", "path": fixture.destination.path],
                    "installLocation": fixture.destination.path
                ]
                var plugins = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.configFiles[2])) as! [String: Any]
                var installed = plugins["plugins"] as! [String: Any]
                if installed[pluginID] == nil {
                    installed[pluginID] = [[
                        "scope": "user", "version": bundledVersion,
                        "installPath": fixture.destination.appendingPathComponent("plugins/codex-meter-claude").path
                    ]]
                }
                plugins["plugins"] = installed
                var updatedPlugins = plugins
                var updatedInstalled = installed
                updatedInstalled[pluginID] = (installed[pluginID] as? [[String: Any]])?.map { entry in
                    var updated = entry
                    if entry["scope"] as? String == "user" { updated["version"] = bundledVersion }
                    return updated
                }
                updatedPlugins["plugins"] = updatedInstalled
                let currentSettings = try Data(contentsOf: fixture.settings)
                let disabled = try JSONSerialization.jsonObject(with: currentSettings) as! [String: Any]
                var enabled = disabled
                var enabledPlugins = enabled["enabledPlugins"] as? [String: Any] ?? [:]
                enabledPlugins["codex-meter-claude@codex-meter-local"] = true
                enabled["enabledPlugins"] = enabledPlugins
                for (name, object) in [("marketplace.json", marketplace), ("plugins.json", plugins), ("plugins-updated.json", updatedPlugins),
                                       ("settings-disabled.json", disabled), ("settings-enabled.json", enabled)] {
                    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                        .write(to: templates.appendingPathComponent(name))
                }
                func copy(_ template: String, to target: URL) -> String {
                    "cp " + ClaudeBridge.shellQuoted(templates.appendingPathComponent(template).path)
                        + " " + ClaudeBridge.shellQuoted(target.path)
                }
                mutations = """
                if [ "${2-}" = marketplace ]; then
                  \(copy("marketplace.json", to: fixture.configFiles[1]))
                fi
                if [ "${2-}" = install ]; then
                  \(copy("plugins.json", to: fixture.configFiles[2]))
                  \(copy("settings-disabled.json", to: fixture.settings))
                fi
                if [ "${2-}" = update ]; then
                  \(failOn == "update" ? "exit 7" : copy("plugins-updated.json", to: fixture.configFiles[2]))
                fi
                if [ "${2-}" = enable ]; then
                  \(failOn == "enable" ? "exit 7" : copy("settings-enabled.json", to: fixture.settings))
                fi
                """
            }
            let script = """
            #!/bin/sh
            set -eu
            {
              printf '%s\\n' "$@"
              printf 'END\\n'
            } >> \(ClaudeBridge.shellQuoted(log.path))
            \(mutations)
            \(failOn.map { "if [ \"${2-}\" = " + ClaudeBridge.shellQuoted($0) + " ]; then exit 7; fi" } ?? "")
            exit 0
            """
            try Data(script.utf8).write(to: url)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        func fixture(_ name: String) throws -> Fixture {
            let directory = root.appendingPathComponent(name)
            let fixture = Fixture(root: directory, support: directory.appendingPathComponent("Meter support"),
                                  settings: directory.appendingPathComponent("claude/settings.json"),
                                  cli: directory.appendingPathComponent("synthetic-claude"),
                                  log: directory.appendingPathComponent("cli-calls.txt"))
            try files.createDirectory(at: fixture.settings.deletingLastPathComponent().appendingPathComponent("plugins"),
                                      withIntermediateDirectories: true)
            for (url, data) in zip(fixture.configFiles, originalConfigs) { try data.write(to: url) }
            try writeCLI(fixture.cli, log: fixture.log)
            return fixture
        }
        func calls(_ log: URL) throws -> [[String]] {
            guard files.fileExists(atPath: log.path) else { return [] }
            return try String(contentsOf: log, encoding: .utf8).components(separatedBy: "END\n")
                .map { $0.split(separator: "\n").map(String.init) }.filter { !$0.isEmpty }
        }
        func writeInstalledVersion(_ version: String, to fixture: Fixture) throws {
            var plugins = try JSONSerialization.jsonObject(with: originalPlugins) as! [String: Any]
            var installed = plugins["plugins"] as! [String: Any]
            installed[pluginID] = [["scope": "user", "version": version,
                                    "installPath": fixture.destination.appendingPathComponent("plugins/codex-meter-claude").path]]
            // A different scope must not decide whether the user installation needs updating.
            installed[pluginID] = (installed[pluginID] as! [[String: Any]]) + [["scope": "project", "version": "unrelated-project-version"]]
            plugins["plugins"] = installed
            try JSONSerialization.data(withJSONObject: plugins).write(to: fixture.configFiles[2])
        }
        func checkConfigs(_ fixture: Fixture) throws {
            for (url, original) in zip(fixture.configFiles, originalConfigs) {
                let current = try Data(contentsOf: url)
                check(current == original, "The native installer must preserve existing settings and statusLine bytes")
            }
        }
        func backups(_ fixture: Fixture) throws -> [URL] {
            try files.contentsOfDirectory(at: fixture.support, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("bridge-backup-") }
        }
        func checkBackups(_ fixture: Fixture, expected: Int) throws {
            let copies = try backups(fixture)
            check(copies.count == expected, "Each attempted replacement keeps one recovery directory")
            for directory in copies {
                let permissions = try mode(directory)
                check(permissions == 0o700, "Recovery directories must be private")
                for (index, original) in originalConfigs.enumerated() {
                    let copy = directory.appendingPathComponent("\(index)-\(fixture.configFiles[index].lastPathComponent)")
                    let contents = try Data(contentsOf: copy)
                    let permissions = try mode(copy)
                    check(contents == original && permissions == 0o600, "Recovery copies preserve exact bytes privately")
                }
            }
        }
        @discardableResult
        func rejects(_ operation: () async throws -> Void, _ message: String) async -> Error {
            do { try await operation(); fatalError(message) } catch { return error }
        }
        let executable = root.appendingPathComponent("Applications/Meter's \"quoted\" $bridge.app/Contents/MacOS/CodexMeter")
        let normal = try fixture("normal")
        try await ClaudeDesktopBridge.install(cli: normal.cli, executable: executable, source: source,
                                               supportDirectory: normal.support, settingsURL: normal.settings)
        let quoted = String(decoding: try JSONSerialization.data(withJSONObject: executable.path, options: [.fragmentsAllowed]), as: UTF8.self)
        let installedModule = try String(contentsOf: normal.destination.appendingPathComponent(modulePath), encoding: .utf8)
        check(installedModule.contains("const METER_EXECUTABLE = \(quoted);"), "Substitute one safe JSON string literal for arbitrary app paths")
        check(try Data(contentsOf: source.appendingPathComponent(modulePath)) == originalModule, "Keep bundled resources unchanged")
        let expectedCommands = [
            ["plugin", "validate", normal.destination.appendingPathComponent("plugins/codex-meter-claude").path],
            ["plugin", "marketplace", "add", normal.destination.path],
            ["plugin", "install", "codex-meter-claude@codex-meter-local", "--scope", "user"],
            ["plugin", "enable", "codex-meter-claude@codex-meter-local", "--scope", "user"]
        ]
        check(try calls(normal.log) == expectedCommands, "Validate before registering and enabling only the local user-scope plugin")
        check(try mode(normal.support) == 0o700, "Create app support privately")
        try checkConfigs(normal)
        try checkBackups(normal, expected: 1)

        // Reinstall from a different app location: replace our plugin and retain its previous copy.
        let movedExecutable = root.appendingPathComponent("Other Applications/Meter.app/Contents/MacOS/CodexMeter")
        let sentinel = Data("previous installed plugin".utf8)
        let marker = normal.destination.appendingPathComponent("previous-install.txt")
        try sentinel.write(to: marker)
        try await ClaudeDesktopBridge.install(cli: normal.cli, executable: movedExecutable, source: source,
                                               supportDirectory: normal.support, settingsURL: normal.settings)
        check(try calls(normal.log) == expectedCommands + expectedCommands, "Repeat setup uses the official idempotent local-marketplace add path")
        check(!files.fileExists(atPath: marker.path), "Reinstall refreshes the bundled plugin")
        let retained = try backups(normal).filter { files.fileExists(atPath: $0.appendingPathComponent("previous-plugin/previous-install.txt").path) }
        check(retained.count == 1, "Keep the previous owned plugin as a recovery copy")
        check(try Data(contentsOf: retained[0].appendingPathComponent("previous-plugin/previous-install.txt")) == sentinel,
              "Previous plugin recovery is exact")
        try checkBackups(normal, expected: 2)

        // Validation has no registry side effects, so it can restore the old source.
        try sentinel.write(to: marker)
        let previousModule = try Data(contentsOf: normal.destination.appendingPathComponent(modulePath))
        let failingCLI = normal.root.appendingPathComponent("failing-claude")
        try writeCLI(failingCLI, log: normal.log, failOn: "validate")
        await rejects({
            try await ClaudeDesktopBridge.install(cli: failingCLI, executable: executable, source: source,
                                                   supportDirectory: normal.support, settingsURL: normal.settings)
        }, "Failed validation must fail setup")
        check(try Data(contentsOf: marker) == sentinel, "Restore the previous plugin before any configuration command ran")
        check(try Data(contentsOf: normal.destination.appendingPathComponent(modulePath)) == previousModule,
              "Rollback also restores the previous app-path substitution")
        try checkConfigs(normal)
        try checkBackups(normal, expected: 3)

        let freshFailure = try fixture("fresh-failure")
        try writeCLI(freshFailure.cli, log: freshFailure.log, failOn: "install", mutating: freshFailure)
        let partialFailure = await rejects({
            try await ClaudeDesktopBridge.install(cli: freshFailure.cli, executable: executable, source: source,
                                                   supportDirectory: freshFailure.support, settingsURL: freshFailure.settings)
        }, "A failed first installation must fail setup")
        if case ClaudeDesktopBridge.SetupError.setupIncomplete = partialFailure {} else {
            fatalError("A partial registration must report incomplete setup, not ordinary validation failure")
        }
        check(files.fileExists(atPath: freshFailure.destination.appendingPathComponent(modulePath).path),
              "Keep a valid plugin source after a possibly committed registration")
        let registered = try JSONSerialization.jsonObject(with: Data(contentsOf: freshFailure.configFiles[1])) as! [String: Any]
        let ownRegistration = registered["codex-meter-local"] as! [String: Any]
        check(ownRegistration["installLocation"] as? String == freshFailure.destination.path,
              "The retained registry must point to the retained source")
        let retainedSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: freshFailure.settings)) as! NSDictionary
        check(retainedSettings == (try JSONSerialization.jsonObject(with: originalSettings) as! NSDictionary),
              "A failed install preserves unrelated settings and the existing terminal status line")
        let unrelatedMarketplace = (try JSONSerialization.jsonObject(with: originalMarketplace) as! [String: Any])["unrelated-marketplace"] as! NSDictionary
        check(registered["unrelated-marketplace"] as? NSDictionary == unrelatedMarketplace,
              "CLI registration must retain unrelated marketplaces")
        let installedAfterFailure = try JSONSerialization.jsonObject(with: Data(contentsOf: freshFailure.configFiles[2])) as! [String: Any]
        let priorInstalled = (try JSONSerialization.jsonObject(with: originalPlugins) as! [String: Any])["plugins"] as! [String: Any]
        check((installedAfterFailure["plugins"] as? [String: Any])?["example@unrelated-marketplace"] as? NSArray
              == priorInstalled["example@unrelated-marketplace"] as? NSArray,
              "A partial install must not discard unrelated installed-plugin metadata")
        try checkBackups(freshFailure, expected: 1)

        let replacementFailure = try fixture("replacement-failure")
        try await ClaudeDesktopBridge.install(cli: replacementFailure.cli, executable: executable, source: source,
                                               supportDirectory: replacementFailure.support, settingsURL: replacementFailure.settings)
        try sentinel.write(to: replacementFailure.destination.appendingPathComponent("previous-install.txt"))
        try writeCLI(replacementFailure.cli, log: replacementFailure.log, failOn: "install", mutating: replacementFailure)
        await rejects({
            try await ClaudeDesktopBridge.install(cli: replacementFailure.cli, executable: movedExecutable, source: source,
                                                   supportDirectory: replacementFailure.support, settingsURL: replacementFailure.settings)
        }, "A partly committed replacement must report failure")
        let newModule = try String(contentsOf: replacementFailure.destination.appendingPathComponent(modulePath), encoding: .utf8)
        let movedQuoted = String(decoding: try JSONSerialization.data(withJSONObject: movedExecutable.path, options: [.fragmentsAllowed]), as: UTF8.self)
        check(newModule.contains("const METER_EXECUTABLE = \(movedQuoted);"),
              "Keep the new validated source after registration may have committed it")
        let preservedPrevious = try backups(replacementFailure).filter {
            files.fileExists(atPath: $0.appendingPathComponent("previous-plugin/previous-install.txt").path)
        }
        check(preservedPrevious.count == 1, "Keep the previous owned source in the private recovery directory")
        try checkBackups(replacementFailure, expected: 2)

        // A prior disabled entry survives install, but explicit setup enables it.
        let disabled = try fixture("previously-disabled")
        var disabledSettings = try JSONSerialization.jsonObject(with: originalSettings) as! [String: Any]
        disabledSettings["enabledPlugins"] = ["codex-meter-claude@codex-meter-local": false,
                                               "example@unrelated-marketplace": true]
        try JSONSerialization.data(withJSONObject: disabledSettings).write(to: disabled.settings)
        try writeCLI(disabled.cli, log: disabled.log, mutating: disabled)
        try await ClaudeDesktopBridge.install(cli: disabled.cli, executable: executable, source: source,
                                               supportDirectory: disabled.support, settingsURL: disabled.settings)
        let enabledSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: disabled.settings)) as! [String: Any]
        let flags = enabledSettings["enabledPlugins"] as! [String: Bool]
        check(flags["codex-meter-claude@codex-meter-local"] == true && flags["example@unrelated-marketplace"] == true,
              "Explicit setup enables only our plugin and preserves other plugin choices")
        var comparable = enabledSettings
        comparable["enabledPlugins"] = disabledSettings["enabledPlugins"]
        check((comparable as NSDictionary) == (disabledSettings as NSDictionary), "Enabling must preserve all unrelated settings")
        check(try calls(disabled.log).last == ["plugin", "enable", "codex-meter-claude@codex-meter-local", "--scope", "user"],
              "Enable the owned plugin explicitly at user scope")

        let enableFailure = try fixture("enable-failure")
        try JSONSerialization.data(withJSONObject: disabledSettings).write(to: enableFailure.settings)
        try writeCLI(enableFailure.cli, log: enableFailure.log, failOn: "enable", mutating: enableFailure)
        let failedEnable = await rejects({
            try await ClaudeDesktopBridge.install(cli: enableFailure.cli, executable: executable, source: source,
                                                   supportDirectory: enableFailure.support, settingsURL: enableFailure.settings)
        }, "A failed enable command must never report successful setup")
        if case ClaudeDesktopBridge.SetupError.setupIncomplete = failedEnable {} else {
            fatalError("A failed enable must report incomplete setup")
        }
        let stillDisabled = try JSONSerialization.jsonObject(with: Data(contentsOf: enableFailure.settings)) as! [String: Any]
        check((stillDisabled["enabledPlugins"] as? [String: Bool])?["codex-meter-claude@codex-meter-local"] == false,
              "Do not bypass the official CLI to rewrite its disabled entry after failure")
        check(files.fileExists(atPath: enableFailure.destination.appendingPathComponent(modulePath).path),
              "Keep the installed source available when explicit enabling fails")

        // Enabling an already enabled plugin is a CLI error, so a repeat setup
        // must inspect the user setting rather than invoke enable unconditionally.
        let alreadyEnabled = try fixture("already-enabled")
        var alreadyEnabledSettings = disabledSettings
        alreadyEnabledSettings["enabledPlugins"] = [pluginID: true, "example@unrelated-marketplace": false]
        try JSONSerialization.data(withJSONObject: alreadyEnabledSettings).write(to: alreadyEnabled.settings)
        try writeInstalledVersion(bundledVersion, to: alreadyEnabled)
        try writeCLI(alreadyEnabled.cli, log: alreadyEnabled.log, failOn: "enable", mutating: alreadyEnabled)
        try await ClaudeDesktopBridge.install(cli: alreadyEnabled.cli, executable: executable, source: source,
                                               supportDirectory: alreadyEnabled.support, settingsURL: alreadyEnabled.settings)
        let alreadyEnabledCalls = try calls(alreadyEnabled.log)
        check(alreadyEnabledCalls.count == 3 && !alreadyEnabledCalls.contains { $0[1] == "enable" || $0[1] == "update" },
              "Same-version enabled setup must avoid both the failing redundant enable and unnecessary update")
        check((try JSONSerialization.jsonObject(with: Data(contentsOf: alreadyEnabled.settings)) as! NSDictionary)
              == alreadyEnabledSettings as NSDictionary, "Repeat setup preserves all enabled and unrelated user settings")

        let upgrade = try fixture("version-upgrade")
        try writeInstalledVersion("0.0.1", to: upgrade)
        try writeCLI(upgrade.cli, log: upgrade.log, mutating: upgrade)
        try await ClaudeDesktopBridge.install(cli: upgrade.cli, executable: executable, source: source,
                                               supportDirectory: upgrade.support, settingsURL: upgrade.settings)
        let upgradeCalls = try calls(upgrade.log)
        check(upgradeCalls.count == 5
              && upgradeCalls[3] == ["plugin", "update", pluginID, "--scope", "user"]
              && upgradeCalls[4] == ["plugin", "enable", pluginID, "--scope", "user"],
              "A retained older user version must update through the official CLI before enabling")
        let upgradedMetadata = try JSONSerialization.jsonObject(with: Data(contentsOf: upgrade.configFiles[2])) as! [String: Any]
        let upgradedEntries = (upgradedMetadata["plugins"] as! [String: Any])[pluginID] as! [[String: Any]]
        check(upgradedEntries.first { $0["scope"] as? String == "user" }?["version"] as? String == bundledVersion,
              "The mutating CLI fixture must record the bundled version after update")
        check(upgradedEntries.first { $0["scope"] as? String == "project" }?["version"] as? String == "unrelated-project-version",
              "Only the owned user installation is updated")

        let updateFailure = try fixture("update-failure")
        try writeInstalledVersion("0.0.1", to: updateFailure)
        try writeCLI(updateFailure.cli, log: updateFailure.log, failOn: "update", mutating: updateFailure)
        let failedUpdate = await rejects({
            try await ClaudeDesktopBridge.install(cli: updateFailure.cli, executable: executable, source: source,
                                                   supportDirectory: updateFailure.support, settingsURL: updateFailure.settings)
        }, "A failed plugin update must never report successful setup")
        if case ClaudeDesktopBridge.SetupError.setupIncomplete = failedUpdate {} else {
            fatalError("A failed update after registration must report incomplete setup")
        }
        check(try calls(updateFailure.log).last == ["plugin", "update", pluginID, "--scope", "user"],
              "Do not continue to enabling after an unsuccessful update")
        let updateFailureBackups = try backups(updateFailure)
        check(files.fileExists(atPath: updateFailure.destination.appendingPathComponent(modulePath).path)
              && updateFailureBackups.count == 1,
              "A failed update retains the valid registered source and private recovery backups")
        let settingsAfterUpdateFailure = try JSONSerialization.jsonObject(with: Data(contentsOf: updateFailure.settings)) as! NSDictionary
        check(settingsAfterUpdateFailure == (try JSONSerialization.jsonObject(with: originalSettings) as! NSDictionary),
              "A failed update preserves unrelated settings and statusLine")

        let unrelated = try fixture("unrelated")
        try files.createDirectory(at: unrelated.destination.appendingPathComponent(".claude-plugin"), withIntermediateDirectories: true)
        try Data(#"{"name":"someone-elses-plugin"}"#.utf8).write(to: unrelated.destination.appendingPathComponent(".claude-plugin/marketplace.json"))
        let unrelatedSentinel = unrelated.destination.appendingPathComponent("keep.txt")
        try sentinel.write(to: unrelatedSentinel)
        await rejects({
            try await ClaudeDesktopBridge.install(cli: unrelated.cli, executable: executable, source: source,
                                                   supportDirectory: unrelated.support, settingsURL: unrelated.settings)
        }, "Do not replace an unrelated plugin destination")
        check(try Data(contentsOf: unrelatedSentinel) == sentinel && calls(unrelated.log).isEmpty,
              "Refusing an unrelated destination leaves its files alone and never runs the CLI")

        let linkedSupport = try fixture("linked-support")
        let external = root.appendingPathComponent("external")
        try files.createDirectory(at: external, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: linkedSupport.support, withDestinationURL: external)
        await rejects({
            try await ClaudeDesktopBridge.install(cli: linkedSupport.cli, executable: executable, source: source,
                                                   supportDirectory: linkedSupport.support, settingsURL: linkedSupport.settings)
        }, "Refuse a symlinked support destination")
        check(try files.contentsOfDirectory(atPath: external.path).isEmpty && calls(linkedSupport.log).isEmpty,
              "Do not write or register through a symbolic link")
        let linkedPlugin = try fixture("linked-plugin")
        try files.createDirectory(at: linkedPlugin.support, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: linkedPlugin.destination, withDestinationURL: normal.destination)
        await rejects({
            try await ClaudeDesktopBridge.install(cli: linkedPlugin.cli, executable: executable, source: source,
                                                   supportDirectory: linkedPlugin.support, settingsURL: linkedPlugin.settings)
        }, "Refuse a symlinked plugin destination")
        check(try Data(contentsOf: marker) == sentinel && calls(linkedPlugin.log).isEmpty,
              "Refusing a symlinked plugin preserves its target")
        print("Claude Desktop installer synthetic tests passed")
    }
}
