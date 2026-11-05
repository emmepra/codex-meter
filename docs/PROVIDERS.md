# Provider design

## 0.7.0 scope

Version 0.7.0 adds optional Claude quota to Codex Meter, keeping the existing repository, application name, bundle identity, update path and native AppKit/SwiftUI stack. Release preparation is in progress; the version is not yet published.

One menu-bar item opens one panel. Codex remains the default; **Show Claude** opts into a second ring. Codex stays on the left and Claude on the right; provider names stay in the panel and tooltip. A 4-point gap keeps the combined indicator at 44 points, or 48 with Codex notification dots. Uncertain values show an exclamation mark inside the affected ring. All counters use consumed quota, preserving the existing Codex meaning.

The 300-point panel has a shared **Usage** header and one compact row per enabled service. Codex and Claude stay visible together; disabling Claude leaves a single Codex row. Each row shows its name, period, used percentage and bar, remaining quota and reset countdown. The period label opens a menu when multiple source windows exist; each service remembers its choice. **Updated** and **Captured** show relative freshness per row, with exact time and source explanation in help text.

Each provider has a **Details** disclosure, with at most one expanded at a time. Budget and pace estimates belong there. Credit balances, banked resets and Tibo content appear only in Codex Details, while compact cues surface conditions needing attention. The overview adds no settings, data source or quota capability.

Provider readings have independent loading, error, missing-data and stale states. A failure in one does not invalidate the other. The normalized quota model and budget calculations are shared; source decoders and collection methods stay separate.

| Capability | Codex | Claude Code |
| --- | --- | --- |
| Quota source | Short-lived local app-server read | Desktop Code plugin or terminal status-line capture |
| Scheduled window reset | Service value | Value supplied in capture |
| Quota budget and pace estimates | Shared quota calculations | Shared quota calculations |
| Account credits and credit pace | Existing scoped implementation | Not supplied by this integration |
| Banked reset availability | Existing optional account metadata | Not supplied by this integration |
| Reset announcements | Existing Tibo feed | No announcement source yet |

Quota availability is independent of announcements. A future Claude announcement source should be optional provider-specific content and must not turn a keyword match into evidence of an account reset.

## Source and storage

Claude has two local entry points feeding the same five-hour and weekly quota model. Desktop's Code surface does not invoke the terminal status-line command, so it needs the bundled `codex-meter-claude@codex-meter-local` plugin. That plugin uses the official [mods API](https://code.claude.com/docs/en/plugins/mods/reference): it reads `$.session.usage()` on `session.start` and receives `rateLimits` on `session.measure`, then passes only normalized quota to Meter's capture command. Terminal sessions can instead use Claude's [documented status-line fields](https://code.claude.com/docs/en/statusline#rate-limit-usage).

The plugin is a small local execution dependency; it requests no model responses and contains no network or credential access code. It is installed at user scope from Meter's local marketplace. This package requires embedded Claude Code 2.1.299 or later; that conservative minimum covers its manifest format. An existing session must reload plugins or restart before the newly installed plugin can run. General chat, Cowork and remote/cloud sessions are outside this integration.

The bridge retains only supported quota values and a capture timestamp in one private file. It does not access credentials or retain session/project metadata. [Setup, coexistence with a custom terminal status line, and removal](INSTALL.md#optional-claude-code-support) are documented in the installation guide.

This source is event driven. App refresh reads the local capture; it does not poll Anthropic. Capture time cannot prove server freshness, and multiple sessions share the latest value without account identification. The UI keeps those limitations visible through source wording, stale data and reset confirmation states.

## Remaining scope

Live Desktop Code capture has been checked in one local setup. A complete reset cycle, terminal-session capture and broader version coverage remain to verify. The mods surface is version dependent; a valid installation does not prove that an open session has loaded the plugin or supplied quota. No additional announcement feed, Claude credit ledger, account switcher, automatic model requests or general provider framework is included. These can be evaluated separately if the simple two-service workflow proves useful.

## UX decision — 5 November 2026

Keep both service rows visible so remaining quotas and resets can be compared immediately. Put secondary statistics and Codex-specific content in one expandable detail area at a time. This replaces the initial provider-selector design while preserving the compact rings and their order.

## Verification — 5 November 2026

The offline suite, app build, native light/dark status-appearance checks and synthetic overview rendering passed. Coverage includes independent provider errors, capture timestamps, stale or missing quota, per-provider window selection, expanded details, the Codex-only state and zero credit balances. Accessibility exposes each percentage once. Public screenshots use synthetic values.

The 300-point overview was installed and checked with real readings for both services. Expanding either service kept the other row visible and resized the native panel. The plugin passed synthetic event and installer tests, embedded-CLI 2.1.309 validation, and live activation in an existing Desktop Code session. A real weekly quota reading matched Claude's native usage display and appeared in Meter.

The complete native UI suite passed in an isolated desktop run: panel growth, shrinkage, status-item movement and reopen retained a zero-point menu-bar gap; light/dark status appearance and synthetic rendering checks also passed. The geometry harness now waits for both content size and menu-bar placement to settle. Earlier runs were interrupted by app deactivation; this interactive check requires an uninterrupted logged-in desktop. A complete reset cycle, terminal capture, older macOS versions and broader CLI coverage remain unverified.
