# Sketchpad

A sketchbook clipped to the side of your workbench. It's a side conversation docked next to your Claude Code session, for exploring and sharpening an idea into a prompt before you hand it to the build.

Nothing you sketch lands in the build session's context until you send it.

## Use it

Type `/sketch` to open the pane. Esc closes it, and it remembers the conversation for the rest of the session.

| Control | Does |
| --- | --- |
| **Input** (Enter) | Talk it through. Replies are short and push back on vague asks |
| **Refine** | Turns the whole sketch into one prompt for Claude Code: goal, context, numbered tasks, constraints, "done when", open questions |
| **Send to prompt** | Drops the refined prompt (or the last reply) into the prompt box. If you already typed something there, it goes underneath instead of replacing it. Review, then hit enter |
| **Sonnet / Opus / Haiku** | Switches the sketch model. Your pick is remembered |
| **Session: off / on** | Off: the sketch knows only itself and your project's CLAUDE.md. On: it can see the build session so far, without adding anything to it |
| **Clear** | Starts a fresh sketch |

Commands: `/sketch`, `/sketch clear`, `/sketch model opus|sonnet|haiku`

## Good to know

- **It draws from your plan limits** like any Claude Code request. Your Aurora billboard shows the cost.
- **"Session: on" costs more on a long session**, since it reads the whole conversation (mostly from cache). Use it when the prompt depends on what the build already did, like "next step after what we just shipped".
- **When the session has nothing to share yet** (right after starting or `/clear`), it answers from the sketch alone and says so.
- **It has no tools.** It can't read or change files beyond the CLAUDE.md it's given at startup. That's on purpose: thinking happens here, building happens in the session.
- **No network calls of its own and no credentials.** It only uses Claude Code's own model API.
