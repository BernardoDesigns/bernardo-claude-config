# Aurora Usage

Two gauges wired to one fuel tank: a thin-line usage billboard inside Claude Code, and a floating HUD that sits over the Claude desktop app so you can see your limits while you brainstorm in Chat and Projects.

```
5h ━━━━━━━━━━━━ 31% ⏰1h38m │ 7d ━━━━━━━━━━━━ 64% ⏰2d15h │ Opus 5.5 ━━━━━━━━━━━━ 42% 420.0k/1.0M │ $1.42
```

Each bar cell is colored by its *position*, so a fuller bar literally reaches further into the hot end of the spectrum.

## What's inside

| Folder | What it is | Runs in |
| --- | --- | --- |
| `aurora-billboard/` | Claude Code mod: the band above your prompt, plus `/billboard` theme picker and threshold toasts | Terminal + desktop app's Code tab |
| `aurora-hud/` | Native macOS floating panel (one Swift file) | Anywhere on your desktop, all Spaces |

## Install

It ships as part of [bernardo-claude-config](../README.md), so the repo's `setup.sh` installs both pieces:

```bash
bash setup.sh            # wires the mod into ~/.claude/settings.json, builds the HUD, starts it at login
bash setup.sh --no-hud   # same, without the HUD
```

Restart Claude Code and the desktop app afterwards. If setup says swiftc is missing, run `xcode-select --install` once and re-run it.

To try the mod for one session without installing anything:

```bash
claude --plugin-dir ~/LocalDev/bernardo-claude-config/aurora-usage/aurora-billboard
```

## Using it

**Billboard (in Claude Code)**

| Command | Does |
| --- | --- |
| `/billboard` | Lists themes, shows the current one |
| `/billboard theme aurora` | Green to amber to coral (default) |
| `/billboard theme ember` | Sand to Claude orange to brick |
| `/billboard theme tide` | Teal to blue to violet |
| `/billboard theme mono` | Quiet grays, white when hot |
| `/billboard bars block` | Chunky ■ cells instead of thin ━ |

You'll get a toast when either limit crosses 80% and again at 95%, once per window.

When either window passes 100% the band adds `⚡ using credits`. A window whose reset time has passed drops back to 0% right away instead of waiting for the next response.

The band adapts to width: bars shrink on narrow windows, token counts drop off under 110 columns, and the context and cost segments drop off under 70.

**HUD (on your desktop)**

- **Follows the Claude desktop app:** it appears when the app opens and hides when it quits. It starts at login and waits in the background in between
- **Refresh button** (bottom right) pulls a fresh reading. The footer says how old the current one is and turns amber after 15 minutes
- **Minimize / maximize button** collapses it into a small pill and back. A click anywhere else on the panel does the same
- **Drag** to park it anywhere; it remembers the spot
- **Right-click** for Refresh now (⌘R), Theme, Block bars, and Quit
- The border glows in the theme's hot color once either limit passes 90%
- Theme and bar style are shared with the billboard, so switching either one switches both

## Good to know

- **One source for both.** The billboard writes every reading to `~/.claude/aurora-usage.json` and the HUD reads it, so the two always agree.
- **Chat counts, but only shows up on the next reading.** The 5h and 7d limits are account-wide, so they include everything you do in Chat and Projects. A new reading arrives whenever any Claude Code session gets a response (terminal or Code tab). During a Chat-only stretch, click refresh.
- **Refresh costs one small request.** It runs `claude -p` once on Haiku with no tools and no MCP servers, and saves no session. That's one request toward your plan, so it only happens when you click, never on a timer.
- **No context bar in the HUD.** Chat conversations don't expose their length to anything outside the app, so the HUD sticks to the plan limits it can read honestly.

## What each piece touches (the security bit)

| | Network | Login token | Files | Auto-update |
| --- | --- | --- | --- | --- |
| Billboard mod | None | None | Writes one file: `~/.claude/aurora-usage.json` | None |
| HUD | None of its own (Refresh launches the `claude` CLI, which makes one request) | None | Reads and writes that same file | None |

The mod only uses Claude Code's own `$.session.usage()` and its file API. The shared file holds percentages, reset times, a timestamp, and the theme: nothing personal, no tokens. The HUD is plain AppKit and Foundation, no third-party code. Every line is yours to read.

## Uninstall

- **Mod:** remove this folder's `aurora-billboard` path from `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`
- **HUD:** `aurora-hud/remove.sh` (stops it and removes the login item), then delete `~/Applications/AuroraHUD` if you want it fully gone
- **Shared file:** delete `~/.claude/aurora-usage.json`
