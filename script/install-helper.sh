#!/usr/bin/env bash
# Installs the Send to AI helper as a login item on this Mac, so the phone and the Mac app can
# ask Claude and ChatGPT through the logins already here. Safe to run again; it replaces itself.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$HOME/Library/Application Support/SAVY/send-to-ai-helper.py"
plist="$HOME/Library/LaunchAgents/com.adamblair.savy.send-to-ai-helper.plist"
mkdir -p "$(dirname "$dest")" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/SAVY"
cp "$root/script/send-to-ai-helper.py" "$dest"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.adamblair.savy.send-to-ai-helper</string>
  <key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>$dest</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string><key>HOME</key><string>$HOME</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/SAVY/send-to-ai-helper.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/SAVY/send-to-ai-helper.log</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/com.adamblair.savy.send-to-ai-helper" >/dev/null 2>&1 || true
pkill -f "send-to-ai-helper.py" >/dev/null 2>&1 || true
sleep 1
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "helper installed and running from $dest"
