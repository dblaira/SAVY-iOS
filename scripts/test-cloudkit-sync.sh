#!/bin/bash
set -euo pipefail
savy_cloud_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_cloud_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-cloud-sync-checks.XXXXXX")"
trap 'rm -rf "$savy_cloud_build"' EXIT
cd "$savy_cloud_root"

if [[ "${1:-}" == "--characterize" ]]; then
  # Exercise the original fallible stores without linking cloud, Calendar, or captures.
  printf 'import Combine\n' > "$savy_cloud_build/PostsAndStories.swift"
  cat SAVY/SocialPost.swift SAVY/Story.swift >> "$savy_cloud_build/PostsAndStories.swift"
  swiftc -swift-version 6 -parse-as-library \
    SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/PostNumberAllocator.swift \
    "$savy_cloud_build/PostsAndStories.swift" scripts/cloudkit-tests/PersistenceCharacterization.swift \
    -o "$savy_cloud_build/persistence-checks"
  "$savy_cloud_build/persistence-checks"
  exit
fi

# These boundaries include the real value/merge code and file-backed adapters only.
# External effects below are replaced by test doubles; no cloud transport is linked.
awk '/^\/\/ MARK: - Transport/ { exit } { print }' SAVY/SavyDocumentSync.swift > "$savy_cloud_build/SyncValues.swift"
awk '/^\/\/\/ Card order and pins/ { exit } { print }' SAVY/SavySyncAdapters.swift > "$savy_cloud_build/ContentAdapters.swift"
awk '/^\/\/\/ Cloud-backed reminder repository/ { exit } { print }' SAVY/ReminderRepository.swift > "$savy_cloud_build/ReminderRepository.swift"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/PostNumberAllocator.swift \
  SAVY/ReminderStore.swift SAVY/ConnectionStore.swift SAVY/SocialPost.swift SAVY/Story.swift \
  SAVY/SavyCloudSyncState.swift "$savy_cloud_build/SyncValues.swift" \
  "$savy_cloud_build/ContentAdapters.swift" "$savy_cloud_build/ReminderRepository.swift" \
  scripts/cloudkit-tests/CloudSyncChecks.swift \
  -o "$savy_cloud_build/cloud-sync-checks"
"$savy_cloud_build/cloud-sync-checks"
