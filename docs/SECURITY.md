# Security boundaries and review

## Trust boundaries

- Meter launches a locally installed Codex CLI with fixed arguments through `Process`, without a shell. Authentication stays with that CLI. Its executable and installation directories must be trusted; Meter does not authenticate the publisher of a discovered executable.
- The CLI protocol starts no model turns and never redeems reset credits. Reads have a deadline and a response-buffer limit; stderr is discarded and the child process is closed after each read.
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

Credit monitoring uses the existing local CLI process and read-only `account/read` and `account/rateLimits/read` methods. The app retains a fingerprint of a recognized personal account, up to 30 minutes of numeric balance samples and a constant-size aggregate for the current and last observed exhausted-quota period only in memory. No email, credential, raw response, sample history or spend aggregate is saved or sent to Meter services. Restarting or changing account clears credit observations. Workspace tracking and forecasting are disabled when a reliable billing scope is unavailable. This adds no storage, dependency, background service or billing request.

Observed spend sums known positive balance decreases; uncertain intervals are omitted and mark the total as partial. Starting with quota already exhausted cannot establish past consumption. A balance decrease is an observation, not guaranteed task-level spend: expiry or service adjustments can also affect it. The until-reset forecast requires fresh scoped metadata, sufficient recent pace history, known window usage and a future reset for every exhausted window. It estimates additional credits at a constant pace, without a charge ledger or monetary conversion, and does not treat the current balance as a cap on projected need.
