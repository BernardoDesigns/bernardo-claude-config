import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'sketchpad',
  component: 'Pane',
  requestId: 'sketchpad',
  props: {
    title: 'Sketchpad',
    isFocused: true,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const usage = { input_tokens: 10, output_tokens: 10, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 }

// Stand in for the engine. Returns what the mod sent so tests can check it.
function engine(on: any, opts: { promptBox?: string } = {}) {
  const sent = { complete: [] as any[], forks: 0, fills: [] as any[], toasts: [] as string[] }
  on('command.register', () => ({ value: { command: 'sketch' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('fs.exists', () => ({ value: false }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('ui.toast', (_: unknown, e: any) => {
    sent.toasts.push(String(e.text ?? e))
    return { value: undefined }
  })
  on('prompt.read', () => ({ value: { text: opts.promptBox ?? '', cursor: 0 } }))
  on('prompt.fill', (_: unknown, e: any) => {
    sent.fills.push(e)
    return { isFilled: true, text: e.text }
  })
  on('model.fork', () => {
    sent.forks++
    return { value: { isAnswered: false, reason: 'nothing-to-fork' } }
  })
  on('model.complete', (_: unknown, e: any) => {
    sent.complete.push(e)
    const p = JSON.stringify(e.prompt)
    const text = p.includes('Turn the conversation above')
      ? 'Build a pricing page.\n\nDone when: three tiers render.'
      : 'Sharp. Who is it for?'
    return { value: { isAnswered: true, text, usage } }
  })
  return sent
}

test('chat, refine, and send to an empty prompt box, on terminal and desktop', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/work/banner-cms', surface: 'desktop', isInteractive: true })
  const opened = await $.command.run({ command: 'sketch', args: '' } as any)
  expect(opened.text).toContain('Sketchpad open')

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    await ui.press({ key: 'clear' })

    await ui.input({ key: 'sketch-input', text: 'pricing page idea' })
    expect((await ui.find({ type: 'Markdown', text: /Who is it for/ }))).toBeTruthy()
    expect(JSON.stringify(sent.complete.at(-1).prompt)).toContain('pricing page idea')
    expect(sent.complete.at(-1).model).toBe('sonnet')

    await ui.press({ key: 'refine' })
    expect((await ui.find({ type: 'Text', text: /Ready for Claude Code/ }))).toBeTruthy()

    await ui.press({ key: 'send' })
    expect(sent.fills.at(-1).text).toBe('Build a pricing page.\n\nDone when: three tiers render.')
    expect(sent.fills.at(-1).mode).toBe('replace')
    await ui.unmount()
  }
})

test('send goes under an existing draft instead of replacing it', async ($, on) => {
  const sent = engine(on, { promptBox: 'my half-typed thought' })
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.input({ key: 'sketch-input', text: 'idea' })
  await ui.press({ key: 'send' })
  expect(sent.fills.at(-1).mode).toBe('append')
  expect(sent.fills.at(-1).text).toBe('\n\nSharp. Who is it for?')
  await ui.unmount()
})

test('session mode tries a fork and falls back with a note when there is nothing to share', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'session' })
  expect((await ui.find({ type: 'Text', text: /sees the session/ }))).toBeTruthy()
  await ui.input({ key: 'sketch-input', text: 'what did we build?' })
  expect(sent.forks).toBe(1)
  expect(sent.complete.length).toBe(1)
  expect((await ui.find({ type: 'Text', text: /nothing to share yet/ }))).toBeTruthy()
  await ui.unmount()
})

test('the model button cycles and the choice is used', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  await ui.press({ key: 'model' })
  await ui.input({ key: 'sketch-input', text: 'go deep' })
  expect(sent.complete.at(-1).model).toBe('opus')
  await ui.unmount()
})

test('Refine with nothing sketched only nudges', async ($, on) => {
  const sent = engine(on)
  await $.session.start({ cwd: '/w', surface: 'desktop', isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'refine' })
  expect(sent.complete.length).toBe(0)
  expect(sent.toasts.join(' ')).toContain('Sketch something first')
  await ui.unmount()
})
