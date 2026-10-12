#!/bin/bash
set -euo pipefail
savy_transport_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_transport_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-cloud-transport-checks.XXXXXX")"
trap 'rm -rf "$savy_transport_build"' EXIT
cd "$savy_transport_root"

# Compile the production transport against Apple's real framework. CKRecord, secure coding,
# scopes and record batches are real; these checks never initialize a CKContainer or engine.
awk '/^\/\/ MARK: - Transport/ { exit } { print }' SAVY/SavyDocumentSync.swift > "$savy_transport_build/SyncValues.swift"
awk '/^private func portableReminderValue/ { exit } { print }' SAVY/SavySyncAdapters.swift > "$savy_transport_build/AdapterProtocols.swift"
printf 'import Foundation\n' > "$savy_transport_build/JSONCoding.swift"
awk '/^extension JSONEncoder/ { copying = 1 } copying { print }' SAVY/ReminderModels.swift >> "$savy_transport_build/JSONCoding.swift"
if [[ "${1:-}" == "--typecheck-ios" ]]; then
  savy_transport_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  xcrun swiftc -swift-version 6 -sdk "$savy_transport_sdk" -target arm64-apple-ios18.0 -typecheck \
    "$savy_transport_build/SyncValues.swift" "$savy_transport_build/AdapterProtocols.swift" \
    "$savy_transport_build/JSONCoding.swift" SAVY/SavyCloudSyncState.swift SAVY/CloudKitDocumentSync.swift
  printf 'CloudKit transport iOS 18 typecheck passed against the installed iPhoneOS SDK\n'
  exit
fi
swiftc -swift-version 6 -parse-as-library \
  "$savy_transport_build/SyncValues.swift" "$savy_transport_build/AdapterProtocols.swift" \
  "$savy_transport_build/JSONCoding.swift" SAVY/SavyCloudSyncState.swift \
  SAVY/CloudKitDocumentSync.swift scripts/cloudkit-tests/TransportChecks.swift \
  -o "$savy_transport_build/cloud-transport-checks"
"$savy_transport_build/cloud-transport-checks"
