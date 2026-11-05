# bernardo-claude-config

**My Claude Code setup, version-controlled and synced across machines.** It holds a small team of design agents, a one-command dev environment, and Aurora Usage, a pair of plan-usage gauges. Clone it anywhere, run `setup.sh`, and the whole kit is wired in.

Built by [Bernardo Garcia](https://www.bellwetherdesigns.io), a product designer who builds with AI every day.

---

## The design agents

Three slash commands in `commands/` that work as one system: a router, two specialists, and a shared memory that gets sharper with use.

| Command | Role | Thinks in |
|---|---|---|
| `/design-director` | Router | Reads the brief, shows how each specialist would approach it, and lets me pick |
| `/eames` | Product design specialist | Components, states, edge cases, flows, responsive behavior, engineering handoff |
| `/rand` | Brand design specialist | Visual identity, emotional register, brand consistency, persuasion |

Named after Charles Eames and Paul Rand, because each agent takes on a point of view, not just a task list.

### How the system works

```
Design request
   │
   ▼
/design-director ──▶ triage card: "Eames would focus on… / Rand would focus on…"
   │                         │
   │        human picks the lead lens (human-in-the-loop)
   ▼                         ▼
/eames  or  /rand  ──▶  does the work using its own method and principles
   │
   ▼
Session debrief ──▶ proposes learnings ──▶ I approve which ones to keep ──▶ shared memory
```

- **One router, no keyword fights.** Instead of guessing from keywords, the Director presents a triage card and I choose which lens leads. The other lens still informs the work.
- **Each specialist knows its blind spot.** Eames is told to stay brand-aware, and Rand is told to respect interaction states and engineering limits.
- **A learning loop with a human gate.** At the end of a session, the agent lists what it learned (patterns, anti-patterns, preferences, principles, edge cases). I pick which ones are worth keeping, and only those get saved to memory, tagged by agent.
- **Memory that stays lean.** When the decision log reaches about 30 entries, the agents suggest a consolidation pass that rolls them up into evolved principles. That keeps the context loaded at the start of each session small.

---

## Daily rhythm

From inside any project with a `package.json` and a `dev` script:

```bash
cc        # starts the dev server + a Cloudflare tunnel, then launches Claude Code
/exit     # quits Claude Code and tears down the server + tunnel
```

- The public tunnel URL is copied to the clipboard so I can share a live preview right away. My own browser opens `localhost` instead, which skips Chrome's Local Network Access prompt (every tunnel is a new random hostname, so Chrome would otherwise ask on every launch). `DEV_OPEN=tunnel` opens the tunnel URL, `DEV_OPEN=none` opens nothing.
- The tunnel dials whichever loopback address the server actually answers on (`127.0.0.1` or `::1`), so it stays steady whether the project is static, Next or Vite.
- Works the same on a fresh start or a resume (`cc --resume`, `cc --continue`).
- The port is auto-detected from `package.json` (3000 for Next, 5173 for Vite).

| Command | What it does |
|---|---|
| `cc` | Launch Claude Code with the dev stack up before and torn down after. Passes args through |
| `devup [port]` | Start server + tunnel manually. Port is auto-detected unless you pass one |
| `devdown [port]` | Kill the server + tunnel on that port. A fallback for orphaned processes |

**Implementation note:** `cc` runs Claude Code in the current shell and calls `devdown` when it returns. No subshell, no `trap`, so teardown fires on `/exit` and nothing can kill the tunnel mid-session. Claude Code's session hooks don't fire reliably on resume or quit, so I don't depend on them.

---

## Aurora Usage

Two gauges on one fuel tank, so I always know how much of my Max plan is left. Details in [`aurora-usage/README.md`](aurora-usage/README.md).

**The billboard** is a Claude Code mod that draws one thin line above the prompt, in the terminal and the desktop app's Code tab:

```
5h ━━━━━━━━━━━━ 31% ⏰1h38m │ 7d ━━━━━━━━━━━━ 64% ⏰2d15h │ Opus 5.5 ━━━━━━━━━━━━ 42% 420.0k/1.0M │ $1.42
```

- The 5-hour and 7-day windows with reset countdowns, then the model's context fill and the session cost.
- Each cell is colored by its position on the bar, so a fuller bar reaches further into the hot end. `/billboard theme aurora|ember|tide|mono` swaps the palette.
- `⚡ using credits` appears when a window passes 100%, and a window drops back to 0% the moment its reset time passes.
- Toasts at 80% and 95%, once per window.

**The HUD** is a small native macOS panel that floats over everything, so the same 5h and 7d bars are visible while I'm in Chat or Projects. One Swift file, AppKit only. The billboard writes each reading to a small shared file and the HUD reads it, so the two always agree. A refresh button pulls a fresh reading on demand, which covers Chat-only stretches.

Neither piece makes a network call, reads a login token, or pulls in third-party code. I built this instead of installing a usage bar that read my credentials and auto-updated itself.

---

## Sketchpad

A side conversation docked next to the session, where I brainstorm and refine a prompt before sending it to the prompt box. Details in [`sketchpad/`](sketchpad/).

---

## New machine setup

```bash
xcode-select --install   # once, for the Aurora HUD's Swift compiler
brew install cloudflared jq
git clone https://github.com/BernardoDesigns/bernardo-claude-config.git ~/LocalDev/bernardo-claude-config
cd ~/LocalDev/bernardo-claude-config
bash setup.sh
```

Then open a new terminal. `setup.sh`:

- symlinks `~/.claude/commands` and `~/.dev-aliases.sh` to the repo copies
- adds a source line to `.zshrc`
- adds the Aurora billboard to `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` without touching any other key, and removes the old `statusLine` entry if it's still there
- builds the Aurora HUD and starts it at login (skip with `bash setup.sh --no-hud`)
- backs up any existing file it would replace (timestamped), and is safe to re-run

## Keeping machines in sync

The repo is the single source of truth. Everything is symlinked or loaded straight from the repo, so a `git pull` on any machine picks up changes instantly. The HUD is the exception: it's compiled, so re-run `setup.sh` after pulling changes to `main.swift`. Re-run `setup.sh` only on a new machine or when the install logic itself changes.

## What's in the repo

| File | Purpose |
|---|---|
| `commands/design-director.md` | Router agent and the shared session debrief protocol |
| `commands/eames.md` | Product design specialist |
| `commands/rand.md` | Brand design specialist |
| `dev-aliases.sh` | `cc`, `devup`, `devdown` |
| `aurora-usage/aurora-billboard/` | Usage billboard mod for Claude Code |
| `aurora-usage/aurora-hud/` | Floating usage HUD for macOS (`main.swift` + build scripts) |
| `setup.sh` | Idempotent installer |
