#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$PROJECT_DIR"
VERSION=$(cat VERSION)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'VERSION must contain a version such as 0.3.1.' >&2
  exit 1
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "v$VERSION" ) ]]; then
  printf 'Expected release tag: v%s\n' "$VERSION" >&2
  exit 1
fi
NOTES="docs/releases/$VERSION.md"
[[ -s "$NOTES" ]] || { printf 'Missing release notes: %s\n' "$NOTES" >&2; exit 1; }
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  printf '%s\n' 'Release packaging requires an Apple Silicon Mac.' >&2
  exit 1
fi

./scripts/build.sh
BUILD_DIR="${METER_BUILD_DIR:-$PROJECT_DIR/.build}"
APP_DIR="$BUILD_DIR/Codex Meter.app"
BINARY="$APP_DIR/Contents/MacOS/CodexMeter"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP_DIR/Contents/Info.plist")" == AppIcon ]]
[[ -s "$APP_DIR/Contents/Resources/AppIcon.icns" && -s "$APP_DIR/Contents/Resources/MeterMark.png" ]]
[[ "$(lipo -archs "$BINARY")" == arm64 ]]
codesign --verify --deep --strict "$APP_DIR"

# Keep signed bundles outside synchronized checkouts, where Finder/FileProvider
# can reattach extended attributes after signing or extraction.
STAGING_DIR=$(mktemp -d /private/tmp/codex-meter-release.XXXXXX)
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/archive" "$STAGING_DIR/unpacked" .build/release
# Fresh staging contains only the app and public installation/provenance files.
ditto --norsrc --noextattr "$APP_DIR" "$STAGING_DIR/archive/Codex Meter.app"
cp LICENSE "$STAGING_DIR/archive/LICENSE"
DOC_SOURCE="https://github.com/emmepra/codex-meter/blob/$(git rev-parse HEAD)"
sed "s|](../docs/BRAND.md|]($DOC_SOURCE/docs/BRAND.md|g" \
  Resources/README.md > "$STAGING_DIR/archive/ASSET-NOTICES.md"
sed -e "s|](../README.md|]($DOC_SOURCE/README.md|g" \
  -e "s|](USAGE.md|]($DOC_SOURCE/docs/USAGE.md|g" \
  docs/INSTALL.md > "$STAGING_DIR/archive/INSTALL.md"
{
  printf 'Codex Meter %s\nSource: https://github.com/emmepra/codex-meter\n' "$VERSION"
  printf 'Commit: %s\n' "$(git rev-parse HEAD)"
  printf 'Target: Apple Silicon, macOS 13+\nSigning: ad hoc; not notarized\nCompiler: '
  xcrun swiftc --version 2>&1
  if [[ -z "$(git status --porcelain)" ]]; then
    printf 'Working tree: clean\n'
  else
    printf 'Working tree: modified (local preview build)\n'
  fi
} > "$STAGING_DIR/archive/BUILD-INFO.txt"
codesign --verify --deep --strict "$STAGING_DIR/archive/Codex Meter.app"
ARCHIVE="Codex-Meter-$VERSION-macos-arm64.zip"
ditto -c -k --norsrc --noextattr "$STAGING_DIR/archive" "$STAGING_DIR/$ARCHIVE"
# Verify the distributed bytes survive an extraction with executable permissions.
ditto -x -k "$STAGING_DIR/$ARCHIVE" "$STAGING_DIR/unpacked"
codesign --verify --deep --strict "$STAGING_DIR/unpacked/Codex Meter.app"
[[ -x "$STAGING_DIR/unpacked/Codex Meter.app/Contents/MacOS/CodexMeter" ]]
mv -f "$STAGING_DIR/$ARCHIVE" ".build/release/$ARCHIVE"
cp "$NOTES" .build/release/release-notes.md
(cd .build/release && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
printf 'Release package: .build/release/%s\n' "$ARCHIVE"
