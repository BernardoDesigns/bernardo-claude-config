# bernardo-claude-config

**My Claude Code setup, version-controlled and synced across machines.** It holds a small team of design agents, a one-command dev environment, and a custom status line. Clone it anywhere, run `setup.sh`, and the whole kit is wired in.

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

- The public tunnel URL is copied to the clipboard and announced with a macOS notification, so I can share a live preview right away.
- Works the same on a fresh start or a resume (`cc --resume`, `cc --continue`).
- The port is auto-detected from `package.json` (3000 for Next, 5173 for Vite).

| Command | What it does |
|---|---|
| `cc` | Launch Claude Code with the dev stack up before and torn down after. Passes args through |
| `devup [port]` | Start server + tunnel manually (default :5173) |
| `devdown [port]` | Kill the server + tunnel on that port. A fallback for orphaned processes |

**Implementation note:** `cc` runs the stack in a subshell with a `trap` on EXIT and HUP. That guarantees teardown however the session ends. Claude Code's session hooks don't fire reliably on resume or quit, so I don't depend on them.

---

## Status line

Two lines at the bottom of every Claude Code session:

```
Opus 5.5 | session $1.24 | ctx ▓▓▓░░░░░░░ 31%
session ▓▓▓▓░░░░░░ 42% resets 6:20 PM | week ▓▓░░░░░░░░ 18% resets Tue 2:00 PM
```

- **Line 1:** model, session cost, and context window usage. A red `⚡ using credits` flag appears when a usage limit hits 100%.
- **Line 2:** the 5-hour and 7-day usage windows, color-coded green, yellow, and red.
- Last known values are cached so a fresh session isn't blank. Cached numbers show a `·` until live data arrives, and expired windows reset to 0%.

---

## New machine setup

```bash
brew install cloudflared jq
git clone https://github.com/BernardoDesigns/bernardo-claude-config.git ~/LocalDev/bernardo-claude-config
cd ~/LocalDev/bernardo-claude-config
bash setup.sh
```

Then open a new terminal. `setup.sh`:

- symlinks `~/.claude/commands`, `~/.claude/statusline.sh`, and `~/.dev-aliases.sh` to the repo copies
- adds a source line to `.zshrc`
- merges the `statusLine` entry into `~/.claude/settings.json` without touching any other key
- backs up any existing file it would replace (timestamped), and is safe to re-run

## Keeping machines in sync

The repo is the single source of truth. Everything is symlinked, so a `git pull` on any machine picks up changes instantly. Re-run `setup.sh` only on a new machine or when the install logic itself changes.

## What's in the repo

| File | Purpose |
|---|---|
| `commands/design-director.md` | Router agent and the shared session debrief protocol |
| `commands/eames.md` | Product design specialist |
| `commands/rand.md` | Brand design specialist |
| `dev-aliases.sh` | `cc`, `devup`, `devdown` |
| `statusline.sh` | The two-line status line |
| `setup.sh` | Idempotent installer |
