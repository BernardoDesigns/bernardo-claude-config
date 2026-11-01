import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'aurora-billboard',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 140,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

const inHours = (h: number) => new Date(Date.now() + h * 3600_000).toISOString()

const USAGE = {
  startedAt: 0,
  context: { tokens: 420_000, window: 1_000_000, percent: 42 },
  rateLimits: [
    { kind: 'five_hour', percentUsed: 31, resetsAt: inHours(1.65) },
    { kind: 'seven_day', percentUsed: 64, resetsAt: inHours(63.2) },
  ],
  cost: { usd: 1.42 },
}

function stubEngine(on: any, usage: any = USAGE) {
  on('command.register', () => ({ value: { command: 'billboard' } }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('session.usage', () => ({ value: usage }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => ({ value: Date.now() }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('turn.complete', () => ({ text: 'ok' }))
  on('command.run', () => ({ text: '' }))
}

test('the band shows both limits, countdowns and the model on terminal and desktop', async ($, on) => {
  stubEngine(on)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.turn.complete({
    answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer',
    usage: { model: 'claude-opus-5-5', input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
  } as any)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect((await ui.find({ type: 'Text', text: /31%/ }))?.text).toContain('31%')
    expect((await ui.find({ type: 'Text', text: /64%/ }))?.text).toContain('64%')
    expect((await ui.find({ type: 'Text', text: /⏰1h3\dm/ }))).toBeTruthy()
    expect((await ui.find({ type: 'Text', text: /Opus 5\.5/ }))).toBeTruthy()
    expect((await ui.find({ type: 'Text', text: /42%/ }))?.text).toContain('42%')
    expect((await ui.find({ type: 'Text', text: /420\.0k\/1\.0M/ }))).toBeTruthy()
    expect((await ui.find({ type: 'Text', text: /\$1\.42/ }))).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /using credits/ })).toBeFalsy()
    await ui.unmount()
  }
})

test('/billboard theme switches and rejects unknown names', async ($, on) => {
  stubEngine(on)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ok = await $.command.run({ command: 'billboard', args: 'theme tide' } as any)
  expect(ok.text).toContain('Tide')
  const bad = await $.command.run({ command: 'billboard', args: 'theme neon' } as any)
  expect(bad.text).toContain('No theme')
})

test('a window past its reset reads 0% with no countdown', async ($, on) => {
  stubEngine(on, {
    ...USAGE,
    rateLimits: [
      { kind: 'five_hour', percentUsed: 100, resetsAt: inHours(-0.5) },
      { kind: 'seven_day', percentUsed: 64, resetsAt: inHours(63.2) },
    ],
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /^ ?0%/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /100%/ })).toBeFalsy()
  expect(await ui.find({ type: 'Text', text: /⏰now/ })).toBeFalsy()
  expect(await ui.find({ type: 'Text', text: /using credits/ })).toBeFalsy()
  await ui.unmount()
})

test('a maxed window flags credits', async ($, on) => {
  stubEngine(on, {
    ...USAGE,
    rateLimits: [
      { kind: 'five_hour', percentUsed: 100, resetsAt: inHours(2) },
      { kind: 'seven_day', percentUsed: 64, resetsAt: inHours(63.2) },
    ],
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /⚡ using credits/ }))).toBeTruthy()
  await ui.unmount()
})
