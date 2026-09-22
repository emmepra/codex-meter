![Codex Meter — Know your limits. Pace your work.](assets/banner.png)

# Codex Meter

A small native macOS menu bar app for checking Codex usage and pacing the quota you have left.

- **At a glance:** a tiny ring and consumed percentage, with an optional ring-only mode.
- **One click:** remaining quota, reset countdown and exact reset time.
- **Plan your usage:** daily or hourly allowance, today's budget, average pace and estimated runway.
- **Lightweight:** AppKit + SwiftUI, no external app dependencies. The Codex reader runs only during refreshes.

The interface is currently in Italian. This is an independent project, not affiliated with OpenAI.

## Install

You need an **Apple Silicon Mac**, macOS **13 or later**, current Xcode Command Line Tools, and the **Codex CLI signed in with ChatGPT**.

```sh
git clone https://github.com/emmepra/codex-meter.git
cd codex-meter
./scripts/install.sh
open "$HOME/Applications/Codex Meter.app"
```

The installer builds the app locally. See the [installation guide](docs/INSTALL.md) for prerequisites, custom destinations, updates and troubleshooting. Builds are locally signed; no notarized binary release is provided.

## Use

Click the menu bar indicator to open the compact panel. The ring and menu bar percentage show **consumed quota**; the larger percentage in the panel shows **remaining quota**.

The `…` menu contains **Solo anello nella barra** (ring only), available quota windows, refresh and **Esci** (quit). Usage refreshes every three minutes and after wake; the arrow refreshes immediately. Automatic launch at login is not enabled.

### What the statistics mean

| In the app | Meaning |
| --- | --- |
| Budget al giorno / all'ora | Remaining quota divided by time until reset. |
| Oggi, da ora | The share of that budget available from now to local midnight. |
| Media del periodo | Current consumption divided by elapsed time in the quota window. |
| Autonomia a questo ritmo | Estimated time to exhaustion at that average pace. If quota would last, the panel shows the projected amount left at reset instead. |

Percentages are **points of the whole window's quota**. For example, 75% remaining with 3.5 days until reset gives a daily allowance of about **21.4%**.

The window's start is inferred from its duration and reset time. Projections assume a constant pace; they are not measured daily history or a prediction of future work. Estimates wait for enough of the window to elapse, and pause when data is stale or a reset is awaiting confirmation. Missing values are never displayed as zero.

## How it works

Codex Meter starts a short-lived `codex app-server` process and reads `account/rateLimits/read` through its documented local protocol. It uses the CLI's existing login, starts no model turns and never consumes reset credits. If desktop and CLI use different accounts, the app follows the CLI account.

Usage snapshots stay in memory. Only display preferences are saved by the app. Authentication remains managed by Codex; no tokens are copied into this project.

See the [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt). Compatibility has been checked with Codex CLI 0.153.0.

## Develop

```sh
./scripts/test.sh       # Offline model, budget and process-lifecycle tests
./scripts/build.sh      # .build/Codex Meter.app
".build/Codex Meter.app/Contents/MacOS/CodexMeter" --check  # Live read, no UI
```

Source is split into the menu bar UI, CLI client, usage decoder and budget calculations under `Sources/`. Tests use synthetic data and local stub processes; they do not need a Codex login or network access.

Builds target macOS 13+ and have been tested locally on macOS 26.6.2. A complete live reset cycle and older macOS releases have not yet been exercised. Issues and small, focused pull requests are welcome; include the macOS and Codex CLI versions when reporting a bug.

## License

[MIT](LICENSE). The README banner was generated with AI; its [prompt and provenance](assets/banner-prompt.md) are included.
