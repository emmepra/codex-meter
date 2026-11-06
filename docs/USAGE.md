# Using Codex Meter

The rings and panel show **used quota**. Remaining quota and the reset countdown appear below each service's bar. These are quota points, not token counts, an API bill, a measured usage history or a productivity score.

## Panel and menu bar

Click the menu-bar item to open the overview. Every monitored service remains visible in the panel, even when its ring is hidden. Choose a quota period from its label when multiple source windows exist; each service remembers its selection. Open **Details** for supporting estimates. Only one service's Details is expanded at a time, and Codex-specific credits, banked resets and Tibo posts stay in Codex Details.

**Options → Menu Bar** saves **Codex and Claude**, **Codex only** or **Claude only**. A choice containing Claude enables its monitoring; Codex only does not stop existing Claude monitoring. **Monitor Claude** controls its reads and panel row. Turning it off returns the menu bar to Codex but leaves the external capture bridge configured. See [bridge removal](INSTALL.md#reading-freshness-and-removal) to stop capture too.

Codex uses teal and Claude terracotta, in both rings and panel bars. When both rings are visible, Codex is left and Claude right. **Ring only** hides numbers. An exclamation mark replaces an uncertain percentage; the tooltip names each service, window and state. Missing values remain unavailable, not zero.

The Codex ring has independent corner dots: green at top left for a fresh positive banked-reset count and amber at bottom right for an unread matching Tibo post. Missing, zero or stale reset counts never produce a green dot. App updates and credit balances add no dot or number. The tooltip includes reset availability and credit balance when supplied.

**Launch at Login** is off until enabled in Options; macOS may require approval. Login launches keep the panel closed. **Automatically Check for Updates** is on by default, checking the latest stable GitHub release at launch and at most every six hours, including after wake. Automatic failures stay quiet. A newer version appears as **Install <version>…** in Options. Manual checking opens the native Sparkle window; installation still requires confirmation and sends no quota or account data. See [updates](INSTALL.md#update).

## Freshness and reset confirmation

Codex reads its installed CLI every three minutes and after wake. **Updated** shows the last successful read. A failed read or more than ten minutes without one marks retained data out of date and pauses estimates. The CLI account can differ from the Codex desktop account.

With **Monitor Claude** enabled, Meter requests subscription usage from the embedded CLI every three minutes, including between Code sessions. A successful direct read shows **Updated**.

For the fallback bridge, version 0.1.1 reads the session's cached usage at startup, on attach and every 60 seconds, alongside quota-measurement events. Meter reads the private local file every 15 seconds. **Synced** reports the last accepted local connection check; a separate observation time records changed quota or a measurement event. Identical cache checks do not renew that observation time. Hover for both times and the source explanation. A connection silent for over ten minutes becomes stale. **Synced does not guarantee a new server response.**

Terminal and older Claude snapshots show **Captured** and use capture age for staleness. A terminal status-line redraw may reuse earlier server data. Several local sessions share the latest snapshot without identifying its account; conflicting idle caches cannot replace newer quota. The bridge timer reads the session cache. [Claude setup and storage](INSTALL.md#optional-claude-code-support) and [source boundaries](SECURITY.md#claude-bridge-boundaries) explain the two routes.

The header refresh button requests Codex and Claude usage immediately. An elapsed reset remains **Reset unconfirmed** until new quota data arrives, even if the Desktop bridge continues checking. Out-of-date data and unconfirmed resets pause estimates. An error in one service does not invalidate the other.

## Banked resets

**Banked resets** in Codex Details shows account-level reset availability, including a confirmed zero. Fresh positive counts are green, zero is red, stale counts are orange and **Unavailable** stays neutral. Unavailable never means zero. A retained count becomes out of date after a failed refresh or more than ten minutes without an update.

This count is separate from the scheduled reset countdown and does not establish that a quota window is eligible for redemption. Redeem resets in Codex; Meter only displays availability. An unconfirmed window reset alone does not make the account-level count stale.

## Credits

When the service supplies credit metadata, **Codex Details** shows the available balance separately from included quota and banked resets. A numeric zero, **Unlimited**, **Unavailable** and **Out of date** are distinct states. Credits remain a balance, without a percentage: the CLI does not supply a reliable total for that calculation. The menu-bar ring continues to show used quota and never appends a credit balance.

**Credits in use** appears only when fresh readings belong to a known personal account, a Codex quota window is exhausted, and the balance has decreased in the last ten minutes. It signals observed balance consumption, not which task was billed; expirations or other adjustments can also lower the balance. An exhausted quota with available credits alone does not activate it. The balance remains available in Details while included quota is still available, without suggesting that credits are being used.

With a zero credit balance, Details shows the balance and omits rate/runway estimates. For a positive balance, **Details** shows **Recent consumption**, the positive net balance decrease per hour over up to 30 minutes of continuous readings, after at least 15 minutes and three samples with a fresh latest reading. **Credit runway** divides the remaining balance by that rate. Observations follow the credit balance independently of quota usage: reaching 100% or returning to included quota does not restart the window. The ten-minute recent-decrease rule applies only to the **Credits in use** cue, not to these statistics.

Details shows **Estimating…** while history is insufficient and **Awaiting balance updates** when the rolling window has no positive decrease. A balance increase, gap longer than ten minutes, failed read, missing numeric balance or change of personal account restarts observations. Stale readings do not produce estimates. Samples are kept only while Meter runs, so restarting starts a new window. These are recent balance observations and constant-pace estimates, not a per-chat ledger, exact billed spend or a countdown of productive work.

The CLI supplies account identity; Meter retains only an in-memory fingerprint and never saves email or credentials. Credit pace requires fresh metadata, an email and a recognized individual plan. Workspace balances can still be shown, but pace estimates remain unavailable until a reliable workspace scope is exposed. No token-to-credit or monetary conversion is inferred.

## Reset posts from Tibo

**Check Tibo’s Reset Posts** in Options is on by default. Meter reads the public RSS feed at `https://x.noodl3.net/thsottiaux/rss` at launch and every 30 minutes, with a due check after wake. This is a third-party Nitter instance, not an official X/OpenAI service; it may be unavailable, delayed or incomplete. The source sees ordinary connection metadata such as the IP address, but Meter sends no account data, quota, cookies or credentials. No X API key, Python runtime or new library is required.

Codex Details shows **𝕏 Tibo** and the date of the newest matching post in the last seven days. It matches the standalone word **reset**, case-insensitively, after removing URLs, and checks the author and post link. Posts from other authors and reposts are ignored. A keyword match does **not** confirm a reset on your account.

A short excerpt appears below the author, with **reset** in bold and ellipses where context is omitted. It keeps whole words, uses up to 72 characters and wraps to at most two lines. For example, using synthetic text:

> … we will **reset** usage limits tomorrow …

- **Read:** recent dates show **Today** or **Yesterday**. Hover for the full date, time and excerpt; click to open the original post on X.
- **Dismiss:** opening the post, clicking its **Mark as seen** checkmark or choosing **Mark Tibo Post as Read** clears the amber dot across restarts. A newer matching post lights it again.
- **Reset-count change:** an increase between two fresh successful quota reads after detecting the post also clears the dot; the link stays visible. Reads must be at most ten minutes apart. This is a dismissal heuristic, not proof that the post caused a reset. An initial positive count, missing/failed reads or a long gap do not establish a connection.
- **Source unavailable:** retained matches are marked **cached** after a failed refresh. **Tibo posts unavailable** distinguishes a failed source without a cached match from no recent match.
- **Control and storage:** disable **Check Tibo’s Reset Posts** to stop fetching and hide the row. Post contents and quota comparisons stay in memory; only the last-read post ID and the feature preference are saved.

## What the statistics mean

These supporting statistics are in each service's collapsible **Details** section.

| In the app | Meaning |
| --- | --- |
| Daily budget / Hourly budget | Remaining quota divided by time until reset. |
| Today, from now | The share of that budget available from now to local midnight. |
| Average / day or / hour | Current consumption divided by elapsed time in the quota window. |
| Runway at this pace | Estimated time to exhaustion at that average pace. |
| Projected at reset | Estimated quota left at reset, shown when the current average pace would leave quota available. |

Percentages are **points of the whole window's quota**. For example, 75% remaining with 3.5 days until reset gives a daily allowance of about **21.4%**.

The window's start is inferred from its duration and reset time. Projections assume a constant pace; they are not measured daily history or a prediction of future work. Estimates wait for enough of the window to elapse, and pause when data is stale or a reset is awaiting confirmation. Missing values are never displayed as zero.

## Data sources and compatibility

Codex Meter starts a short-lived `codex app-server` process and reads `account/read` and `account/rateLimits/read` through its documented local protocol. It uses the CLI's existing login, starts no model turns and never consumes reset credits. If desktop and CLI use different accounts, the app follows the CLI account.

Codex snapshots stay in memory; the optional Claude bridge keeps one sanitized local snapshot. Display, provider, automatic-update and reset-post preferences plus the last-read post ID are saved by the app; macOS manages the login item. Authentication remains with the official CLIs; no tokens are copied into this project.

See the [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt). Compatibility has been checked with Codex CLI 0.153.0.

The reset-count field has been verified in the generated protocol schema for CLI 0.155.0-alpha.16, with synthetic payload tests. Its earliest supported stable CLI version and live availability across accounts have not been verified. Older CLIs that omit the field continue to show ordinary quota data, with reset availability shown as **Unavailable**.

See [provider design and verification](PROVIDERS.md) for observed compatibility and remaining coverage, and [security boundaries](SECURITY.md) for storage and trust details. A complete reset cycle, terminal-session capture and broader version coverage remain unverified.
