#!/bin/bash
set -euo pipefail
savy_sync_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_sync_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-reminder-sync-checks.XXXXXX")"
trap 'rm -rf "$savy_sync_build"' EXIT
cd "$savy_sync_root"
# Compile the real Gateway wire types and ReminderStore, substituting only external
# delivery/capture dependencies. Every cache and fake server stays inside this process.
printf 'import Foundation\n' > "$savy_sync_build/Checks.swift"
awk '/^private struct GatewayReminderSubtaskRow/ { printing = 1 } /^private struct CaptureRow/ { printing = 0 } printing' \
  SAVY/AWSGraphClient.swift >> "$savy_sync_build/Checks.swift"
cat scripts/schedule-tests/ReminderSyncChecks.swift >> "$savy_sync_build/Checks.swift"
awk '/^\/\/\/ Cloud-backed reminder repository/ { exit } { print }' SAVY/ReminderRepository.swift \
  > "$savy_sync_build/ReminderRepository.swift"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/ReminderStore.swift \
  "$savy_sync_build/ReminderRepository.swift" "$savy_sync_build/Checks.swift" \
  -o "$savy_sync_build/reminder-sync-checks"
"$savy_sync_build/reminder-sync-checks"
