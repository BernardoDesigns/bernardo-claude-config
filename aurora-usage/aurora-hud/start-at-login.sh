#!/bin/bash
# Starts Aurora HUD now and at every login, using a standard macOS LaunchAgent.
# Undo anytime with ./remove.sh
set -euo pipefail

BIN="$HOME/Applications/AuroraHUD/AuroraHUD"
PLIST="$HOME/Library/LaunchAgents/com.bernardo.aurora-hud.plist"

[ -x "$BIN" ] || { echo "Build first: ./build.sh"; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.bernardo.aurora-hud</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/com.bernardo.aurora-hud" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Aurora HUD is running and will start at login."
