# Install Codex Meter

Build the app locally from source. The interface is currently in Italian; this guide names the relevant menu items.

## Requirements

- An Apple Silicon Mac. The build targets macOS 13 or later; local testing has been on macOS 26.6.2. Intel builds and older macOS versions have not been verified.
- Xcode Command Line Tools with Swift 5.9 or later.
- Git.
- Codex CLI installed and signed in with the ChatGPT account whose quota you want to monitor.

Install Apple's Command Line Tools if needed, then check the compiler:

```sh
xcode-select --install
xcrun swiftc --version
```

If the tools are already installed, skip the first command.

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

Complete the browser flow using your ChatGPT account. Codex Meter reads the account-wide ChatGPT quota exposed by the CLI; API billing is outside its scope. The CLI account may differ from the account in your desktop app. Authentication is managed by Codex itself; see [OpenAI's authentication documentation](https://learn.chatgpt.com/docs/auth).

## Build and install

In the folder where you keep source projects:

```sh
git clone https://github.com/emmepra/codex-meter.git
cd codex-meter
./scripts/install.sh
open "$HOME/Applications/Codex Meter.app"
```

The installer runs `scripts/build.sh`, verifies the app's local code signature, and copies it to `~/Applications/Codex Meter.app`. It does not require administrator access for this destination. It stops if Codex Meter is running: open the app's `…` menu, select **Esci** (Quit), then retry. The installer does not quit apps, sign in, or enable launch at login.

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

Codex Meter appears in the menu bar without a Dock icon. Click the small ring and percentage to open the panel. The percentage in the menu bar is **consumed** quota; **disponibile** in the panel is the remaining quota.

The `…` menu contains:

| Italian label | Meaning |
| --- | --- |
| Solo anello nella barra | Show only the ring in the menu bar |
| Aggiorna | Refresh now |
| Esci | Quit |

Other available quota windows appear in the same menu. Read the [README](../README.md) for the budget calculations and their limits.

## Check a problem

From the source checkout, after building:

```sh
./scripts/test.sh
".build/Codex Meter.app/Contents/MacOS/CodexMeter" --check
```

The tests use synthetic data without login or network access. `--check` makes a real quota read and prints the quota/reset or a short error; it does not open the interface or start a model task.

If the CLI is not found, check `command -v codex`. Codex Meter looks in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, then its inherited `PATH`. Finder-launched apps may have a different `PATH` from Terminal, especially with Node version managers. A Homebrew installation uses one of the explicit locations.

If sign-in is required, run `codex login` and use **Aggiorna** in Codex Meter. If an error persists, check that the CLI works and that your network connection is available. Unknown quota values remain unavailable; an old value after a failed refresh is marked as stale.

## Update

Quit Codex Meter using **… → Esci**, then run these commands in your checkout:

```sh
git pull --ff-only
./scripts/install.sh
open "$HOME/Applications/Codex Meter.app"
```

Reuse `--destination` if you chose a custom install folder. If Git reports local changes or diverging history, resolve those changes before updating.

Codex CLI updates are separate. Use the package manager you originally chose: `brew upgrade --cask codex` or `npm install -g @openai/codex`. These are the update commands in the [official CLI guide](https://learn.chatgpt.com/docs/codex/cli).

## Uninstall

Choose **… → Esci**, then move `~/Applications/Codex Meter.app` to the Trash in Finder. For a custom installation, remove the app from that destination instead.

This removes Codex Meter only. The Codex CLI, its sign-in credentials and configuration, and your source checkout remain in place. There is no need to run `codex logout` or remove `~/.codex`. Codex Meter's small display preferences remain available if you reinstall it.
