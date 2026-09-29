#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/module-cache
FLAGS=(-D METER_TESTS)
OUTPUT=.build/status-appearance-tests
if [[ "${1:-}" == --legacy ]]; then
  FLAGS+=(-D LEGACY_APPEARANCE_OBSERVER)
  OUTPUT=.build/status-appearance-tests-legacy
elif [[ $# -gt 0 ]]; then
  printf '%s\n' 'Usage: scripts/test-status-appearance.sh [--legacy]' >&2
  exit 2
fi
# Requires a logged-in macOS desktop and briefly adds a synthetic status item.
# --legacy is a negative control: exit 1 is expected on affected macOS versions.
xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macosx13.0 \
  -module-cache-path .build/module-cache "${FLAGS[@]}" \
  Sources/StatusIndicator.swift Tests/StatusAppearanceTests.swift -o "$OUTPUT"
"$OUTPUT"
