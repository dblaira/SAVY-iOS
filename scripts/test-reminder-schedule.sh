#!/bin/bash
set -euo pipefail
savy_schedule_root="$(cd "$(dirname "$0")/.." && pwd)"
savy_schedule_build="$(mktemp -d "${TMPDIR:-/tmp}/savy-schedule-checks.XXXXXX")"
trap 'rm -rf "$savy_schedule_build"' EXIT
cd "$savy_schedule_root"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift \
  scripts/schedule-tests/PlannerChecks.swift \
  -o "$savy_schedule_build/planner-checks"
"$savy_schedule_build/planner-checks"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/ReminderNotificationScheduler.swift \
  scripts/schedule-tests/DeliveryChecks.swift \
  -o "$savy_schedule_build/delivery-checks"
"$savy_schedule_build/delivery-checks"
swiftc -swift-version 6 -parse-as-library \
  SAVY/PostTheme.swift SAVY/ReminderModels.swift SAVY/ReminderCalendarIntegration.swift \
  scripts/schedule-tests/InvitationChecks.swift \
  -o "$savy_schedule_build/invitation-checks"
"$savy_schedule_build/invitation-checks"
