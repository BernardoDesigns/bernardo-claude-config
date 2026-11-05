import { atom, read, update } from 'claude-code'
import type {
  EngineInterface,
  Register,
  SessionRateLimit,
  SessionContextUsage,
  SessionCost,
} from 'claude-code'

import type { Gate, Limit, LimitKey, Shared, Snapshot } from '../types'
import {
  LIMITS,
  decide,
  isPast,
  isRaised,
  levelLabel,
  lineOf,
  parseLevel,
  snoozable,
  toastLevels,
  type Readings,
} from './gate'
import {
  DEFAULT_THEME,
  THEMES,
  fmtDuration,
  fmtTokens,
  mix,
  prettyModel,
  spectrum,
  themeOf,
} from './themes'


// Bump a shape tag when that value's fields change, so a stale value from an
// earlier version is declined after a reload instead of breaking the band.
const snapshot = atom({ plugin: 'aurora-billboard', key: 'snapshot' } as const, null, { shape: 'snap-2' })
const model = atom({ plugin: 'aurora-billboard', key: 'model' } as const, null)
const theme = atom({ plugin: 'aurora-billboard', key: 'theme' } as const, DEFAULT_THEME)
const glyph = atom({ plugin: 'aurora-billboard', key: 'glyph' } as const, 'thin')
const now = atom({ plugin: 'aurora-billboard', key: 'now' } as const, 0)
const gate = atom({ plugin: 'aurora-billboard', key: 'gate' } as const, { showAt: {}, snooze: {} })

function pick(limits: SessionRateLimit[], kind: string): Limit | null {
  const l = limits.find(x => x.kind === kind)
  return l ? { percent: l.percentUsed, resetsAt: l.resetsAt } : null
}

function toSnapshot(
  limits: SessionRateLimit[],
  ctx: SessionContextUsage,
  cost: SessionCost | undefined,
): Snapshot {
  return {
    fiveHour: pick(limits, 'five_hour'),
    sevenDay: pick(limits, 'seven_day'),
    contextTokens: ctx.tokens,
    contextWindow: ctx.window,
    contextPercent: ctx.percent,
    costUsd: cost?.usd,
  }
}

// The floating HUD reads the last reading and the look from this one local
// file. Read-modify-write, so a session with no reading yet never blanks out
// another session's numbers. A failure here never touches the band.
async function sharedPath($: EngineInterface): Promise<string | null> {
  const home = await $.env.get('HOME')
  return home ? `${home}/.claude/aurora-usage.json` : null
}

async function readShared($: EngineInterface): Promise<Shared> {
  try {
    const path = await sharedPath($)
    return path ? (JSON.parse(String(await $.fs.read(path))) as Shared) : {}
  } catch {
    return {}
  }
}

async function share($: EngineInterface, patch: Shared): Promise<void> {
  try {
    const path = await sharedPath($)
    if (!path) return
    const next = { ...(await readShared($)), ...patch, v: 1 }
    await $.fs.write(path, JSON.stringify(next, null, 2) + '\n')
  } catch {}
}

async function shareReading($: EngineInterface, snap: Snapshot): Promise<void> {
  if (!snap.fiveHour && !snap.sevenDay) return
  await share($, { updatedAt: await $.clock.now(), fiveHour: snap.fiveHour, sevenDay: snap.sevenDay })
}

// A window whose reset time has passed is back to zero, even if no response
// has reported the new reading yet.
function live(lim: Limit, t: number): Limit {
  const at = lim.resetsAt ? Date.parse(lim.resetsAt) : NaN
  return Number.isFinite(at) && at <= t ? { percent: 0 } : lim
}

function readings(fiveHour: Limit | null | undefined, sevenDay: Limit | null | undefined, t: number): Readings {
  return {
    '5h': fiveHour ? live(fiveHour, t).percent : undefined,
    '7d': sevenDay ? live(sevenDay, t).percent : undefined,
  }
}

// Picks up what the HUD or another session changed: lines, snoozes and the
// newest reading. The file's reading decides when a snooze clears, because an
// idle session's own numbers can be hours old. Only writes when a snooze changed.
async function syncGate($: EngineInterface): Promise<Gate> {
  const shared = await readShared($)
  const g: Gate = { showAt: shared.showAt ?? {}, snooze: shared.snooze ?? {} }
  const r = readings(shared.fiveHour, shared.sevenDay, await $.clock.now())

  const snooze: Gate['snooze'] = {}
  for (const k of LIMITS) {
    const kept = decide(r[k], lineOf(g, k), g.snooze[k]).snooze
    if (kept !== undefined) snooze[k] = kept
  }
  if (LIMITS.some(k => snooze[k] !== g.snooze[k])) await share($, { snooze })

  const next: Gate = { showAt: g.showAt, snooze }
  await update($, gate, () => next)
  if (shared.fiveHour || shared.sevenDay) {
    await update($, snapshot, s =>
      s && {
        ...s,
        fiveHour: shared.fiveHour ?? s.fiveHour,
        sevenDay: shared.sevenDay ?? s.sevenDay,
      },
    )
  }
  return next
}

export const register: Register = on => {
  const toasted = new Set<string>()

  on('session.start', async ($, e, next) => {
    // The shared file wins, so a theme picked in the HUD carries over.
    const shared = await readShared($)
    const saved = shared.theme ?? (await $.store.get('theme'))
    if (typeof saved === 'string' && THEMES[saved]) await update($, theme, () => saved)
    const savedGlyph = shared.glyph ?? (await $.store.get('glyph'))
    if (savedGlyph === 'thin' || savedGlyph === 'block') await update($, glyph, () => savedGlyph)

    await $.command.register({
      name: 'billboard',
      description:
        'Usage billboard: /billboard theme <name>, bars thin|block, show 5h|7d <percent|always|off>, hide',
    })

    const ran = await next(e)
    const u = await $.session.usage()
    const first = toSnapshot(u.rateLimits, u.context, u.cost)
    await update($, snapshot, () => first)
    await shareReading($, first)
    await syncGate($)
    // Countdowns tick down between turns, and the HUD may have changed a line
    // or a snooze. Same 30s cadence as the HUD's own check.
    $.clock.every(30_000, async () => {
      await update($, now, () => Date.now())
      await syncGate($)
    })
    return ran
  })

  on('session.measure', async ($, e, next) => {
    const snap = toSnapshot(e.rateLimits, e.context, e.cost)
    await update($, snapshot, () => snap)
    await shareReading($, snap)
    const g = await syncGate($)

    for (const [key, label, lim] of [
      ['5h', '5-hour', snap.fiveHour],
      ['7d', 'weekly', snap.sevenDay],
    ] as const) {
      if (!lim) continue
      for (const t of toastLevels(lineOf(g, key))) {
        const key = `${label}:${t}:${lim.resetsAt ?? ''}`
        if (lim.percent >= t && !toasted.has(key)) {
          toasted.add(key)
          $.ui.toast(`Heads up: ${label} limit at ${Math.round(lim.percent)}%`)
        }
      }
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.usage?.model
    if (id) await update($, model, () => prettyModel(id))
    return next(e)
  })

  on('command.run', { command: 'billboard' }, async ($, e) => {
    const [sub, value] = e.args.trim().split(/\s+/)
    const names = Object.keys(THEMES)

    if (sub === 'theme' && value) {
      if (!THEMES[value]) return { text: `No theme "${value}". Try: ${names.join(', ')}` }
      await update($, theme, () => value)
      await $.store.set('theme', value)
      await share($, { theme: value })
      return { text: `Billboard theme: ${THEMES[value]!.label}` }
    }
    if (sub === 'bars' && (value === 'thin' || value === 'block')) {
      await update($, glyph, () => value)
      await $.store.set('glyph', value)
      await share($, { glyph: value })
      return { text: `Billboard bars: ${value}` }
    }

    if (sub === 'show') {
      const k = LIMITS.find(l => l === value)
      const level = parseLevel(e.args.trim().split(/\s+/)[2])
      if (!k || level === null) {
        return { text: 'Try: /billboard show 5h 75, or show 7d always, or show 7d off' }
      }
      const shared = await readShared($)
      const { [k]: _cleared, ...snooze } = shared.snooze ?? {}
      await share($, { showAt: { ...shared.showAt, [k]: level }, snooze })
      await syncGate($)
      return { text: `${k} shows at ${levelLabel(level)}` }
    }
    if (sub === 'hide') {
      const g = await syncGate($)
      const shared = await readShared($)
      const holding = snoozable(g, readings(shared.fiveHour, shared.sevenDay, await $.clock.now()))
      if (holding.length === 0) return { text: 'Nothing to hide: no limit is holding it up.' }
      await share($, { snooze: { ...g.snooze, ...Object.fromEntries(holding) } })
      await syncGate($)
      const parts = holding.map(([k, n]) => (n > 100 ? `${k} resets` : `${k} hits ${n}%`))
      return { text: `Hidden until ${parts.join(' or ')}` }
    }

    const current = await read($, theme)
    const g = await read($, gate)
    const list = names
      .map(n => `${n === current ? '●' : '○'} ${n.padEnd(7)} ${THEMES[n]!.label}`)
      .join('\n')
    return {
      text:
        `Themes (current: ${current})\n${list}\n\n` +
        `Shows at 5h ${levelLabel(lineOf(g, '5h'))} · 7d ${levelLabel(lineOf(g, '7d'))}\n\n` +
        `/billboard theme <name>   switch theme\n` +
        `/billboard bars thin|block   bar style\n` +
        `/billboard show 5h|7d <percent|always|off>   when a limit shows\n` +
        `/billboard hide   hide until the next step or the reset`,
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const snap = await read($, snapshot)
    if (!snap) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const th = themeOf(await read($, theme))
    const cell = (await read($, glyph)) === 'block' ? '■' : '━'
    const ticked = await read($, now)
    const t = ticked || (await $.clock.now())
    const modelName = await read($, model)

    const cols = e.props.bodyColumns
    const width = cols >= 140 ? 18 : cols >= 110 ? 12 : 8
    const showContext = cols >= 70
    const showTokens = cols >= 110

    // Fades toward the theme's track color instead of a terminal dim, so a dimmed
    // limit keeps its hue on every surface, like the HUD's 40% row.
    const fade = (c: string, dim: boolean) => (dim ? mix(c, th.track, 0.6) : c)

    const bar = (pct: number, dim: boolean) => {
      const filled = Math.round((Math.max(0, Math.min(100, pct)) / 100) * width)
      return Array.from({ length: width }, (_, i) => (
        <Text color={i < filled ? fade(spectrum(th, (i + 0.5) / width), dim) : th.track}>{cell}</Text>
      ))
    }

    const pct = (label: string, color: string | undefined, percent: number, dim = false) => (
      <Text>
        <Text color={fade(color ?? th.mute, dim)}>{label} </Text>
        {bar(percent, dim)}
        <Text color={fade(spectrum(th, percent / 100), dim)} weight={dim ? 'regular' : 'bold'} tabular>
          {' '}
          {Math.round(percent)}%
        </Text>
      </Text>
    )

    const segment = (label: LimitKey, lim: Limit, dim: boolean) => {
      const left = lim.resetsAt ? Date.parse(lim.resetsAt) - t : NaN
      return (
        <Text>
          {pct(label, undefined, lim.percent, dim)}
          {Number.isFinite(left) && (
            <Text color={fade(th.mute, dim)} tabular>
              {' '}⏰{fmtDuration(left)}
            </Text>
          )}
        </Text>
      )
    }

    const sep = <Text color={th.track}> │ </Text>
    const parts = []
    const fiveHour = snap.fiveHour && live(snap.fiveHour, t)
    const sevenDay = snap.sevenDay && live(snap.sevenDay, t)
    // Same rule as the HUD: nothing until a limit crosses its line, then both,
    // with the one under its line dimmed. Context and cost have no line, so they
    // always show.
    const g = await read($, gate)
    const r: Readings = { '5h': fiveHour?.percent, '7d': sevenDay?.percent }
    if (isRaised(g, r)) {
      if (fiveHour) parts.push(segment('5h', fiveHour, !isPast(g, '5h', r)))
      if (sevenDay) parts.push(segment('7d', sevenDay, !isPast(g, '7d', r)))
    }
    // Past 100% on either window, Max keeps going on usage credits. That's money,
    // so it shows even when the limit is snoozed or off.
    if ([fiveHour, sevenDay].some(l => l && l.percent >= 100)) {
      parts.push(
        <Text color={th.hot} weight="bold">
          ⚡ using credits
        </Text>,
      )
    }
    if (showContext && (modelName || snap.contextTokens !== undefined)) {
      parts.push(
        <Text>
          {pct(modelName ?? 'ctx', th.accent, snap.contextPercent ?? 0)}
          {showTokens && snap.contextTokens !== undefined && (
            <Text color={th.mute} tabular>
              {' '}
              {fmtTokens(snap.contextTokens)}/{fmtTokens(snap.contextWindow)}
            </Text>
          )}
        </Text>,
      )
    }
    if (showContext && snap.costUsd !== undefined) {
      parts.push(
        <Text color={th.mute} tabular>
          ${snap.costUsd.toFixed(2)}
        </Text>,
      )
    }
    if (parts.length === 0) return next(e)

    return (
      <Box>
        <Text wrap="truncate">
          {parts.flatMap((p, i) => (i === 0 ? [p] : [sep, p]))}
        </Text>
      </Box>
    )
  })
}
