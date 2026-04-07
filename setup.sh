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
echo ""
echo "Available commands:"
ls "$COMMANDS_DIR"/*.md 2>/dev/null | while read f; do
    echo "  /$(basename "$f" .md)"
done
echo ""
echo "Restart any running Claude Code sessions to pick up the commands."
