# Install Codex Meter

Download the app from GitHub Releases, or build it from source.

## Requirements

- An Apple Silicon Mac with macOS 13 or later. Local app testing has been on macOS 26.6.2; Intel builds and older macOS releases have not been verified.
- Codex CLI installed and signed in with the ChatGPT account whose quota you want to monitor.

The downloaded app does not require Xcode, a Swift compiler or a source checkout. Building from source additionally requires Git and Xcode Command Line Tools with Swift 5.9 or later.

## Login & privacy

Meter uses the official Codex CLI login; you do not give the project an account, password or API key. It reads quota and reset details through a short-lived local CLI process and has no Meter backend or telemetry. Usage stays in memory and only display and automatic-update preferences are saved; Codex CLI manages its own network access, authentication and logs. See the [README's privacy details](../README.md#login--privacy) and the next section for setup. The CLI account can differ from the Codex desktop account.

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

Codex Meter appears in the menu bar without a Dock icon. Click the small ring to open the panel; the used percentage is centered inside the ring. **Ring only** hides that number. The larger percentage in the panel is **remaining** quota. **Resets in** shows the reset countdown.

**Usage limit resets** shows banked resets for the Codex CLI account. A fresh count above one is green; one or zero is red. Out-of-date counts remain orange, and **Unavailable** is distinct from zero.

The **Options** (`…`) menu contains:

| Menu item | Action |
| --- | --- |
| Ring only | Hide the number; keep the ring and any indicator |
| Launch at Login | Enable or disable the native macOS login item |
| Automatically Check for Updates | Check silently at launch and every six hours |
| Check for Updates… | Check now and display the result |
| Update to <version>… | Open the available release for manual installation |
| Open Repository | Open the project on GitHub |
| Refresh | Read current usage |
| Quit | Close Codex Meter |

**Launch at Login** is off until selected. If approval is required, choose **Approve Launch at Login…** and allow the app in macOS Login Items. Keep the app in Applications; login launches do not open the panel.

Other available quota windows appear in the same menu. Read the [README](../README.md) for the budget calculations and their limits.

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

If the CLI is not found, check `command -v codex`. Codex Meter looks in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, then its inherited `PATH`. Finder-launched apps may have a different `PATH` from Terminal, especially with Node version managers. A Homebrew installation uses one of the explicit locations.

If sign-in is required, run `codex login` and use **Refresh** in Codex Meter. If an error persists, check that the CLI works and that your network connection is available. Unknown quota values remain unavailable; an old value after a failed refresh is marked as stale.

If **Usage limit resets** shows **Unavailable**, the CLI/service did not return a valid reset count. This does not mean you have zero resets. The field is confirmed in CLI 0.155.0-alpha.16's generated schema; the minimum stable CLI version and account-specific availability are not yet verified. Ordinary quota display still works when this optional field is absent. **Out of date** means the last known count needs a successful refresh. Meter cannot redeem resets.

## Update

Quit Codex Meter using **Options → Quit** before replacing the app.

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

The menu bar shows the used quota as a number inside the ring (the percent sign is omitted for readability). A blue dot takes priority when an update is available; Options shows **Update to <version>…** with a link to the release. Otherwise, a green dot appears only when fresh data reports at least one available usage-limit reset. When no update is known, the dot is hidden for zero, missing, or stale reset counts. The tooltip includes the exact count. Ring-only mode hides the number, retaining any update or reset indicator.

The panel header shows the OpenAI mark beside Codex Meter. The text-only Codex Meter footer links to the repository. Budget values use the system primary text color for light and dark appearance. The app bundle includes a dedicated meter icon, also used in update dialogs.

**Automatically Check for Updates** is on by default. It checks the latest stable GitHub release at app launch and then at most every six hours while running, including after wake. Disable it in Options for manual-only checks. Automatic checks are silent, including network failures. **Check for Updates…** still checks immediately and displays the result. It sends no quota or account data. An available update opens its release page for manual download and installation; the app does not replace itself automatically.

## Uninstall

Choose **Options → Quit**, then move **Codex Meter.app** from its installation folder to the Trash in Finder. This may be `/Applications`, `~/Applications`, or a custom destination.

This removes Codex Meter only. The Codex CLI, its sign-in credentials and configuration, and your source checkout remain in place. There is no need to run `codex logout` or remove `~/.codex`. Codex Meter's small display preferences remain available if you reinstall it.
