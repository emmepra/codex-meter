# Codex Meter

Read `README.md` for product behavior and `docs/INSTALL.md` for setup.

- Keep the app small and native. Do not add dependencies or background services without a concrete need.
- Keep usage unknown/stale states explicit. Budget calculations use quota points, not tokens or a measured usage history.
- Authentication belongs to the Codex CLI. Never log credentials or raw account responses, start model turns, or redeem reset credits.
- Run `./scripts/test.sh` and `./scripts/build.sh` for code changes. Verify UI changes on macOS when available; distinguish compilation from visual verification.
- Keep public documentation, examples, screenshots and fixtures free of personal paths, account details and real usage snapshots.
