#!/bin/bash
# Setup script for Claude Code agent commands
# Run this after cloning the repo on a new machine

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# If commands directory already exists as a real dir, back it up (timestamped)
if [ -d "$COMMANDS_DIR" ] && [ ! -L "$COMMANDS_DIR" ]; then
    BACKUP="$COMMANDS_DIR.bak.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing commands directory to $BACKUP"
    mv "$COMMANDS_DIR" "$BACKUP"
fi

# Remove existing symlink (live or broken) if present
if [ -L "$COMMANDS_DIR" ]; then
    if [ ! -e "$COMMANDS_DIR" ]; then
        echo "Found broken symlink at $COMMANDS_DIR (target missing) — removing"
    fi
    rm "$COMMANDS_DIR"
fi

# Create symlink
ln -s "$REPO_DIR/commands" "$COMMANDS_DIR"

# Verify
if [ ! -e "$COMMANDS_DIR" ]; then
    echo "ERROR: symlink created but target $REPO_DIR/commands does not exist"
    exit 1
fi

echo "Done! ~/.claude/commands -> $REPO_DIR/commands"

# --- dev-aliases.sh: symlink into home + wire .zshrc ---
ALIASES_LINK="$HOME/.dev-aliases.sh"

# Back up a real file in the way (timestamped), then clear any stale symlink
if [ -f "$ALIASES_LINK" ] && [ ! -L "$ALIASES_LINK" ]; then
    BACKUP="$ALIASES_LINK.bak.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing dev-aliases.sh to $BACKUP"
    mv "$ALIASES_LINK" "$BACKUP"
fi
[ -L "$ALIASES_LINK" ] && rm "$ALIASES_LINK"

# Symlink home -> repo copy
ln -s "$REPO_DIR/dev-aliases.sh" "$ALIASES_LINK"

# Verify the link resolves
if [ ! -e "$ALIASES_LINK" ]; then
    echo "ERROR: dev-aliases symlink created but target $REPO_DIR/dev-aliases.sh does not exist"
    exit 1
fi
echo "Done! ~/.dev-aliases.sh -> $REPO_DIR/dev-aliases.sh"

# Wire the source line into .zshrc (only if missing)
ZSHRC="$HOME/.zshrc"
if grep -qF '.dev-aliases.sh' "$ZSHRC" 2>/dev/null; then
    echo "Source line already in $ZSHRC, leaving it"
else
    echo '[ -f ~/.dev-aliases.sh ] && source ~/.dev-aliases.sh' >> "$ZSHRC"
    echo "Added source line to $ZSHRC"
fi

# --- statusline.sh: symlink into ~/.claude + wire settings.json ---
STATUSLINE_LINK="$CLAUDE_DIR/statusline.sh"

# Back up a real file in the way (timestamped), then clear any stale symlink
if [ -f "$STATUSLINE_LINK" ] && [ ! -L "$STATUSLINE_LINK" ]; then
    BACKUP="$STATUSLINE_LINK.bak.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing statusline.sh to $BACKUP"
    mv "$STATUSLINE_LINK" "$BACKUP"
fi
[ -L "$STATUSLINE_LINK" ] && rm "$STATUSLINE_LINK"

# Symlink ~/.claude -> repo copy
ln -s "$REPO_DIR/statusline.sh" "$STATUSLINE_LINK"

if [ ! -e "$STATUSLINE_LINK" ]; then
    echo "ERROR: statusline symlink created but target $REPO_DIR/statusline.sh does not exist"
    exit 1
fi
echo "Done! ~/.claude/statusline.sh -> $REPO_DIR/statusline.sh"

# Dependencies: warn loudly instead of failing silently
if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found. The status line and the settings merge below need it:"
    echo "    brew install jq"
fi

# Merge statusLine into settings.json, leaving every other key untouched
SETTINGS="$CLAUDE_DIR/settings.json"
if command -v jq >/dev/null 2>&1; then
    [ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    WANT='{"type":"command","command":"~/.claude/statusline.sh"}'
    if jq -e --argjson want "$WANT" '.statusLine == $want' "$SETTINGS" >/dev/null 2>&1; then
        echo "statusLine already set in $SETTINGS, leaving it"
    elif MERGED=$(jq --argjson want "$WANT" '.statusLine = $want' "$SETTINGS"); then
        # Write in place (not mv) so a symlinked settings.json stays a symlink
        printf '%s\n' "$MERGED" > "$SETTINGS"
        echo "Set statusLine in $SETTINGS"
    else
        echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
    fi
else
    echo "Skipped statusLine in $SETTINGS (needs jq)"
fi

echo ""
echo "Available commands:"
ls "$COMMANDS_DIR"/*.md 2>/dev/null | while read f; do
    echo "  /$(basename "$f" .md)"
done
echo ""
echo "Restart any running Claude Code sessions to pick up the commands."
