#!/bin/bash
set -euo pipefail
usage() {
  printf '%s\n' 'Usage: ./scripts/test-ui.sh [--render-only]' \
    'Run synthetic panel state checks and save screenshots in .build/.' \
    'By default, also run native window geometry and status-item appearance checks.' \
    '--render-only skips those interactive desktop integration checks.'
}

RENDER_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --render-only) RENDER_ONLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/module-cache
if [[ "$RENDER_ONLY" == false ]]; then
  # Requires a logged-in macOS desktop; briefly shows synthetic test UI.
  xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx13.0 \
    -module-cache-path .build/module-cache \
    Sources/PanelPlacement.swift Sources/StatusPanel.swift Tests/StatusPanelTests.swift \
    -o .build/status-panel-tests
  .build/status-panel-tests
fi

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -target arm64-apple-macosx13.0 \
  -module-cache-path .build/module-cache \
  Sources/*.swift Tests/MeterPanelTests.swift -o .build/meter-panel-tests
.build/meter-panel-tests

if [[ "$RENDER_ONLY" == false ]]; then
  ./scripts/test-status-appearance.sh
fi
