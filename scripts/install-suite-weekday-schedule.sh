#!/usr/bin/env bash
set -euo pipefail

LABEL="com.dblaira.savy.suite-weekday-status"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$REPO_ROOT/scripts/com.dblaira.savy.suite-weekday-status.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"

UID_NUM="$(id -u)"
launchctl bootout "gui/$UID_NUM" "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST_DST"
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "Installed $LABEL"
echo "Runs weekdays at 9:00 AM local time"
echo "Log: $HOME/Library/Logs/savy-suite-weekday-status.log"
