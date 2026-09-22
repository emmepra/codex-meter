#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/Codex Meter.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR/module-cache"
xcrun swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path "$BUILD_DIR/module-cache" \
  Sources/UsageSnapshot.swift Sources/ComputeBudget.swift Sources/CodexClient.swift Sources/App.swift \
  -o "$APP_DIR/Contents/MacOS/CodexMeter"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CodexMeter</string>
  <key>CFBundleIdentifier</key><string>it.emmepra.codex-meter</string>
  <key>CFBundleName</key><string>Codex Meter</string>
  <key>CFBundleDisplayName</key><string>Codex Meter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR"
printf '%s\n' "$APP_DIR"
