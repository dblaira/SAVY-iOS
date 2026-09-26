#!/bin/bash
set -euo pipefail
savy_sync_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_sync_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-connection-sync-checks.XXXXXX")"
trap 'rm -rf "$savy_sync_build"' EXIT
cd "$savy_sync_root"
# Compile the production document engine and Connection adapter. Other adapters and the
# live gateway transport are deliberately not linked; every store below is isolated.
awk '/^\/\/ MARK: - Transport/ { exit } { print }' SAVY/SavyDocumentSync.swift > "$savy_sync_build/SyncValues.swift"
awk '/^\/\/\/ The older News\/Advertising posts/ { exit } { print }' SAVY/SavySyncAdapters.swift > "$savy_sync_build/ConnectionsSyncAdapter.swift"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/ConnectionStore.swift \
  "$savy_sync_build/SyncValues.swift" "$savy_sync_build/ConnectionsSyncAdapter.swift" \
  scripts/schedule-tests/ConnectionSyncChecks.swift \
  -o "$savy_sync_build/connection-sync-checks"
"$savy_sync_build/connection-sync-checks"
