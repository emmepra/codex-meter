# Install Codex Meter

Download the app from GitHub Releases, or build it from source.

## Requirements

- An Apple Silicon Mac with macOS 13 or later. Local app testing has been on macOS 26.6.2; Intel builds and older macOS releases have not been verified.
- Codex CLI installed and signed in with the ChatGPT account whose quota you want to monitor.
- Optional Claude support needs a local Claude Code subscription session and the bridge setup below. This Desktop plugin package requires embedded Claude Code 2.1.299 or later; check `/status` in the Code tab.

The downloaded app does not require Xcode, a Swift compiler or a source checkout. Building from source additionally requires Git and Xcode Command Line Tools with Swift 5.9 or later.

## Login & privacy

Meter uses the official Codex CLI login; you do not give the project an account, password or API key. It reads quota and reset details through a short-lived local CLI process and has no Meter backend or telemetry. Codex usage and up to 30 minutes of recent credit samples stay in memory. Display and provider preferences, automatic-update and reset-post preferences plus the last-read post ID are saved; Codex CLI manages its own network access, authentication and logs. The optional Claude bridge saves one sanitized quota snapshot locally, as described below. See the [README's privacy details](../README.md#privacy). The CLI account can differ from the Codex desktop account.

## Install Codex CLI and sign in

If you use Homebrew:

```sh
brew install --cask codex
```

Alternatively, with npm already installed:

```sh
npm install -g @openai/codex
```

These installation methods are documented in the [official OpenAI CLI guide](https://learn.chatgpt.com/docs/codex/cli). Skip installation if `codex --version` already works.

Sign in and confirm the authentication method:

```sh
codex login
codex login status
```

Complete the browser flow using your ChatGPT account. Authentication is managed by Codex itself; see [OpenAI's authentication documentation](https://learn.chatgpt.com/docs/auth).

## Download and install

1. Open the [latest release](https://github.com/emmepra/codex-meter/releases/latest).
2. Under **Assets**, download the **Apple Silicon ZIP** containing the app. GitHub's separate **Source code** archives contain the source project, not a ready-to-run app.
3. Double-click the ZIP in Finder to extract **Codex Meter.app**.
4. Move the app to **Applications**, or to `~/Applications` for an installation in your own user folder.
5. Open **Codex Meter.app** and follow the [first-launch instructions](#first-launch) if macOS blocks it.

The release app is ad hoc signed. It has no Apple Developer ID signature and is not notarized. Installation does not sign in to Codex or enable launch at login.

## Build from source (alternative)

Install Apple's Command Line Tools if needed, then check the compiler:

```sh
xcode-select --install
xcrun swiftc --version
```

If the tools are already installed, skip the first command.

In the folder where you keep source projects:

```sh
git clone https://github.com/emmepra/codex-meter.git
cd codex-meter
./scripts/install.sh
open "$HOME/Applications/Codex Meter.app"
```

The installer runs `scripts/build.sh`, verifies the app's local code signature, and copies it to `~/Applications/Codex Meter.app`. It does not require administrator access for this destination. It stops if Codex Meter is running: open the app's **Options** (`…`) menu, select **Quit**, then retry. The installer does not quit apps, sign in, or enable launch at login.

To select another destination directory:

```sh
./scripts/install.sh --destination "/path/to/Applications"
```

Choose a directory you can write to. The installer adds `Codex Meter.app` inside it.

To build and run directly from the checkout instead:

```sh
./scripts/build.sh
open ".build/Codex Meter.app"
```

The app uses ad hoc signing for local use and is not notarized. Build output is kept in `.build/`.

## First launch

Gatekeeper may block the downloaded app because it has no Developer ID signature or notarization. If you trust the copy downloaded from this repository's release, first try opening it, then open **System Settings → Privacy & Security**. Find the blocked-app notice, choose **Open Anyway**, and confirm **Open** in the next prompt. See [Apple's guide to safely opening apps](https://support.apple.com/en-us/102445) for the current instructions.

Codex Meter appears in the menu bar without a Dock icon. Click the small ring to open the overview; the used percentage is centered inside the ring, and **Ring only** hides that number. The 300-point panel always shows one compact row per enabled service: Codex, plus Claude when **Monitor Claude** is on. Each row includes its name, period, used quota and bar, remaining share and reset countdown. No service tabs are needed. Open a row's **Details** for budgets and pace; at most one service's Details stays open. Codex Details also contains credits, banked resets and Tibo posts. Compact cues remain visible when attention is needed.

Each row shows relative freshness with **Updated** for Codex, **Synced** for a Desktop bridge check, or **Captured** for terminal and older Claude snapshots. Hover for exact check/observation times and the source explanation. These local times are separate from the quota window's scheduled reset.

Missing quota is shown as unavailable, never as zero. A reported zero remains a valid reading. Out-of-date values and unconfirmed resets are marked explicitly and pause estimates; one service's state does not invalidate the other. Use the shared header's refresh button to read Codex and the latest local Claude capture.

See [Credits](USAGE.md#credits) for balance states, recent-consumption calculations, account scope and estimate limits.

**Banked resets** in Codex Details shows banked resets for the Codex CLI account. A fresh positive count is green; zero is red. Out-of-date counts remain orange, and **Unavailable** is distinct from zero.

The **Options** (`…`) menu contains:

| Menu item | Action |
| --- | --- |
| Menu Bar | Choose Codex and Claude, Codex only or Claude only rings |
| Ring only | Hide the number; keep the ring and any indicator |
| Monitor Claude | Read Claude usage and include its row in the panel |
| Set Up Claude… | Configure the bridge when Claude is enabled |
| Launch at Login | Enable or disable the native macOS login item |
| Check Tibo’s Reset Posts | Enable or disable the Codex reset-post feed |
| Automatically Check for Updates | Check silently at launch and every six hours |
| Check for Updates… | Check now and display the result |
| Install <version>… | Open the native update window for the available release |
| Open Repository | Open the project on GitHub |
| Quit | Close Codex Meter |

**Launch at Login** is off until selected. If approval is required, choose **Approve Launch at Login…** and allow the app in macOS Login Items. Keep the app in Applications; login launches do not open the panel.

**Menu Bar** saves the ring display independently of monitoring. **Codex and Claude** and **Claude only** enable Claude monitoring when selected; **Codex only** leaves it running if already enabled. The panel continues to show every monitored service. Turning **Monitor Claude** off stops Meter's Claude reads and returns the rings to Codex.

When a service supplies more than one quota window, click its visible period label to choose a window. Codex and Claude remember their choices separately. Read the [statistics guide](USAGE.md#what-the-statistics-mean) for budget calculations and their limits.

## Optional Claude Code support

Claude support is optional. Sign in through Claude Code's own flow. Meter connects to local Code sessions in two ways: a small plugin for Claude Desktop's **Code** tab, or a status-line command for terminal Claude Code. Neither route reads OAuth tokens or starts model tasks. General Claude chat, Cowork and remote/cloud sessions are outside this integration.

Install Meter in a stable Applications location first. Enable **Options → Monitor Claude**, then choose **Set Up Claude… → Enable Bridge**. Setup selects the Desktop plugin when a compatible Desktop installation is available, with the terminal status line as a fallback. The setup result identifies the configured route.

Alternatively, run Meter's executable to configure the bridge:

```sh
"/Applications/Codex Meter.app/Contents/MacOS/CodexMeter" --install-claude-bridge
```

Adjust the path for a different install location, such as `~/Applications`. Keep the app at this path, or rerun setup after moving it. Setup does not sign in, send prompts or request model responses.

### Desktop Code sessions

**Upgrading from 0.7.0:** after updating Meter, choose **Set Up Claude…** once to install bridge 0.1.1, then run `/reload-plugins` in an open Code session or start a new local session. Updating the app alone does not replace the external plugin. Existing authentication and unrelated configuration are retained.

The Desktop route installs `codex-meter-claude@codex-meter-local` at user scope from a local marketplace bundled with Meter. It uses the official [Claude Code mods interface](https://code.claude.com/docs/en/plugins/mods/overview), which runs inside a local Code session. Bridge 0.1.1 reads cached session usage at startup and on attach, receives quota-measurement events, and checks the cache every 60 seconds using a [session timer](https://code.claude.com/docs/en/plugins/mods/api#run-work-in-the-background). It starts no model turns and contains no prompt, transcript, authentication or direct network request code.

Setup copies the bundled marketplace to `~/Library/Application Support/Codex Meter/ClaudeDesktopBridge` and sets the installed Meter executable path in that private copy. It uses Claude Code's own validation, marketplace-add and user-scope plugin-install and plugin-enable commands. Before those commands change configuration, setup saves existing `~/.claude/settings.json`, `~/.claude/plugins/known_marketplaces.json` and `~/.claude/plugins/installed_plugins.json`, plus any previous Meter bridge source, under `~/Library/Application Support/Codex Meter/bridge-backup-<id>/`. Backup directories use mode `0700` and copied configuration files `0600`; authentication files are not copied.

Explicit setup enables the Meter plugin even if it was disabled before. If setup fails before registration, the previous plugin source is restored. Once registration has been attempted, valid bridge files and private backups are retained so a partially registered marketplace never points to removed source. Setup reports the failure and can be retried; it does not blindly restore shared Claude configuration over later changes.

After setup, run `/reload-plugins` in an open Code session or open a new local Code session. [Shell-installed plugins load on reload or the next session](https://code.claude.com/docs/en/plugins/install#install-from-your-shell). A configured terminal `statusLine` does not run in the Desktop Code surface. If Claude remains unavailable, check that the plugin is enabled, reload it, and confirm the embedded Claude Code version with `/status`. Organization policy or disabled hooks can prevent it from loading.

When replacing an older bridge, run **Set Up Claude…** again and reload plugins so the open session loads the bundled version. The once-a-minute check runs only while that local session and plugin are active. It reads Claude Code's cache; it cannot force a fresh server quota response.

The mods surface is version dependent. Live Desktop quota capture has been checked with embedded CLI 2.1.309; full reset-cycle verification remains pending. Installing and validating a plugin alone does not prove it has loaded or received quota in an existing session.

### Terminal Code sessions

The terminal route adds Meter's capture command to `statusLine` in `~/.claude/settings.json`, preserving other settings. Before changing an existing file, it saves the original bytes beside it as `settings.codex-meter-backup-<id>.json`. It refuses to replace an unrelated status-line command. A previous Meter-generated command can be updated when its executable moves.

If you already have a custom status line, keep it and add Meter's capture command inside your existing script. Read stdin once and pass the same payload to both commands, suppressing only Meter's output. For a Bash status-line script, the additional capture can look like this after reading stdin into a variable named `status_payload`:

```sh
printf '%s' "$status_payload" | "/Applications/Codex Meter.app/Contents/MacOS/CodexMeter" --capture-claude-usage >/dev/null
```

Your existing display command must also read `status_payload`; it cannot read stdin a second time. Do not write the raw payload to a file: it can include session and project information. Project-level status-line settings can override the user setting.

Quota fields in the [status-line data](https://code.claude.com/docs/en/statusline#rate-limit-usage) may be absent until the session receives its first API response. Open or continue your terminal session normally; Meter does not create a model request to populate the fields.

### Reading freshness and removal

Claude's row stays visible beside Codex in Meter's panel. Meter rereads the local file every 15 seconds; the shared header's refresh button reads it immediately. Neither asks Anthropic for a new reading. Open Claude Details for budget and pace estimates.

**Synced** uses the Desktop payload's `checkedAt`: the last successful local bridge check. Its separate `observedAt` records a quota change or measurement event. Identical cached checks update the connection time without advancing the quota-observation time. The tooltip shows both and explains that server freshness is unknown. Desktop data becomes out of date if this connection stops for more than ten minutes. A reported reset still waits for new data after its scheduled time; a continuing bridge check does not confirm it.

Terminal and older snapshots retain **Captured** and become out of date by capture age. A terminal status-line redraw may reuse earlier server data. Missing data remains unavailable. Out-of-date data and unconfirmed resets pause estimates.

Both routes store only supported source/timestamp metadata and the five-hour/weekly quota fields in `~/Library/Application Support/Codex Meter/claude-usage.json`, using a private file. They store no prompts, transcript paths, session identifiers, account identifiers or credentials. Multiple local sessions share the latest snapshot, without identifying its account. Claude credit billing, reset banks and announcement feeds are outside this integration.

To hide only Claude's ring, choose **Menu Bar → Codex only**; monitoring and its panel row remain enabled. To stop Meter's Claude reads and remove its panel row, turn off **Monitor Claude**. This leaves capture configured. To stop Desktop capture, disable or uninstall `codex-meter-claude@codex-meter-local` in Claude Code's plugin manager, then reload plugins or start a new session. To stop terminal capture, remove only Meter's `statusLine` entry from `~/.claude/settings.json`, or remove its capture call from your existing script. You may then delete `claude-usage.json`. Preserve unrelated settings and any later changes when using a backup.

### Reset posts from Tibo

Optional Tibo notices remain in Codex Details, with an unread cue in the overview. The [usage guide](USAGE.md#reset-posts-from-tibo) covers the third-party feed, keyword matching, privacy, cached states and dismissal behavior. A matching post does not confirm an account reset.

## Check a problem

To check the installed app's connection without opening its interface, run its executable with `--check`:

```sh
"/Applications/Codex Meter.app/Contents/MacOS/CodexMeter" --check
```

Adjust the path if you installed it elsewhere, for example to `$HOME/Applications/Codex Meter.app/Contents/MacOS/CodexMeter`.

From a source checkout, after building, you can also run the offline tests:

```sh
./scripts/test.sh
".build/Codex Meter.app/Contents/MacOS/CodexMeter" --check
```

The tests use synthetic data without login or network access. `--check` makes a real quota read and prints the quota/reset or a short error; it does not open the interface or start a model task.

If the CLI is not found, check `command -v codex`. Codex Meter checks `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, its inherited `PATH`, and the CLI bundled with the Codex desktop app. Finder-launched apps may have a different `PATH` from Terminal, especially with Node version managers. Meter skips broken CLI symlinks, which can occur after a desktop app update, and checks the installed desktop app directly. If neither installation is found, install or update the Codex CLI or desktop app, then refresh.

If sign-in is required, run `codex login` and click the refresh button in Meter's shared header. If an error persists, check that the CLI works and that your network connection is available. Unknown quota values remain unavailable; an old value after a failed refresh is marked as stale.

If **Banked resets** shows **Unavailable**, the CLI/service did not return a valid reset count. This does not mean you have zero resets. The field is confirmed in CLI 0.155.0-alpha.16's generated schema; the minimum stable CLI version and account-specific availability are not yet verified. Ordinary quota display still works when this optional field is absent. **Out of date** means the last known count needs a successful refresh. Meter cannot redeem resets.

## Update

From **0.5.3**, choose **Options → Check for Updates…** or **Install <version>…** when shown. In the native update window, confirm download and installation; Sparkle verifies the signed update, replaces the app and relaunches it. Keep Meter in Applications. Your display preferences are preserved.

**Versions 0.5.2 and earlier require one manual upgrade.** Quit Codex Meter using **Options → Quit** before replacing the app. The same manual procedure can be used if an in-app update is unavailable.

For a downloaded installation, download the Apple Silicon ZIP from the [latest release](https://github.com/emmepra/codex-meter/releases/latest), extract it, and move the new **Codex Meter.app** into the same Applications folder, replacing the previous copy. Open the new app; macOS may ask you to confirm it again. Display preferences are preserved.

For a source installation, run these commands in your checkout:

```sh
git pull --ff-only
./scripts/install.sh
open "$HOME/Applications/Codex Meter.app"
```

Reuse `--destination` if you chose a custom install folder. If Git reports local changes or diverging history, resolve those changes before updating.

Codex CLI updates are separate. Use the package manager you originally chose: `brew upgrade --cask codex` or `npm install -g @openai/codex`. These are the update commands in the [official CLI guide](https://learn.chatgpt.com/docs/codex/cli).

### Compact menu bar and project links

With Codex alone, the menu bar shows the used quota as a number inside the ring (the percent sign is omitted for readability). Two independent corner dots surround the Codex ring: green at top left for fresh positive reset availability, and amber at bottom right for an unread Tibo post mentioning **reset**. App updates do not light a dot. They can appear together. Missing, zero or stale reset counts never produce a green dot. Options shows **Install <version>…** when a release is available. Credits add no number or indicator to the menu bar; the tooltip includes the exact reset count and credit balance when available. Ring-only mode hides the number, retaining the reset and unread-post indicators.

The overview header shows **Codex Meter** beside the app mark, with refresh and Options. Each service row has its own **Details** control and relative **Updated**, **Synced** or **Captured** time; hover for exact local times and the source explanation. Budget values use the system primary text color for light and dark appearance. The app bundle includes a dedicated meter icon, also used in update dialogs.

**Automatically Check for Updates** is on by default. It checks the latest stable GitHub release at app launch and then at most every six hours while running, including after wake. Disable it in Options for manual-only checks. Automatic checks are silent, including network failures. **Check for Updates…** still checks immediately and displays the result. It sends no quota or account data. From version 0.5.3, **Check for Updates…** or **Install <version>…** opens the native Sparkle update window. Confirm the download and installation there; Sparkle verifies the signed feed and archive, replaces the app and relaunches it. Installation always requires your confirmation.

## Uninstall

Choose **Options → Quit**, then move **Codex Meter.app** from its installation folder to the Trash in Finder. This may be `/Applications`, `~/Applications`, or a custom destination.

If you enabled Claude capture, first remove its status-line entry or wrapper call as described [above](#optional-claude-code-support), so Claude Code does not invoke a removed app. The sanitized `claude-usage.json` file may also be deleted.

Removing the app leaves the official CLIs, their sign-in credentials and configuration, and your source checkout in place. There is no need to run `codex logout` or remove `~/.codex`. Codex Meter's small display preferences remain available if you reinstall it.
