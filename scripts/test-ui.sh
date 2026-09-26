#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/module-cache
# Requires a logged-in macOS desktop; briefly shows synthetic test UI.
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path .build/module-cache \
  Sources/PanelPlacement.swift Sources/StatusPanel.swift Tests/StatusPanelTests.swift \
  -o .build/status-panel-tests
.build/status-panel-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -target arm64-apple-macosx13.0 \
  -module-cache-path .build/module-cache \
  Sources/*.swift Tests/MeterPanelTests.swift -o .build/meter-panel-tests
.build/meter-panel-tests
