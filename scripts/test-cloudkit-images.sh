#!/bin/bash
set -euo pipefail
savy_image_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_image_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-image-checks.XXXXXX")"
trap 'rm -rf "$savy_image_build"' EXIT
cd "$savy_image_root"

# Use the production portable values and JSON codec with real Apple asset types.
# These checks create CKRecord/CKAsset values only; no container or engine is opened.
awk '/^\/\/ MARK: - Transport/ { exit } { print }' SAVY/SavyDocumentSync.swift > "$savy_image_build/SyncValues.swift"
awk '/^\/\/\/ Both complete originals/ { exit } { print }' SAVY/SavyCloudSyncState.swift > "$savy_image_build/CloudRecords.swift"
printf 'import Foundation\n' > "$savy_image_build/JSONCoding.swift"
awk '/^extension JSONEncoder/ { copying = 1 } copying { print }' SAVY/ReminderModels.swift >> "$savy_image_build/JSONCoding.swift"
swiftc -swift-version 6 -parse-as-library \
  "$savy_image_build/SyncValues.swift" "$savy_image_build/CloudRecords.swift" \
  "$savy_image_build/JSONCoding.swift" SAVY/SavyImageCache.swift SAVY/SavyCloudKitAssets.swift \
  scripts/cloudkit-tests/ImageCacheChecks.swift -o "$savy_image_build/image-checks"
"$savy_image_build/image-checks"
