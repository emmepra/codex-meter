# Security boundaries and review

## Trust boundaries

- Meter launches a locally installed Codex CLI with fixed arguments through `Process`, without a shell. Authentication stays with that CLI. Its executable and installation directories must be trusted; Meter does not authenticate the publisher of a discovered executable.
- The CLI protocol starts no model turns and never redeems reset credits. Reads have a deadline and a response-buffer limit; stderr is discarded and the child process is closed after each read.
- The optional Claude bridge receives local quota from a bundled Desktop Code plugin or a terminal status-line command and saves only capture time and known windows. Its own code does not read Claude credentials or call Anthropic endpoints. Its quota file is local input, not authenticated account evidence; another process with the same user's access could replace it. See [Claude bridge boundaries](#claude-bridge-boundaries).
- Reset posts come from a third-party HTTPS Nitter feed. Redirects, XML document types and entities are rejected; the streamed body, XML depth, item count and accepted text size are bounded. Matching text is displayed as text, not executed or rendered as HTML. Post links are reconstructed on `x.com` from validated numeric IDs.
- Feed author and channel checks do not authenticate a tweet independently of the RSS provider. A compromised provider could forge or suppress announcements. Treat them as notices, not confirmation of account resets.
- Update metadata comes from a fixed HTTPS GitHub endpoint, with redirects rejected. Release links are reconstructed from validated stable version numbers. From 0.5.3, user-initiated installation uses the bundled Sparkle framework. It requires an Ed25519-signed feed and archive and verifies the archive before extraction. The public key is embedded in the app; the private key remains in the maintainer Mac login Keychain. Sparkle manages replacement and relaunch after user confirmation. GitHub CI stages a draft; a local signing step must finish before publication.
- The app is ad hoc signed, not Developer ID signed or notarized. Release checksums detect differing bytes but do not establish publisher identity independently of GitHub.

## Focused review — 26 September 2026

Reviewed the RSS parser and fetcher, release checker, CLI discovery and process handling, installation/packaging scripts, and release workflow against the 0.5.1 source. Actions are pinned by commit; publishing is isolated from pull-request jobs. The reviewed 0.5.1 version had no third-party runtime library. Version 0.5.3 introduces Sparkle 2.10.0, pinned by distribution checksum; it is a new runtime trust dependency.

One resource-exhaustion hardening gap was found: the update response's 2 MiB limit was checked only after `URLSession.data(for:)` had buffered the full body. The follow-up implementation reads a byte stream, rejects oversized declared lengths, and stops when the actual body exceeds 2 MiB, including responses without a content length. **This hardening is included from 0.5.2; it is absent from 0.5.1 and earlier.** Regression checks cover the exact limit and early rejection without draining an oversized stream.

The offline regression suite passed. A scan of tracked working-tree files found no matches for selected common private-key, GitHub-token and API-key formats; this was not a complete historical secret audit. No direct remote code-execution path was identified in the reviewed code. This is a bounded source review, not a penetration test or a guarantee that no vulnerabilities exist; upstream CLI/macOS vulnerabilities and compromised local installations were not audited.

## In-app updater verification — 0.5.3

An isolated app copy with a separate bundle identifier was updated from fixture version 0.5.2 to 0.5.3 using the production Sparkle integration and a localhost feed signed with the project key. The native Install Update and Install and Relaunch flow completed; the replaced bundle version and relaunched process were checked. Changing the signed feed's title without re-signing produced Sparkle's invalid-signature error and cancelled the update. The localhost URL and transport exception exist only in the ignored test fixture, never in the production bundle. Installation requiring administrator authorization and a translocated/read-only app were not exercised.

## Credit observations

Credit monitoring uses the existing local CLI process and read-only `account/read` and `account/rateLimits/read` methods. The app retains a fingerprint of a recognized personal account and up to 30 minutes of numeric balance samples only in memory. No email, credential, raw response or sample history is saved or sent to Meter services. Restarting or changing account clears credit observations. Workspace pace estimation is disabled when a reliable billing scope is unavailable. This adds no storage, dependency, background service or billing request.

Credit pace requires fresh scoped metadata, a positive net decrease in the continuous rolling 30-minute balance history, at least 15 minutes and three samples, and a fresh latest reading. Balance increases, long gaps, failed reads and missing numeric balances restart observations. Quota exhaustion and resets do not restart this independent balance history. Recent consumption and credit runway appear only in Details; the ten-minute recent-decrease cue does not gate them. A balance decrease is an observation, not guaranteed task-level spend: expiry or service adjustments can also affect it. Credit runway assumes that recent pace continues, without a charge ledger or monetary conversion.

## Claude bridge boundaries

Claude support uses the documented [mods API](https://code.claude.com/docs/en/plugins/mods/reference) for Desktop Code sessions or the local [status-line interface](https://code.claude.com/docs/en/statusline#rate-limit-usage) for terminal sessions. Authentication remains with Claude Code; Meter does not collect, copy or intermediate subscription tokens. This follows the separation described in Anthropic's [authentication guidance](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use).

The capture command treats stdin as untrusted input. It discards all fields except the supported quota windows and writes one sanitized snapshot atomically with restrictive permissions. It never persists the full status-line payload, which can contain project and session information. The reader validates data and capture time before using the snapshot; missing quota values remain unknown.

The bridge is installed only by explicit setup. The Desktop route adds a local marketplace and user-scoped plugin; the terminal route preserves unrelated settings and refuses to overwrite an unrelated status-line command. Settings changes are backed up. Both routes point to the installed Meter executable, so moving or removing it requires updating or removing the integration. A custom terminal wrapper remains the user's script and must pass input to the capture command without evaluating payload contents as shell code.

Desktop setup copies the bundled source into Meter's private Application Support directory and changes the executable path only in that copy. Before invoking Claude Code's installation commands, it backs up only existing settings, marketplace and installed-plugin metadata, together with any previous Meter bridge source. It does not copy authentication files. Backup directories are `0700` and copied configuration files `0600`; the [installation guide](INSTALL.md#desktop-code-sessions) lists their paths.

The bundled plugin is a new local execution dependency. It handles only session startup and quota-measurement events, extracts supported quota fields and invokes the fixed capture executable with sanitized stdin. Its code makes no network, model, prompt, transcript or credential calls and adds no MCP server or background service. This is a property of the bundled source, not a sandbox restriction: Claude Code mods run with the user's permissions, as described in the [mods trust model](https://code.claude.com/docs/en/plugins/mods/overview#decide-whether-to-trust-a-mod). The copied plugin and its installation directories must remain trusted.

Capture time records receipt from Claude Code, not a fresh Anthropic response. Terminal status lines can redraw from existing data. Multiple sessions share the latest local snapshot, without a reliable account identity; no cross-account credit history is inferred. Old captures and elapsed resets pause estimates. This adds no credential store, network service, direct polling of Anthropic or model invocation.

The focused reviews and updater checks above predate this integration. They do not establish Claude live-account compatibility or complete reset-cycle behavior. Use the current change's test evidence for this integration's verification scope.

Desktop setup explicitly enables only Meter’s own plugin at user scope. Failures before registration restore the previous source; failures after registration starts retain valid source and private backups for retry, without blindly restoring shared CLI metadata. Focused mutating-stub tests cover partial registration, prior disabled state and a failed enable command.
