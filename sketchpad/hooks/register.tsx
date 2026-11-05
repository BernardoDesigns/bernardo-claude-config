import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Msg } from '../types'

// Sketchpad: a sketchbook clipped to the side of the workbench. Rough an idea out
// here, in its own conversation, then tear off the page (Refine) and pin it to
// the bench (Send to prompt). Nothing here lands in the build session's context
// until you send it.

const PANE = 'sketchpad'
const TITLE = 'Sketchpad'

// Aurora palette, same values as the billboard and the HUD.
const C = {
  ok: '#8bc66b',
  warn: '#e5b454',
  hot: '#e0685c',
  mute: '#8b8f98',
  accent: '#c99be8',
}

const MODELS = ['sonnet', 'opus', 'haiku'] as const
const MODEL_LABEL: Record<string, string> = { sonnet: 'Sonnet', opus: 'Opus', haiku: 'Haiku' }

const messages = atom({ plugin: 'sketchpad', key: 'messages' } as const, [], { shape: 'msgs-1' })
const ready = atom({ plugin: 'sketchpad', key: 'ready' } as const, null)
const busy = atom({ plugin: 'sketchpad', key: 'busy' } as const, false)
const seesSession = atom({ plugin: 'sketchpad', key: 'seesSession' } as const, false)
const model = atom({ plugin: 'sketchpad', key: 'model' } as const, 'sonnet')

const RULES = `You are the Sketchpad, a side conversation docked beside a Claude Code session.
The person is a senior product designer. They use you to explore, brainstorm and sharpen ideas into prompts before handing them to Claude Code to build.

How to work:
- Be casual, direct and brief. Short replies unless asked to go deep.
- Push back on vague asks. Name the missing piece (goal, scope, what "done" looks like, constraints, which files) in one line, and suggest a sensible default.
- A metaphor helps when a concept is tricky.
- Offer options when there's a real fork in the road, with your pick.
- You have no tools. Never claim you ran, read or changed anything beyond what is in this conversation.`

const REFINE = `Turn the conversation above into ONE prompt for Claude Code to build from.

Shape it like this:
- First line: the goal, in one sentence.
- Context: what exists and what matters (files or areas, if known).
- Task: numbered steps.
- Constraints: what to keep, avoid or ask about first.
- Done when: checkable outcomes.
- Ask me first: open questions, only if any are still undecided.

Plain language, no filler, no em dashes. Leave out anything that was rejected along the way. Reply with the prompt only, nothing before or after it.`

const MAX_TRANSCRIPT = 60_000
const MAX_NOTES = 8_000

function transcript(list: readonly Msg[]): string {
  const lines = list
    .filter(m => m.role !== 'note')
    .map(m => `${m.role === 'you' ? 'Person' : 'Sketchpad'}: ${m.text}`)
  let text = lines.join('\n\n')
  while (text.length > MAX_TRANSCRIPT && lines.length > 1) {
    lines.shift()
    text = '(earlier messages trimmed)\n\n' + lines.join('\n\n')
  }
  return text
}

export const register: Register = on => {
  // Per-process scratch, rebuilt on reload: the project's notes and the text being typed.
  let projectName = ''
  let projectNotes = ''
  let typed = ''
  let stop: AbortController | null = null

  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    await $.command.register({
      name: 'sketch',
      description: 'Sketchpad: a side conversation for shaping prompts. /sketch, /sketch clear, /sketch model opus',
    })
    projectName = e.cwd.split('/').filter(Boolean).pop() ?? ''
    try {
      if (await $.fs.exists('CLAUDE.md')) projectNotes = (await $.fs.read('CLAUDE.md')).slice(0, MAX_NOTES)
    } catch {
      projectNotes = ''
    }
    const savedModel = await $.store.get('model')
    if (typeof savedModel === 'string' && MODELS.includes(savedModel as (typeof MODELS)[number])) {
      await update($, model, () => savedModel)
    }
    return ran
  })

  on('command.run', { command: 'sketch' }, async ($, e) => {
    const [sub, value] = e.args.trim().split(/\s+/)
    if (sub === 'clear') {
      stop?.abort()
      await update($, messages, () => [])
      await update($, ready, () => null)
      return { text: 'Sketchpad cleared.' }
    }
    if (sub === 'model') {
      if (!value || !MODELS.includes(value as (typeof MODELS)[number])) {
        return { text: `Sketchpad models: ${MODELS.join(', ')}` }
      }
      await update($, model, () => value)
      await $.store.set('model', value)
      return { text: `Sketchpad model: ${MODEL_LABEL[value]}` }
    }
    const opened = await $.ui.open({ id: PANE, title: TITLE, focus: true, closeOnEscape: true })
    return { text: opened.isPlaced ? 'Sketchpad open. Esc closes it.' : 'Sketchpad is waiting for room to open.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button, Input, Markdown } = $.ui.resolve(e)
    const list = await read($, messages)
    const prompt = await read($, ready)
    const isBusy = await read($, busy)
    const withSession = await read($, seesSession)
    const modelName = await read($, model)

    // Ask the model. `refine` turns the whole sketch into one prompt for Claude Code.
    const ask = async (refine: boolean) => {
      if (await read($, busy)) return
      const now = await read($, messages)
      if (now.filter(m => m.role !== 'note').length === 0) {
        $.ui.toast('Sketch something first')
        return
      }
      await update($, busy, () => true)
      stop = new AbortController()

      const convo = transcript(now)
      const tail = refine
        ? REFINE
        : 'Reply to the last message from the person, as the Sketchpad.'
      const notes = projectNotes
        ? `\n\nProject: ${projectName}\nFrom its CLAUDE.md:\n${projectNotes}`
        : projectName ? `\n\nProject: ${projectName}` : ''

      let r
      let fellBack = false
      if (await read($, seesSession)) {
        r = await $.model.fork({
          prompt:
            `[Side conversation from the Sketchpad pane. Don't continue the build work above; use it only as context.]\n\n` +
            `${RULES}\n\nThe sketch so far:\n\n${convo}\n\n${tail}`,
        })
        if (!r.isAnswered && r.reason === 'nothing-to-fork') fellBack = true
      }
      if (!r || fellBack) {
        r = await $.model.complete(
          {
            model: await read($, model),
            system: [{ text: RULES + notes, cache: true }],
            prompt: `${convo}\n\n${tail}`,
            maxTokens: refine ? 4000 : 2000,
          },
          { signal: stop.signal },
        )
      }

      if (r.isAnswered) {
        const text = r.text.trim()
        if (refine) {
          await update($, ready, () => text)
        } else {
          await update($, messages, (l): Msg[] => [...l, { role: 'claude', text }])
        }
        if (fellBack) {
          await update($, messages, (l): Msg[] => [
            ...l,
            { role: 'note', text: 'The session had nothing to share yet, so that answer came from the sketch alone.' },
          ])
        }
      } else if (r.reason !== 'aborted') {
        const why = r.reason === 'api-error' ? `API error ${r.status}` : r.reason
        await update($, messages, (l): Msg[] => [...l, { role: 'note', text: `No reply (${why}). Try again.` }])
      }
      stop = null
      await update($, busy, () => false)
    }

    const send = async (value: string) => {
      const text = value.trim()
      if (!text || (await read($, busy))) return
      typed = ''
      await update($, messages, (l): Msg[] => [...l, { role: 'you', text }])
      await ask(false)
    }

    const toPrompt = async () => {
      const latest = await read($, messages)
      const text = (await read($, ready)) ?? [...latest].reverse().find(m => m.role === 'claude')?.text
      if (!text) {
        $.ui.toast('Nothing to send yet. Try Refine first.')
        return
      }
      const box = await $.prompt.read()
      const hasDraft = box.text.trim().length > 0
      await $.prompt.fill({ text: hasDraft ? `\n\n${text}` : text, mode: hasDraft ? 'append' : 'replace' })
      $.ui.toast(hasDraft ? 'Added under your draft. Give it a read, then send.' : 'In the prompt box. Give it a read, then send.')
    }

    const clear = async () => {
      stop?.abort()
      typed = ''
      await update($, messages, () => [])
      await update($, ready, () => null)
      await update($, busy, () => false)
    }

    const cycleModel = async () => {
      const i = MODELS.indexOf(modelName as (typeof MODELS)[number])
      const nextModel = MODELS[(i + 1) % MODELS.length]!
      await update($, model, () => nextModel)
      await $.store.set('model', nextModel)
    }

    const shown = list.slice(-30)

    return (
      <Box flexDirection="column" gap={1} paddingX={1}>
        <Text color={C.mute}>
          {projectName ? `${projectName} · ` : ''}
          {withSession ? 'sees the session' : 'sketch only'} · {withSession ? 'session model' : MODEL_LABEL[modelName] ?? modelName}
        </Text>

        {shown.length === 0 && (
          <Text color={C.mute}>
            Rough out an idea here. It stays out of your build session. When it's sharp, hit Refine, then Send to prompt.
          </Text>
        )}

        {shown.map(m =>
          m.role === 'note' ? (
            <Text color={C.mute} italic>
              {m.text}
            </Text>
          ) : (
            <Box flexDirection="column">
              <Text color={m.role === 'you' ? C.accent : C.ok} bold>
                {m.role === 'you' ? 'You' : 'Sketchpad'}
              </Text>
              <Markdown text={m.text} />
            </Box>
          ),
        )}

        {isBusy && <Text color={C.mute}>thinking…</Text>}

        {prompt && (
          <Box flexDirection="column" borderStyle="round" borderColor={C.warn} paddingX={1}>
            <Text color={C.warn} bold>
              Ready for Claude Code
            </Text>
            <Markdown text={prompt} />
          </Box>
        )}

        <Input
          key="sketch-input"
          rows={3}
          placeholder="Think out loud…"
          submitLabel="send"
          value={typed}
          autoFocus
          onInput={value => {
            typed = value
          }}
          onSubmit={value => void send(value)}
        />

        <Box flexDirection="row" gap={1} flexWrap="wrap">
          <Button key="refine" variant="primary" onPress={() => void ask(true)}>
            Refine
          </Button>
          <Button key="send" onPress={() => void toPrompt()}>Send to prompt</Button>
          <Button key="model" onPress={() => void cycleModel()}>{MODEL_LABEL[modelName] ?? modelName}</Button>
          <Button key="session" onPress={() => void update($, seesSession, v => !v)}>
            {withSession ? 'Session: on' : 'Session: off'}
          </Button>
          <Button key="clear" onPress={() => void clear()}>Clear</Button>
        </Box>
      </Box>
    )
  })
}
