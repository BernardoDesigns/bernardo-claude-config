#!/bin/bash
# Builds Aurora HUD from main.swift and puts it in ~/Applications/AuroraHUD.
# Needs Xcode Command Line Tools (run `xcode-select --install` once if swiftc is missing).
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null; then
  echo "swiftc not found. Run: xcode-select --install"
  exit 1
fi

mkdir -p "$HOME/Applications/AuroraHUD"
swiftc -O main.swift -o "$HOME/Applications/AuroraHUD/AuroraHUD"
echo "Built: $HOME/Applications/AuroraHUD/AuroraHUD"
echo "Run it now with:  open -a Terminal \"$HOME/Applications/AuroraHUD/AuroraHUD\"  or  ./start-at-login.sh"
