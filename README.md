![Codex Meter — Know your limits. Pace your work.](assets/banner.png)

# Codex Meter

A small native macOS menu bar app for checking Codex usage and pacing the quota you have left.

- **At a glance:** a tiny ring and consumed percentage, with an optional ring-only mode.
- **One click:** remaining quota, reset countdown and exact reset time.
- **Plan your usage:** daily or hourly allowance, today's budget, average pace and estimated runway.
- **Lightweight:** AppKit + SwiftUI, no external app dependencies. The Codex reader runs only during refreshes.

![Codex Meter menu bar panel with synthetic demonstration values](assets/codex-meter-demo.png)

The example above uses synthetic values; it does not show an account's actual usage.

This is an independent project, not affiliated with OpenAI.

## Login & privacy

Sign in with the official Codex CLI using ChatGPT before opening Meter. You do not give Codex Meter an account, password or API key. The CLI account may be different from the account signed in to the Codex desktop app; Meter reads whichever account the CLI uses. API billing is outside Meter's scope.

Meter asks the locally launched CLI for quota and reset information through `account/rateLimits/read` over standard input/output, then closes that process. The app has no Meter backend or telemetry code. Usage snapshots stay in memory; only the selected quota window and ring-only display preference are saved. Codex CLI manages its own network access, authentication and any logs it writes.

Meter can use a standalone Codex CLI or the CLI bundled with the Codex desktop app. It checks the desktop app directly if a standalone CLI path is unavailable, including when an app update leaves an old symlink behind.

The displayed percentages are quota points, not token counts. Budget allowance is remaining quota divided by time to reset; runway and reset projections assume the current average pace. These figures are not a history of actual usage or a measure of productivity.

## Install

You need an **Apple Silicon Mac**, macOS **13 or later**, and the **Codex CLI signed in with ChatGPT**.

1. Open the [latest release](https://github.com/emmepra/codex-meter/releases/latest) and download the **Apple Silicon ZIP** under **Assets**.
2. Unzip it and move **Codex Meter.app** to your Applications folder.
3. Open the app. No compiler or source checkout is needed.

The app is **ad hoc signed**, without an Apple Developer ID signature or notarization, so Gatekeeper may block the first launch. The [installation guide](docs/INSTALL.md#first-launch) explains Apple's **Open Anyway** procedure, along with [CLI setup](docs/INSTALL.md#install-codex-cli-and-sign-in), [building from source](docs/INSTALL.md#build-from-source-alternative), updates and troubleshooting.

## Use

Click the menu bar indicator to open the compact panel, anchored directly below the menu bar even when its content changes height. The ring and menu bar percentage show **used quota**; the larger percentage in the panel shows **remaining quota**. **Resets in** shows the time until the next reset.

The **Options** (`…`) menu contains **Ring only**, available quota windows, **Refresh** and **Quit**. Usage refreshes every three minutes and after wake; the arrow refreshes immediately. Automatic launch at login is not enabled.

**Usage limit resets** shows the number of banked resets available to the Codex CLI account, including a confirmed zero. **Unavailable** means the CLI/service did not provide a valid count; **Out of date** marks a retained count after a failed refresh or more than ten minutes without an update. This account-level count is separate from the scheduled **Resets in** countdown and does not imply that a window is eligible for redemption. Redeem resets in Codex; Meter only displays availability.

### What the statistics mean

| In the app | Meaning |
| --- | --- |
| Daily budget / Hourly budget | Remaining quota divided by time until reset. |
| Today, from now | The share of that budget available from now to local midnight. |
| Average / day or / hour | Current consumption divided by elapsed time in the quota window. |
| Runway at this pace | Estimated time to exhaustion at that average pace. |
| Projected at reset | Estimated quota left at reset, shown when the current average pace would leave quota available. |

Percentages are **points of the whole window's quota**. For example, 75% remaining with 3.5 days until reset gives a daily allowance of about **21.4%**.

The window's start is inferred from its duration and reset time. Projections assume a constant pace; they are not measured daily history or a prediction of future work. Estimates wait for enough of the window to elapse, and pause when data is stale or a reset is awaiting confirmation. Missing values are never displayed as zero.

## How it works

Codex Meter starts a short-lived `codex app-server` process and reads `account/rateLimits/read` through its documented local protocol. It uses the CLI's existing login, starts no model turns and never consumes reset credits. If desktop and CLI use different accounts, the app follows the CLI account.

Usage snapshots stay in memory. Only display preferences are saved by the app. Authentication remains managed by Codex; no tokens are copied into this project.

See the [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt). Compatibility has been checked with Codex CLI 0.153.0.

The reset-count field has been verified in the generated protocol schema for CLI 0.155.0-alpha.16, with synthetic payload tests. Its earliest supported stable CLI version and live availability across accounts have not been verified. Older CLIs that omit the field continue to show ordinary quota data, with reset availability shown as **Unavailable**.

## Develop

```sh
./scripts/test.sh       # Offline model, budget, geometry and process-lifecycle tests
./scripts/test-ui.sh    # Native window layout checks; briefly shows synthetic UI
./scripts/build.sh      # .build/Codex Meter.app
".build/Codex Meter.app/Contents/MacOS/CodexMeter" --check  # Live read, no UI
```

Source is split into the menu bar UI and panel positioning, CLI client, usage decoder and budget calculations under `Sources/`. Tests use synthetic data and local stub processes; they do not need a Codex login or network access. The optional UI tests require a logged-in macOS desktop and check actual window coordinates after content growth, shrinkage and menu bar item movement.

Builds target macOS 13+ and have been tested locally on macOS 26.6.2. A complete live reset cycle and older macOS releases have not yet been exercised.

## Contributing

Use an [issue](https://github.com/emmepra/codex-meter/issues/new/choose) to report a bug or propose a change. Include the macOS and Codex CLI versions in bug reports.

To contribute code, fork the repository, create a branch and open a pull request. Changes go through maintainer review and CI before merging. See [CONTRIBUTING.md](CONTRIBUTING.md) for the steps and checks.

## Releases

Versioning, packaging and the tag-triggered GitHub Actions workflow are described in the [release guide](docs/RELEASING.md).

## License

[MIT](LICENSE). The README banner was generated with AI; its [prompt and provenance](assets/banner-prompt.md) are included.
