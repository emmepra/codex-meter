#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
./scripts/fetch-sparkle.sh
SPARKLE_DIR="$PROJECT_DIR/.build/sparkle-2.10.0"
VERSION=$(cat "$PROJECT_DIR/VERSION")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf '%s\n' 'VERSION must contain a version such as 0.3.1.' >&2
  exit 1
fi
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/Codex Meter.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/module-cache" \
  Sources/UsageSnapshot.swift Sources/ComputeBudget.swift Sources/CodexClient.swift Sources/PanelPlacement.swift Sources/StatusPanel.swift Sources/StatusIndicator.swift Sources/ReleaseInfo.swift Sources/ReleaseChecker.swift Sources/SparkleInstaller.swift Sources/LoginPreference.swift Sources/ResetAnnouncements.swift Sources/App.swift \
  -F "$SPARKLE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP_DIR/Contents/MacOS/CodexMeter"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE"
xcrun swift -module-cache-path "$BUILD_DIR/module-cache" scripts/make-icon.swift "$BUILD_DIR/AppIcon.iconset"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
sips -s format png -z 128 128 Resources/OpenAI.svg --out "$APP_DIR/Contents/Resources/OpenAI.png" >/dev/null
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CodexMeter</string>
  <key>CFBundleIdentifier</key><string>it.emmepra.codex-meter</string>
  <key>CFBundleName</key><string>Codex Meter</string>
  <key>CFBundleDisplayName</key><string>Codex Meter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string></array>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>SUFeedURL</key><string>https://github.com/emmepra/codex-meter/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$(cat Resources/Sparkle-public-key.txt)</string>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUShowReleaseNotes</key><false/>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
