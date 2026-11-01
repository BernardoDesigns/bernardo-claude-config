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
bash setup.sh            # wires the mod into ~/.claude/settings.json
```

Restart Claude Code and the desktop app afterwards.

> **HUD status: in progress.** The file it was written to read (`plan-usage-history.json`) doesn't exist in current versions of the desktop app, so the HUD has no data yet. `main.swift` compiles, but `setup.sh` skips it (`HUD_ENABLED=0`) until it has a source that tracks Chat usage too. Once it's back on, `setup.sh` builds it and starts it at login, and `bash setup.sh --no-hud` skips it.

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

- **Click** to collapse into a small pill, click again to expand
- **Drag** to park it anywhere; it remembers the spot
- **Right-click** for Theme, Block bars, and Quit
- The border glows in the theme's hot color once either limit passes 90%

## Good to know

- **The two read different sources.** The billboard gets live numbers straight from Claude Code. The HUD reads a file the Claude desktop app updates about every 5 minutes, so it can trail by a few minutes. Same account limits, slightly different freshness.
- **HUD countdowns appear after the first reset it sees.** It works out reset times by spotting when usage drops. Until that happens you'll see `⏰–`. Give it one window.
- **If the HUD says "unexpected format"**, the desktop app changed its file. Ping Claude with that message and it can adapt the parser.
- **No context bar in the HUD.** Chat conversations don't expose their length to anything outside the app, so the HUD sticks to the plan limits it can read honestly.

## What each piece touches (the security bit)

| | Network | Login token | Files | Auto-update |
| --- | --- | --- | --- | --- |
| Billboard mod | None | None | None | None |
| HUD | None | None | Reads one file: `~/Library/Application Support/Claude/plan-usage-history.json` | None |

The mod only uses Claude Code's own `$.session.usage()` and remembers your theme with its built-in store. The HUD is plain AppKit, no third-party code. Every line is yours to read.

## Uninstall

- **Mod:** remove this folder's `aurora-billboard` path from `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`
- **HUD:** `aurora-hud/remove.sh` (stops it and removes the login item), then delete `~/Applications/AuroraHUD` if you want it fully gone
