#!/bin/bash
# Stops Aurora HUD and removes the login item. Leaves the built app in place.
PLIST="$HOME/Library/LaunchAgents/com.bernardo.aurora-hud.plist"
launchctl bootout "gui/$(id -u)/com.bernardo.aurora-hud" 2>/dev/null || true
rm -f "$PLIST"
pkill -x AuroraHUD 2>/dev/null || true
echo "Aurora HUD stopped and removed from login items."
