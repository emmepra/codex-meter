#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Tests/UsageSnapshotTests.swift -o .build/usage-tests
.build/usage-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/CLIProcess.swift Sources/CodexClient.swift Tests/CodexClientTests.swift -o .build/client-tests
.build/client-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/ComputeBudget.swift Tests/ComputeBudgetTests.swift -o .build/budget-tests
.build/budget-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/PanelPlacement.swift Tests/PanelPlacementTests.swift -o .build/placement-tests
.build/placement-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Tests/ReleaseInfoTests.swift -o .build/release-info-tests
.build/release-info-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Sources/ReleaseChecker.swift Sources/SparkleInstaller.swift Tests/ReleaseCheckerTests.swift -o .build/release-checker-tests
.build/release-checker-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Sources/ResetAnnouncements.swift Tests/ResetFeedTests.swift -o .build/reset-feed-tests
.build/reset-feed-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/ReleaseInfo.swift Sources/ResetAnnouncements.swift Tests/ResetReadStateTests.swift -o .build/reset-read-tests
.build/reset-read-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/CreditPace.swift Tests/CreditPaceTests.swift -o .build/credit-pace-tests
.build/credit-pace-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/ProviderSelection.swift Tests/ProviderSelectionTests.swift -o .build/provider-selection-tests
.build/provider-selection-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/ClaudeUsage.swift Sources/ClaudeBridge.swift Tests/ClaudeUsageTests.swift -o .build/claude-usage-tests
.build/claude-usage-tests

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/ClaudeUsage.swift Sources/ClaudeBridge.swift Sources/ClaudeDesktopBridge.swift \
  Tests/ClaudeDesktopInstallerTests.swift -o .build/claude-desktop-installer-tests
.build/claude-desktop-installer-tests

node Tests/ClaudeDesktopBridgeTests.js

xcrun swiftc -swift-version 5 -parse-as-library -D METER_TESTS -module-cache-path .build/module-cache \
  Sources/UsageSnapshot.swift Sources/ClaudeUsage.swift Sources/ClaudeBridge.swift Sources/ClaudeDesktopBridge.swift \
  Sources/CLIProcess.swift Sources/ClaudeQuotaClient.swift Tests/ClaudeQuotaClientTests.swift -o .build/claude-quota-client-tests
.build/claude-quota-client-tests
