#!/bin/bash
# Setup script for Claude Code agent commands
# Run this after cloning the repo on a new machine

CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# If commands directory already exists, back it up
if [ -d "$COMMANDS_DIR" ] && [ ! -L "$COMMANDS_DIR" ]; then
    echo "Backing up existing commands to $COMMANDS_DIR.bak"
    mv "$COMMANDS_DIR" "$COMMANDS_DIR.bak"
fi

# Remove existing symlink if present
if [ -L "$COMMANDS_DIR" ]; then
    rm "$COMMANDS_DIR"
fi

# Create symlink
ln -s "$REPO_DIR/commands" "$COMMANDS_DIR"

echo "Done! ~/.claude/commands now points to $REPO_DIR/commands"
echo ""
echo "Available commands:"
ls "$COMMANDS_DIR"/*.md 2>/dev/null | while read f; do
    echo "  /$(basename "$f" .md)"
done
