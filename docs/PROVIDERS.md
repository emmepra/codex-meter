# Provider design

## 0.7.0 scope

Version 0.7.0 adds optional Claude quota to Codex Meter, keeping the existing repository, application name, bundle identity, update path and native AppKit/SwiftUI stack.

One menu-bar item opens one panel. **Monitor Claude** enables Claude reads and its panel row independently of which rings are shown. **Options → Menu Bar** persists **Codex and Claude**, **Codex only** or **Claude only**. Choosing a mode containing Claude enables its monitoring; choosing Codex only does not disable it. Turning monitoring off falls back to Codex. The panel always shows the monitored services.

When both rings are visible, Codex stays on the left and Claude on the right; provider names stay in the panel and tooltip. A 4-point gap keeps the combined indicator at 44 points, or 48 with Codex notification dots. Uncertain values show an exclamation mark inside the affected ring. All counters use consumed quota, preserving the existing Codex meaning.

Fixed teal for Codex and terracotta for Claude carry through from the rings to the panel bars; digits stay neutral and adapt to appearance.

The 300-point panel has a shared **Usage** header and one compact row per enabled service. Codex and Claude stay visible together; disabling Claude leaves a single Codex row. Each row shows its name, period, used percentage and bar, remaining quota and reset countdown. The period label opens a menu when multiple source windows exist; each service remembers its choice. **Updated**, **Synced** and **Captured** identify Codex reads, Desktop bridge checks and terminal/older captures, with exact times and source explanation in help text.

Each provider has a **Details** disclosure, with at most one expanded at a time. Budget and pace estimates belong there. Credit balances, banked resets and Tibo content appear only in Codex Details, while compact cues surface conditions needing attention. Ring display preferences do not change these rows or their data sources.

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

Claude has two local entry points feeding the same five-hour and weekly quota model. Desktop's Code surface does not invoke the terminal status-line command, so it needs the bundled `codex-meter-claude@codex-meter-local` plugin. Bridge 0.1.1 uses the official [mods API](https://code.claude.com/docs/en/plugins/mods/reference): it reads cached `$.session.usage()` on startup, attach and every 60 seconds, and receives `rateLimits` on `session.measure`. The recurring check uses the documented [background timer API](https://code.claude.com/docs/en/plugins/mods/api#run-work-in-the-background) inside the active session. Terminal sessions can instead use Claude's [documented status-line fields](https://code.claude.com/docs/en/statusline#rate-limit-usage).

The plugin is a small local execution dependency; it requests no model responses and contains no network or credential access code. It is installed at user scope from Meter's local marketplace. This package requires embedded Claude Code 2.1.299 or later; that conservative minimum covers its manifest format. An existing session must reload plugins or restart before the newly installed plugin can run. General chat, Cowork and remote/cloud sessions are outside this integration.

The bridge retains only supported quota values, source and local timestamps in one private file. It does not access credentials or retain session/project metadata. [Setup, coexistence with a custom terminal status line, and removal](INSTALL.md#optional-claude-code-support) are documented in the installation guide.

Meter reads this local file every 15 seconds. Desktop payloads identify `source: desktop` and keep `checkedAt` (bridge liveness) separate from `observedAt` (quota change or measurement event). Accepted identical cache checks update only `checkedAt`; **Synced** reports that connection time, with both times and unknown server freshness in the tooltip. A connection silent for over ten minutes becomes stale. Terminal/older snapshots use **Captured** and capture age. Reset confirmation is unchanged: passing a scheduled reset still requires new quota data. Multiple sessions share the latest snapshot without account identification. A newly loaded cache may bootstrap only a compatible progression of whole quota windows; decreases or a changed future reset need a matching baseline or a measurement event. Neither the timer nor app refresh independently polls Anthropic or starts a model turn.

Cached checks compare an expected normalized quota baseline so an idle session cannot overwrite a conflicting newer value from another session. A conflict preserves both quota and timestamps; measurement events remain authoritative, and comparison baselines are never persisted. Writers coordinate through a private file lock and atomic replacement, as described in the [bridge trust boundaries](SECURITY.md#claude-bridge-boundaries).

## Remaining scope

Live Desktop Code capture has been checked in one local setup. A complete reset cycle, terminal-session capture and broader version coverage remain to verify. The mods surface is version dependent; a valid installation does not prove that an open session has loaded the plugin or supplied quota. No additional announcement feed, Claude credit ledger, account switcher, automatic model requests or general provider framework is included. These can be evaluated separately if the simple two-service workflow proves useful.

## UX decision — 5 November 2026

Keep both service rows visible so remaining quotas and resets can be compared immediately. Put secondary statistics and Codex-specific content in one expandable detail area at a time. This replaces the initial provider-selector design while preserving the compact rings and their order.

## Verification — 5 November 2026

The offline suite, app build, native light/dark status-appearance checks and synthetic overview rendering passed. Coverage includes independent provider errors, capture timestamps, stale or missing quota, per-provider window selection, expanded details, the Codex-only state and zero credit balances. Accessibility exposes each percentage once. Public screenshots use synthetic values.

The 300-point overview was installed and checked with real readings for both services. Expanding either service kept the other row visible and resized the native panel. The plugin passed synthetic event and installer tests, embedded-CLI 2.1.309 validation, and live activation in an existing Desktop Code session. A real weekly quota reading matched Claude's native usage display and appeared in Meter.

The complete native UI suite passed in an isolated desktop run: panel growth, shrinkage, status-item movement and reopen retained a zero-point menu-bar gap; light/dark status appearance and synthetic rendering checks also passed. The geometry harness now waits for both content size and menu-bar placement to settle. Earlier runs were interrupted by app deactivation; this interactive check requires an uninterrupted logged-in desktop. A complete reset cycle, terminal capture, older macOS versions and broader CLI coverage remain unverified.

These checks describe the initial 0.7.0 integration. The 0.1.1 automatic cache-sync and separate liveness timestamps require their own verification; no new live or test result is implied here.

## Automatic sync follow-up — 5 November 2026

Offline tests cover idle polling, failed captures, interprocess cache conflicts, clock metadata and persisted menu-bar modes. Synthetic rendering and native light/dark status appearance checks passed. The interactive geometry harness closed on app deactivation in this desktop run; it did not complete. The installed panel and its three menu-bar modes were checked manually.

The updated plugin was validated with embedded Claude Code 2.1.309, reloaded in a local Desktop Code session, and produced repeated automatic local syncs without a model prompt from Meter. An unchanged accepted cache poll kept its earlier quota observation time. This verifies delivery of the session's locally available figures; it does not establish an independent server refresh or a complete reset cycle.
