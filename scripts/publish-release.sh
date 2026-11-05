#!/bin/bash
# Complete a CI-created draft using the signing key retained on the maintainer Mac.
set -euo pipefail
usage() {
  printf '%s\n' 'Usage: ./scripts/publish-release.sh [--prepare-only]' \
    'Verify and sign the tagged draft release, upload its appcast, then publish.' \
    '--prepare-only signs and uploads the appcast while leaving the release as a draft.'
}

PREPARE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare-only) PREPARE_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_DIR"
VERSION=$(cat VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
TAG="v$VERSION"
SOURCE_COMMIT=$(git rev-parse HEAD)

require_clean_tag() {
  [[ -z "$(git status --porcelain)" ]]
  [[ "$(git rev-parse HEAD)" == "$SOURCE_COMMIT" ]]
  [[ "$SOURCE_COMMIT" == "$(git rev-parse "$TAG^{commit}")" ]]
}

require_draft() {
  local is_draft
  is_draft=$(gh release view "$TAG" --json isDraft --jq .isDraft)
  if [[ "$is_draft" != true ]]; then
    printf '%s\n' 'This version is already published. Use a new version.' >&2
    exit 1
  fi
}

require_clean_tag
require_draft
./scripts/fetch-sparkle.sh
# Extraction on FileProvider-managed source folders can invalidate signed apps.
STAGING=$(mktemp -d "/private/tmp/codex-meter-publish-$VERSION.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
gh release download "$TAG" --pattern '*.zip' --pattern SHA256SUMS.txt --dir "$STAGING"
(cd "$STAGING" && shasum -a 256 -c SHA256SUMS.txt)
ARCHIVE="$STAGING/Codex-Meter-$VERSION-macos-arm64.zip"
ditto -x -k "$ARCHIVE" "$STAGING/unpacked"
APP="$STAGING/unpacked/Codex Meter.app"
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")" == "$(cat Resources/Sparkle-public-key.txt)" ]]
grep -Fx "Commit: $SOURCE_COMMIT" "$STAGING/unpacked/BUILD-INFO.txt" >/dev/null
grep -Fx 'Working tree: clean' "$STAGING/unpacked/BUILD-INFO.txt" >/dev/null
python3 scripts/create-appcast.py "$VERSION" "$ARCHIVE" "$STAGING/appcast.xml"
# Recheck publication boundaries after the potentially interactive signing step.
require_clean_tag
require_draft
gh release upload "$TAG" "$STAGING/appcast.xml" --clobber
if [[ "$PREPARE_ONLY" == true ]]; then
  printf '%s\n' 'Signed appcast uploaded. The release remains a draft.'
else
  # Only signed, complete releases become visible to users.
  require_draft
  gh release edit "$TAG" --draft=false --latest
fi
gh release view "$TAG" --json url --jq .url
