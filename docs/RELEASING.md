# Releasing Codex Meter

A release is a reviewed commit on `main` plus a tag matching `VERSION`. Pushing
that tag runs the same build checks as a pull request, then publishes the app.
No manual upload or personal token is needed in Actions.

## Prepare and publish

1. Set `VERSION` to the next `major.minor.patch` number and write
   `docs/releases/<version>.md` with concise changes and installation caveats.
   `scripts/build.sh` uses `VERSION` for both bundle version fields.
2. Run `./scripts/test.sh` and `./scripts/package-release.sh`. For UI changes,
   also run `./scripts/test-ui.sh` in a logged-in macOS desktop and check the app.
   Packaging does not launch the app or make a live quota read.
3. Commit the changes, push `main`, and wait for **Build and release** to pass.
4. From that clean, up-to-date commit, create and push the matching tag:

   ```sh
   version=$(cat VERSION)
   git tag -a "v$version" -m "Codex Meter $version"
   git push origin "v$version"
   ```

5. Check the tag's **Build and release** run, then open the
   [release](https://github.com/emmepra/codex-meter/releases). Confirm the version,
   installation notes, ZIP and checksum, and download the ZIP once to verify it.

Pushing a tag is the publication step. Ordinary branch pushes and pull requests
run tests and retain build artifacts for 14 days; they do not create a release.

## What the workflow does

The build job runs on GitHub's `macos-15` Apple Silicon runner with read-only
repository permission. It checks the tag against `VERSION`, runs offline tests,
builds the app, checks its architecture and signature, creates a ZIP, extracts
it, and verifies the extracted signature and executable permissions.

A separate publish job has `contents: write` through the temporary `GITHUB_TOKEN`.
It downloads that run's artifacts, checks SHA-256, creates a draft release with
its assets, and publishes only after uploads succeed. No Codex login, usage data,
Apple signing credentials or personal access token is supplied to either job.
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
