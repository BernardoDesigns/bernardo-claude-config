# bernardo-claude-config

Personal Claude Code config, version-controlled and synced across machines.
Holds three things: design agent slash commands (`commands/`), a portable
local dev environment (`dev-aliases.sh`), and the Claude Code status line
(`statusline.sh`).

One repo, one installer. Clone it on any machine, run `setup.sh`, and you get
the whole kit wired in.

---

## Daily rhythm

From inside any project (a repo with a `package.json` + a `dev` script):

```bash
cc        # starts the dev server + a cloudflare tunnel, then launches Claude Code
/exit     # quits Claude Code, which auto-kills the server + tunnel
```

That's the whole loop. `cc` to sit down, `/exit` to stand up.

- The public tunnel URL is **copied to your clipboard** and shown as a **macOS
  notification** the moment it's ready, so just Cmd+V into a browser.
- Works the same on a fresh start *or* a resume (`cc --resume`, `cc --continue`).
- Port is auto-detected from `package.json` (3000 for Next, 5173 for Vite), so
  there's nothing to configure per project.

### The commands

| Command | What it does |
| --- | --- |
| `cc` | Launch Claude Code with the dev stack up before and killed after. Passes args through. |
| `devup [port]` | Start server + tunnel manually (default :5173). |
| `devdown [port]` | Kill the server + tunnel on that port. The fallback if something gets orphaned. |

`devdown` is a safety net, not part of the daily flow. `/exit` handles teardown
on its own.

---

## New machine setup

Two commands and you're running:

```bash
git clone <repo-url> ~/LocalDev/bernardo-claude-config
cd ~/LocalDev/bernardo-claude-config
bash setup.sh
```

Then open a fresh terminal. `setup.sh` symlinks `~/.claude/commands`,
`~/.claude/statusline.sh` and `~/.dev-aliases.sh` to the repo copies, wires the
source line into `.zshrc`, and merges the `statusLine` entry into
`~/.claude/settings.json` (every other key is left alone).
It's idempotent, so re-running it is always safe, and it backs up any real file
that's already in the way (timestamped) before linking.

Requirements:

```bash
brew install cloudflared jq
npm install -g ccusage
```

`setup.sh` checks for `jq` and `ccusage` and prints the install command if
either is missing.

---

## Status line

Two lines at the bottom of every Claude Code session:

```
Opus 5.5 | session $1.24 | ctx ▓▓▓░░░░░░░ 31% | today $18.40 (all projects)
session ▓▓▓▓░░░░░░ 42% resets 6:20 PM | week ▓▓░░░░░░░░ 18% resets Tue 2:00 PM
```

- **Line 1:** model, this session's cost, context window fill, and today's
  spend across every project (from `ccusage`, cached for 60s).
- **Line 2:** rate limits for the 5-hour session window and the 7-day week.
  Bars go green under 50%, yellow to 80%, red above.

A fresh session doesn't get rate limit data until the first response lands, so
the last known values are cached in `~/.claude/statusline-limits.json`. When
line 2 is showing cached numbers you'll see a `·` after the percentage
(`42% ·`). It drops off as soon as live data arrives. If a window's reset time
has already passed, the bar shows 0% instead of stale usage.

---

## Keeping machines in sync

The repo is the single source of truth. Each machine's `~/.dev-aliases.sh` is a
symlink pointing at the repo copy, so:

```bash
# edit dev-aliases.sh, then on the machine you edited:
git add dev-aliases.sh && git commit -m "tweak aliases" && git push

# on every other machine:
git pull
```

A `git pull` is enough to pick up alias changes (the symlink reflects the file
instantly, no re-install). Only re-run `setup.sh` if the *install logic* itself
changes or you're setting up a brand-new machine.

---

## How it's wired (so future-you remembers)

- `dev-aliases.sh` — the real file, version-controlled here. Defines `devup`,
  `devdown`, `cc`.
- `~/.dev-aliases.sh` — a symlink on each machine pointing at the file above.
- `.zshrc` — sources `~/.dev-aliases.sh` on every new shell.
- `statusline.sh` — the real status line script, version-controlled here.
- `~/.claude/statusline.sh` — a symlink on each machine pointing at it.
  `~/.claude/settings.json` points `statusLine` at the symlink, so a
  `git pull` updates the status line with no re-install.
- `cc` runs the stack in a subshell with a `trap` on EXIT/HUP, which is what
  guarantees teardown happens however you quit (not relying on Claude Code's
  session hooks, which don't fire reliably on resume or on quit).
