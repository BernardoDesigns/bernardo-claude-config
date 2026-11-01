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

# --- Retire the old status line (replaced by Aurora Usage) ---
# Earlier versions linked ~/.claude/statusline.sh to this repo. Remove that
# link, but leave alone any status line script that isn't ours.
STATUSLINE_LINK="$CLAUDE_DIR/statusline.sh"
if [ -L "$STATUSLINE_LINK" ] && [[ "$(readlink "$STATUSLINE_LINK")" == "$REPO_DIR/"* ]]; then
    rm "$STATUSLINE_LINK"
    echo "Removed old status line link $STATUSLINE_LINK"
fi

# Dependencies: warn loudly instead of failing silently
if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found. The settings merge below needs it:"
    echo "    brew install jq"
fi

# --- Aurora billboard: load the mod from this repo in every session ---
# Adds this repo's mod folder to env.CLAUDE_CODE_PLUGIN_DIRS (appended, ':'
# separated, if other folders are already listed) and drops the old statusLine
# entry only if it still points at our retired script. Every other key stays.
SETTINGS="$CLAUDE_DIR/settings.json"
BILLBOARD_DIR="$REPO_DIR/aurora-usage/aurora-billboard"
OLD_STATUSLINE='{"type":"command","command":"~/.claude/statusline.sh"}'
if command -v jq >/dev/null 2>&1; then
    [ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    if MERGED=$(jq --arg dir "$BILLBOARD_DIR" --argjson old "$OLD_STATUSLINE" '
            (.env.CLAUDE_CODE_PLUGIN_DIRS // "") as $cur
            | .env = ((.env // {}) + {CLAUDE_CODE_PLUGIN_DIRS:
                (if $cur == "" then $dir
                 elif ($cur | split(":") | index($dir)) then $cur
                 else $cur + ":" + $dir end)})
            | if .statusLine == $old then del(.statusLine) else . end
        ' "$SETTINGS"); then
        if [ "$MERGED" = "$(jq . "$SETTINGS")" ]; then
            echo "Aurora billboard already wired in $SETTINGS, leaving it"
        else
            BACKUP="$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
            cp "$SETTINGS" "$BACKUP"
            # Write in place (not mv) so a symlinked settings.json stays a symlink
            printf '%s\n' "$MERGED" > "$SETTINGS"
            echo "Wired Aurora billboard into $SETTINGS (backup: $BACKUP)"
        fi
    else
        echo "ERROR: $SETTINGS is not valid JSON, left it alone. Fix it and re-run."
    fi
else
    echo "Skipped Aurora billboard in $SETTINGS (needs jq)"
fi

# --- Aurora HUD: build the floating usage panel and start it at login ---
# On by default. Skip with: bash setup.sh --no-hud   Undo with: aurora-usage/aurora-hud/remove.sh
# Set to 0 to take it out of setup entirely.
HUD_ENABLED=1
HUD_DIR="$REPO_DIR/aurora-usage/aurora-hud"
if [ "$HUD_ENABLED" != 1 ]; then
    echo "Skipped Aurora HUD (in progress, see aurora-usage/README.md)"
elif [ "${1:-}" = "--no-hud" ]; then
    echo "Skipped Aurora HUD (--no-hud)"
elif [ "$(uname)" != "Darwin" ]; then
    echo "Skipped Aurora HUD (macOS only)"
elif ! command -v swiftc >/dev/null 2>&1; then
    echo "WARNING: swiftc not found, so the Aurora HUD wasn't built. Run this once, then re-run setup.sh:"
    echo "    xcode-select --install"
elif "$HUD_DIR/build.sh" && "$HUD_DIR/start-at-login.sh"; then
    echo "Done! Aurora HUD is running and starts at login"
else
    echo "WARNING: Aurora HUD build or launch failed. Everything else is set up."
fi

echo ""
echo "Available commands:"
ls "$COMMANDS_DIR"/*.md 2>/dev/null | while read f; do
    echo "  /$(basename "$f" .md)"
done
echo ""
echo "Restart any running Claude Code sessions (and the desktop app) to pick up the commands and the billboard."
