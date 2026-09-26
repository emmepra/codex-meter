# Security boundaries and review

## Trust boundaries

- Meter launches a locally installed Codex CLI with fixed arguments through `Process`, without a shell. Authentication stays with that CLI. Its executable and installation directories must be trusted; Meter does not authenticate the publisher of a discovered executable.
- The CLI protocol starts no model turns and never redeems reset credits. Reads have a deadline and a response-buffer limit; stderr is discarded and the child process is closed after each read.
- Reset posts come from a third-party HTTPS Nitter feed. Redirects, XML document types and entities are rejected; the streamed body, XML depth, item count and accepted text size are bounded. Matching text is displayed as text, not executed or rendered as HTML. Post links are reconstructed on `x.com` from validated numeric IDs.
- Feed author and channel checks do not authenticate a tweet independently of the RSS provider. A compromised provider could forge or suppress announcements. Treat them as notices, not confirmation of account resets.
- Update metadata comes from a fixed HTTPS GitHub endpoint, with redirects rejected. Release links are reconstructed from validated stable version numbers. Meter opens the release page; it does not download and execute an installer or replace itself.
- The app is ad hoc signed, not Developer ID signed or notarized. Release checksums detect differing bytes but do not establish publisher identity independently of GitHub.

## Focused review — 26 September 2026

Reviewed the RSS parser and fetcher, release checker, CLI discovery and process handling, installation/packaging scripts, and release workflow against the 0.5.1 source. Actions are pinned by commit; publishing is isolated from pull-request jobs. No new third-party runtime library is used.

One resource-exhaustion hardening gap was found: the update response's 2 MiB limit was checked only after `URLSession.data(for:)` had buffered the full body. The follow-up implementation reads a byte stream, rejects oversized declared lengths, and stops when the actual body exceeds 2 MiB, including responses without a content length. **This hardening is included from 0.5.2; it is absent from 0.5.1 and earlier.** Regression checks cover the exact limit and early rejection without draining an oversized stream.

The offline regression suite passed. A scan of tracked working-tree files found no matches for selected common private-key, GitHub-token and API-key formats; this was not a complete historical secret audit. No direct remote code-execution path was identified in the reviewed code. This is a bounded source review, not a penetration test or a guarantee that no vulnerabilities exist; upstream CLI/macOS vulnerabilities and compromised local installations were not audited.
