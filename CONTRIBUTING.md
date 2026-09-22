# Contributing to Codex Meter

Bug reports, small fixes, documentation improvements and usability feedback are
welcome. Use English for the app, documentation, issues and pull requests.

## Choose a change

Search existing [issues](https://github.com/emmepra/codex-meter/issues) first.
Use the [bug report or feature proposal forms](https://github.com/emmepra/codex-meter/issues/new/choose)
to describe a problem. For a larger feature or architectural change, discuss the
scope in an issue before investing in implementation. A small fix or typo can go
directly to a pull request; no separate issue is required.

Good starting points include reproducing an open bug, improving setup instructions
and reporting UI behavior on a macOS version or display setup you can test.

## Fork, implement, test

You do not need write access to this repository. Fork it on GitHub, then clone
your fork and create a branch (replace `YOUR-GITHUB-USERNAME` below):

```sh
git clone https://github.com/YOUR-GITHUB-USERNAME/codex-meter.git
cd codex-meter
git remote add upstream https://github.com/emmepra/codex-meter.git
git switch -c describe-your-change
```

See [installation](docs/INSTALL.md) for build requirements. Keep each change
focused and keep documentation consistent with implemented behavior. Preserve
unknown and stale quota states, and keep the app small and native.

For code changes, run:

```sh
./scripts/test.sh
./scripts/build.sh
```

These checks need no Codex login or network access. For UI changes, also run
`./scripts/test-ui.sh` on a logged-in macOS desktop and inspect the changed UI.
State what you actually verified, including missing hardware or macOS coverage.
Tests and screenshots should use synthetic data. Never attach credentials,
raw account responses, personal paths, or real usage snapshots to a public report.

## Open a pull request

Commit your change and push its branch to your fork:

```sh
git push -u origin HEAD
```

Open a pull request against `emmepra/codex-meter:main`. The template asks for the
problem, resulting behavior, verification and any limitations. Link a related
issue if there is one. Use a draft PR if you want feedback before it is ready.
Do not bump `VERSION`, create release tags or upload app binaries for an ordinary
contribution; the maintainer handles release preparation.

GitHub Actions runs the offline tests, builds the app and verifies its ZIP. A
first-time contributor's workflow may wait for maintainer approval before it
runs. PR jobs use read-only repository access and have no Codex login. Workflow
changes receive review before the maintainer approves their execution.

## Review, merge and release

The maintainer, [@emmepra](https://github.com/emmepra), reviews scope, behavior and
verification, and may request changes on the same PR. `CODEOWNERS` routes review
requests to the maintainer. Keep discussion concrete and respectful.

`main` requires a pull request, an up-to-date branch, the successful **build**
check from GitHub Actions, and resolved review conversations. These rules also
apply to administrators; direct and force pushes are blocked. There is currently
one maintainer, so GitHub does not require an additional approving reviewer for
the maintainer's own PRs. External contributors cannot merge their own PRs;
the maintainer reviews and merges them after the checks pass.

After merge, the maintainer prepares a version and release notes in a separate
PR when needed, then follows the [release guide](docs/RELEASING.md). A merged PR
does not automatically create a downloadable release. Releases preserve the
source commit and MIT license in their downloadable package.
