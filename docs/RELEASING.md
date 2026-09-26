# Releasing Codex Meter

A release is a reviewed commit on `main` plus a tag matching `VERSION`. Pushing
that tag runs the same build checks as a pull request, then stages a draft. The maintainer signs the update locally before publication.
The Ed25519 private key stays in the maintainer Mac login Keychain, account `it.emmepra.codex-meter`. It is never committed or uploaded to Actions.

## Prepare and publish

1. Set `VERSION` to the next `major.minor.patch` number and write
   `docs/releases/<version>.md` with concise changes and installation caveats.
   `scripts/build.sh` uses `VERSION` for both bundle version fields.
2. Run `./scripts/test.sh` and `./scripts/package-release.sh`. For UI changes,
   also run `./scripts/test-ui.sh` in a logged-in macOS desktop and check the app.
   Packaging does not launch the app or make a live quota read.
3. Submit the version and notes through a pull request, following
   [Contributing](../CONTRIBUTING.md). After review and the required **build** check
   pass, merge the PR. `main` is protected, including for administrators.
   Wait for **Build and release** on the resulting `main` commit to pass.
4. From that clean, up-to-date commit, create and push the matching tag:

   ```sh
   git switch main
   git pull --ff-only
   version=$(cat VERSION)
   git tag -a "v$version" -m "Codex Meter $version"
   git push origin "v$version"
   ```

5. After the tag's **Build and release** run succeeds, run `./scripts/publish-release.sh` from the clean tagged commit on the maintainer Mac. Authorize the Sparkle signing tool in Keychain when prompted. The script downloads and verifies the draft ZIP, checks bundle version, source commit and embedded public key, signs the archive and appcast, verifies both signatures, uploads `appcast.xml`, and publishes the release. Then open the
   [release](https://github.com/emmepra/codex-meter/releases). Confirm the version,
   installation notes, ZIP and checksum, and download the ZIP once to verify it.

Pushing a tag creates an unpublished draft; local signing and `publish-release.sh` are the publication step. Pushes to `main` and pull requests
run tests and retain build artifacts for 14 days; they do not create a release.

## What the workflow does

The build job runs on GitHub's `macos-15` Apple Silicon runner with read-only
repository permission. It checks the tag against `VERSION`, runs offline tests,
builds the app, checks its architecture and signature, creates a ZIP, extracts
it, and verifies the extracted signature and executable permissions.

A separate publish job has `contents: write` through the temporary `GITHUB_TOKEN`.
It downloads that run's artifacts, checks SHA-256, creates a draft release with
its assets, and leaves it as a draft until the local signing step succeeds. No Codex login, usage data, Sparkle private key, Apple signing credentials or personal access token is supplied to either job.
The interactive UI test stays local because it requires a real desktop session.

The ZIP includes `Codex Meter.app`, the MIT license, installation instructions
and `BUILD-INFO.txt` with the source commit and compiler version. `SHA256SUMS.txt`
is a separate release asset. To check a downloaded ZIP in the same directory:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Builds target Apple Silicon and macOS 13+. They use ad hoc signing, without an
Apple Developer ID signature or notarization; see [installation](INSTALL.md).
Notarization would require a separate Apple Developer signing setup.

## Failed runs and corrections

Fix failing tests or packaging on `main` before creating a release tag. For an
infrastructure or upload failure with unchanged source, rerun the failed tag
workflow from Actions. A rerun can finish an unpublished draft; it refuses to
overwrite a published release. If source changes are needed after tagging,
choose a new version and tag. Do not move a published tag or replace its ZIP.

## Signed in-app updates (0.5.3+)

`scripts/fetch-sparkle.sh` fetches Sparkle 2.10.0 with a pinned SHA-256 and verifies its code signature. The framework and license are embedded during build. The application requires signed feeds and validation before archive extraction; the feed URL is the latest release's `appcast.xml` asset.

The existing project signing key is stored in login Keychain. Do not generate a replacement during routine releases or put a private key in the repository. Keep a secure backup of the Keychain/signing key: these ad hoc signed apps cannot use Developer ID key rotation to recover a lost Ed25519 key. Only the public key is in `Resources/Sparkle-public-key.txt`. `create-appcast.py` refuses to sign with a different public key.

Old versions cannot acquire updater functionality without a one-time manual installation. Updating from 0.5.3 onward uses the Sparkle window. Background availability checks remain quiet and installation is never unattended.
