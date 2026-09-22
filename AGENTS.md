# Codex Meter

Read `README.md` for product behavior, `docs/INSTALL.md` for setup, and `CONTRIBUTING.md` for changes.

- Use English for app text, documentation, issues and pull requests.
- Submit changes through a pull request; `main` requires the GitHub Actions `build` check. Follow `docs/RELEASING.md` for versions and tags.

- Keep the app small and native. Do not add dependencies or background services without a concrete need.
- Keep usage unknown/stale states explicit. Budget calculations use quota points, not tokens or a measured usage history.
- Authentication belongs to the Codex CLI. Never log credentials or raw account responses, start model turns, or redeem reset credits.
- Run `./scripts/test.sh` and `./scripts/build.sh` for code changes. Verify UI changes on macOS when available; distinguish compilation from visual verification.
- Keep public documentation, examples, screenshots and fixtures free of personal paths, account details and real usage snapshots.
