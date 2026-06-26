# bernardo-claude-config

Personal Claude Code config, version-controlled and synced across machines.
Holds two things: design agent slash commands (`commands/`) and a portable
local dev environment (`dev-aliases.sh`).

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

Then open a fresh terminal. `setup.sh` symlinks `~/.claude/commands` and
`~/.dev-aliases.sh` to the repo copies and wires the source line into `.zshrc`.
It's idempotent, so re-running it is always safe, and it backs up any real file
that's already in the way (timestamped) before linking.

Needs `cloudflared` installed: `brew install cloudflared`.

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
- `cc` runs the stack in a subshell with a `trap` on EXIT/HUP, which is what
  guarantees teardown happens however you quit (not relying on Claude Code's
  session hooks, which don't fire reliably on resume or on quit).
