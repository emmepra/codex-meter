#!/bin/bash
# Complete a CI-created draft using the signing key retained on the maintainer Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]]
[[ "$(git rev-parse HEAD)" == "$(git rev-parse "$TAG^{commit}")" ]]
[[ "$(gh release view "$TAG" --json isDraft --jq .isDraft)" == true ]]
./scripts/fetch-sparkle.sh
STAGING=$(mktemp -d "$PWD/.build/publish-$VERSION.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
gh release download "$TAG" --pattern '*.zip' --pattern SHA256SUMS.txt --dir "$STAGING"
(cd "$STAGING" && shasum -a 256 -c SHA256SUMS.txt)
ARCHIVE="$STAGING/Codex-Meter-$VERSION-macos-arm64.zip"
ditto -x -k "$ARCHIVE" "$STAGING/unpacked"
APP="$STAGING/unpacked/Codex Meter.app"
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")" == "$(cat Resources/Sparkle-public-key.txt)" ]]
grep -Fx "Commit: $(git rev-parse HEAD)" "$STAGING/unpacked/BUILD-INFO.txt" >/dev/null
python3 scripts/create-appcast.py "$VERSION" "$ARCHIVE" "$STAGING/appcast.xml"
gh release upload "$TAG" "$STAGING/appcast.xml" --clobber
# Only signed, complete releases become visible to users.
gh release edit "$TAG" --draft=false --latest
gh release view "$TAG" --json url --jq .url
