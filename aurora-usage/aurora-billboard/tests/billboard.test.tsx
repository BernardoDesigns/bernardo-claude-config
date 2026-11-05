import { expect, test } from 'claude-code/testing'

import { spectrum, themeOf } from '../hooks/themes'

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

const SHARED = '/home/test/.claude/aurora-usage.json'

// A shared file with the given extra keys, for seeding what the HUD wrote.
const seeded = (keys: object): Record<string, string> => ({ [SHARED]: JSON.stringify({ v: 1, ...keys }) })
const ALWAYS = { showAt: { '5h': 0, '7d': 0 } }

// Fixed times: a window is known by its reset, so these must hold across readings.
const FIVE_HOUR_RESET = inHours(2)
const SEVEN_DAY_RESET = inHours(63.2)
const usageAt = (fiveHour: number, sevenDay: number) => ({
  ...USAGE,
  rateLimits: [
    { kind: 'five_hour', percentUsed: fiveHour, resetsAt: FIVE_HOUR_RESET },
    { kind: 'seven_day', percentUsed: sevenDay, resetsAt: SEVEN_DAY_RESET },
  ],
})

const measure = ($: any, usage: any) =>
  $.session.measure({ rateLimits: usage.rateLimits, context: usage.context, cost: usage.cost })

// files stands in for the disk; a missing path rejects the read like ENOENT.
function stubEngine(on: any, usage: any = USAGE, files: Record<string, string> = {}, toasts: string[] = []) {
  on('env.get', () => ({ value: '/home/test' }))
  on('fs.read', (_: unknown, e: any) => {
    if (files[e.path] === undefined) throw new Error('ENOENT')
    return { value: files[e.path] }
  })
  on('fs.write', (_: unknown, e: any) => {
    files[e.path] = e.text
    return { value: undefined }
  })
  on('command.register', () => ({ value: { command: 'billboard' } }))
  on('store.get', () => ({ value: undefined }))
  on('store.set', () => ({ value: undefined }))
  on('session.usage', () => ({ value: usage }))
  on('clock.every', () => ({ value: undefined }))
  on('clock.now', () => ({ value: Date.now() }))
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('turn.complete', () => ({ text: 'ok' }))
  on('command.run', () => ({ text: '' }))
  on('session.measure', () => ({ changed: [] }))
  on('ui.toast', (_: unknown, e: any) => {
    toasts.push(e.text)
    return { value: undefined }
  })
}

test('the band shows both limits, countdowns and the model on terminal and desktop', async ($, on) => {
  stubEngine(on, USAGE, seeded(ALWAYS))
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
  }, seeded(ALWAYS))
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

test('the reading and the theme land in the shared file for the HUD', async ($, on) => {
  const files: Record<string, string> = {}
  stubEngine(on, USAGE, files)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const first = JSON.parse(files[SHARED]!)
  expect(first.fiveHour.percent).toBe(31)
  expect(first.sevenDay.percent).toBe(64)
  expect(typeof first.updatedAt).toBe('number')

  await $.command.run({ command: 'billboard', args: 'theme tide' } as any)
  const after = JSON.parse(files[SHARED]!)
  expect(after.theme).toBe('tide')
  expect(after.fiveHour.percent).toBe(31)
})

test('a session with no reading leaves the last one alone', async ($, on) => {
  const files = { [SHARED]: JSON.stringify({ v: 1, updatedAt: 1, fiveHour: { percent: 50 }, sevenDay: null }) }
  stubEngine(on, { ...USAGE, rateLimits: [] }, files)
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect(JSON.parse(files[SHARED]!).fiveHour.percent).toBe(50)
})

test('a theme picked in the HUD carries into the band', async ($, on) => {
  stubEngine(on, USAGE, { [SHARED]: JSON.stringify({ v: 1, theme: 'ember' }) })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const list = await $.command.run({ command: 'billboard', args: '' } as any)
  expect(list.text).toContain('current: ember')
})

const mountBand = ($: any, surface: 'terminal' | 'desktop' = 'terminal') => $.ui.mount({ ...BAND, surface })
const start = ($: any) => $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

test('under both lines the limits stay hidden and context stays', async ($, on) => {
  stubEngine(on, usageAt(74, 89))
  await start($)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await mountBand($, surface)
    expect(await ui.find({ type: 'Text', text: /74%/ })).toBeFalsy()
    expect(await ui.find({ type: 'Text', text: /89%/ })).toBeFalsy()
    expect(await ui.find({ type: 'Text', text: /42%/ })).toBeTruthy()
    expect(await ui.find({ type: 'Text', text: /\$1\.42/ })).toBeTruthy()
    await ui.unmount()
  }
})

test('crossing one line shows both, with the other dimmed', async ($, on) => {
  stubEngine(on, usageAt(75, 64))
  await start($)
  const raised = await mountBand($)
  // The run that draws the number itself, not the Texts wrapped around it.
  const number = async (text: RegExp) =>
    (await raised.findAll({ type: 'Text', text })).find((t: any) => t.props.weight)
  const hot = await number(/75%/)
  const quiet = await number(/64%/)
  expect(hot?.props.weight).toBe('bold')
  expect(quiet?.props.weight).toBe('regular')
  // Faded toward the theme's track color, so it isn't the position's full color.
  expect(quiet?.props.color).not.toBe(spectrum(themeOf('aurora'), 0.64))
  await raised.unmount()
})

test('the weekly limit waits for its later line', async ($, on) => {
  stubEngine(on, usageAt(10, 90))
  await start($)
  const ui = await mountBand($)
  expect(await ui.find({ type: 'Text', text: /90%/ })).toBeTruthy()
  expect(await ui.find({ type: 'Text', text: /10%/ })).toBeTruthy()
  await ui.unmount()
})

test('lines and snoozes set in the HUD apply to the band', async ($, on) => {
  stubEngine(on, usageAt(40, 32), seeded({ showAt: { '5h': 30 } }))
  await start($)
  const ui = await mountBand($)
  expect(await ui.find({ type: 'Text', text: /40%/ })).toBeTruthy()
  await ui.unmount()
})

test('a snooze from the HUD holds until the next step, then clears', async ($, on) => {
  const files = seeded({ snooze: { '5h': 90 } })
  stubEngine(on, usageAt(80, 32), files)
  await start($)
  const held = await mountBand($)
  expect(await held.find({ type: 'Text', text: /80%/ })).toBeFalsy()
  await held.unmount()

  await measure($, usageAt(90, 32))
  const up = await mountBand($)
  expect(await up.find({ type: 'Text', text: /90%/ })).toBeTruthy()
  await up.unmount()
  expect(JSON.parse(files[SHARED]!).snooze['5h']).toBeUndefined()
})

test('dropping under the line clears a snooze', async ($, on) => {
  const files = seeded({ snooze: { '5h': 101 } })
  stubEngine(on, usageAt(3, 32), files)
  await start($)
  expect(JSON.parse(files[SHARED]!).snooze['5h']).toBeUndefined()
})

test('/billboard show sets a line in the shared file and clears its snooze', async ($, on) => {
  const files = seeded({ snooze: { '5h': 90 } })
  stubEngine(on, usageAt(40, 32), files)
  await start($)

  const ok = await $.command.run({ command: 'billboard', args: 'show 5h 30' } as any)
  expect(ok.text).toContain('5h shows at 30%')
  const shared = JSON.parse(files[SHARED]!)
  expect(shared.showAt['5h']).toBe(30)
  expect(shared.snooze['5h']).toBeUndefined()

  const ui = await mountBand($)
  expect(await ui.find({ type: 'Text', text: /40%/ })).toBeTruthy()
  await ui.unmount()

  await $.command.run({ command: 'billboard', args: 'show 7d always' } as any)
  await $.command.run({ command: 'billboard', args: 'show 5h off' } as any)
  const after = JSON.parse(files[SHARED]!)
  expect(after.showAt['7d']).toBe(0)
  expect(after.showAt['5h']).toBe(101)

  const bad = await $.command.run({ command: 'billboard', args: 'show 5h lots' } as any)
  expect(bad.text).toContain('Try')
  const worse = await $.command.run({ command: 'billboard', args: 'show 3d 50' } as any)
  expect(worse.text).toContain('Try')
})

test('/billboard hide walks 90, 95, then the reset', async ($, on) => {
  const files: Record<string, string> = {}
  stubEngine(on, usageAt(80, 32), files)
  await start($)

  const first = await $.command.run({ command: 'billboard', args: 'hide' } as any)
  expect(first.text).toContain('5h hits 90%')
  expect(JSON.parse(files[SHARED]!).snooze['5h']).toBe(90)
  const hidden = await mountBand($)
  expect(await hidden.find({ type: 'Text', text: /80%/ })).toBeFalsy()
  await hidden.unmount()

  await measure($, usageAt(91, 32))
  const second = await $.command.run({ command: 'billboard', args: 'hide' } as any)
  expect(second.text).toContain('5h hits 95%')

  await measure($, usageAt(96, 32))
  const third = await $.command.run({ command: 'billboard', args: 'hide' } as any)
  expect(third.text).toContain('5h resets')

  await measure($, usageAt(99, 32))
  const nothing = await $.command.run({ command: 'billboard', args: 'hide' } as any)
  expect(nothing.text).toContain('Nothing to hide')
})

test('hide goes by the newest reading in the file, not an idle session\'s own', async ($, on) => {
  const files: Record<string, string> = {}
  stubEngine(on, usageAt(11, 32), files)
  await start($)
  const shared = JSON.parse(files[SHARED]!)
  files[SHARED] = JSON.stringify({ ...shared, fiveHour: { percent: 80, resetsAt: inHours(2) } })

  const res = await $.command.run({ command: 'billboard', args: 'hide' } as any)
  expect(res.text).toContain('5h hits 90%')
})

test('toasts fire at each limit\'s line and at 95, once', async ($, on) => {
  const toasts: string[] = []
  stubEngine(on, usageAt(10, 10), {}, toasts)
  await start($)

  await measure($, usageAt(74, 89))
  expect(toasts).toHaveLength(0)
  await measure($, usageAt(75, 89))
  await measure($, usageAt(80, 89))
  expect(toasts).toEqual(['Heads up: 5-hour limit at 75%'])
  await measure($, usageAt(95, 90))
  expect(toasts).toEqual([
    'Heads up: 5-hour limit at 75%',
    'Heads up: 5-hour limit at 95%',
    'Heads up: weekly limit at 90%',
  ])
})

test('a limit set to off never toasts or raises, but credits still show', async ($, on) => {
  const toasts: string[] = []
  stubEngine(on, usageAt(99, 32), seeded({ showAt: { '5h': 101 } }), toasts)
  await start($)
  const quiet = await mountBand($)
  expect(await quiet.find({ type: 'Text', text: /99%/ })).toBeFalsy()
  await quiet.unmount()

  await measure($, usageAt(100, 32))
  expect(toasts).toHaveLength(0)
  const ui = await mountBand($)
  expect(await ui.find({ type: 'Text', text: /100%/ })).toBeFalsy()
  expect(await ui.find({ type: 'Text', text: /⚡ using credits/ })).toBeTruthy()
  await ui.unmount()
})
