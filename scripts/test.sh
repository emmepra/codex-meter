#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Tests/UsageSnapshotTests.swift -o .build/usage-tests
.build/usage-tests

xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/CodexClient.swift Tests/CodexClientTests.swift -o .build/client-tests
.build/client-tests

xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/ComputeBudget.swift Tests/ComputeBudgetTests.swift -o .build/budget-tests
.build/budget-tests

xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/PanelPlacement.swift Tests/PanelPlacementTests.swift -o .build/placement-tests
.build/placement-tests

xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Tests/ReleaseInfoTests.swift -o .build/release-info-tests
.build/release-info-tests

xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Sources/ReleaseChecker.swift Tests/ReleaseCheckerTests.swift -o .build/release-checker-tests
.build/release-checker-tests
