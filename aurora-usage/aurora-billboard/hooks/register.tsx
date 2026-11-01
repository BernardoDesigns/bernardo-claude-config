import { atom, read, update } from 'claude-code'
import type { Register, SessionRateLimit, SessionContextUsage, SessionCost } from 'claude-code'

import type { Limit, Snapshot } from '../types'
import {
  DEFAULT_THEME,
  THEMES,
  fmtDuration,
  fmtTokens,
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

// Toast once per window per threshold, so a long brainstorm gets a heads-up
// without nagging.
const THRESHOLDS = [80, 95]

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

// A window whose reset time has passed is back to zero, even if no response
// has reported the new reading yet.
function live(lim: Limit, t: number): Limit {
  const at = lim.resetsAt ? Date.parse(lim.resetsAt) : NaN
  return Number.isFinite(at) && at <= t ? { percent: 0 } : lim
}

export const register: Register = on => {
  const toasted = new Set<string>()

  on('session.start', async ($, e, next) => {
    const saved = await $.store.get('theme')
    if (typeof saved === 'string' && THEMES[saved]) await update($, theme, () => saved)
    const savedGlyph = await $.store.get('glyph')
    if (savedGlyph === 'thin' || savedGlyph === 'block') await update($, glyph, () => savedGlyph)

    await $.command.register({
      name: 'billboard',
      description: 'Usage billboard: /billboard theme <name>, /billboard bars thin|block',
    })

    const ran = await next(e)
    const u = await $.session.usage()
    await update($, snapshot, () => toSnapshot(u.rateLimits, u.context, u.cost))
    // Countdowns tick down between turns.
    $.clock.every(60_000, async () => {
      await update($, now, () => Date.now())
    })
    return ran
  })

  on('session.measure', async ($, e, next) => {
    const snap = toSnapshot(e.rateLimits, e.context, e.cost)
    await update($, snapshot, () => snap)

    for (const [label, lim] of [
      ['5-hour', snap.fiveHour],
      ['weekly', snap.sevenDay],
    ] as const) {
      if (!lim) continue
      for (const t of THRESHOLDS) {
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
      return { text: `Billboard theme: ${THEMES[value]!.label}` }
    }
    if (sub === 'bars' && (value === 'thin' || value === 'block')) {
      await update($, glyph, () => value)
      await $.store.set('glyph', value)
      return { text: `Billboard bars: ${value}` }
    }

    const current = await read($, theme)
    const list = names
      .map(n => `${n === current ? '●' : '○'} ${n.padEnd(7)} ${THEMES[n]!.label}`)
      .join('\n')
    return {
      text:
        `Themes (current: ${current})\n${list}\n\n` +
        `/billboard theme <name>   switch theme\n` +
        `/billboard bars thin|block   bar style`,
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

    const bar = (pct: number) => {
      const filled = Math.round((Math.max(0, Math.min(100, pct)) / 100) * width)
      return Array.from({ length: width }, (_, i) => (
        <Text color={i < filled ? spectrum(th, (i + 0.5) / width) : th.track}>{cell}</Text>
      ))
    }

    const pct = (label: string, color: string | undefined, percent: number) => (
      <Text>
        <Text color={color ?? th.mute}>{label} </Text>
        {bar(percent)}
        <Text color={spectrum(th, percent / 100)} weight="bold" tabular>
          {' '}
          {Math.round(percent)}%
        </Text>
      </Text>
    )

    const segment = (label: string, lim: Limit) => {
      const left = lim.resetsAt ? Date.parse(lim.resetsAt) - t : NaN
      return (
        <Text>
          {pct(label, undefined, lim.percent)}
          {Number.isFinite(left) && (
            <Text color={th.mute} tabular>
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
    if (fiveHour) parts.push(segment('5h', fiveHour))
    if (sevenDay) parts.push(segment('7d', sevenDay))
    // Past 100% on either window, Max keeps going on usage credits.
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
