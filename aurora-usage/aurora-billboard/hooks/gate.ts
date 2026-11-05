// When the plan limits show. Same rules as the Gate enum in the HUD's main.swift:
// a low-fuel light per limit, off until the limit crosses its own line. Both read
// the lines and snoozes from the shared file, so they always agree.

import type { Gate, LimitKey } from '../types'

export const LIMITS: readonly LimitKey[] = ['5h', '7d']
export const DEFAULT_SHOW_AT: Record<LimitKey, number> = { '5h': 75, '7d': 90 }
export const STEPS = [90, 95]
export const OFF = 101 // a line no reading can reach
export const UNTIL_RESET = 101 // above any real percent

export type Readings = Partial<Record<LimitKey, number>>

export function lineOf(g: Gate, k: LimitKey): number {
  return g.showAt[k] ?? DEFAULT_SHOW_AT[k]
}

export function decide(
  peak: number | undefined,
  showAt: number,
  snoozedUntil: number | undefined,
): { show: boolean; snooze?: number } {
  if (showAt <= 0) return { show: true } // "always"
  if (peak === undefined) return { show: false, snooze: snoozedUntil } // no reading yet
  if (peak < showAt) return { show: false } // under the line: clears any snooze
  if (snoozedUntil !== undefined && peak < snoozedUntil) return { show: false, snooze: snoozedUntil }
  return { show: true }
}

export function isRaised(g: Gate, r: Readings): boolean {
  return LIMITS.some(k => decide(r[k], lineOf(g, k), g.snooze[k]).show)
}

// Past its own line or set to "always". Limits that aren't are drawn dimmed, so
// a glance shows which one raised the readout.
export function isPast(g: Gate, k: LimitKey, r: Readings): boolean {
  const line = lineOf(g, k)
  return line <= 0 || (r[k] ?? 0) >= line
}

export function nextStep(peak: number, showAt: number): number {
  return STEPS.find(s => s > peak && s > showAt) ?? UNTIL_RESET
}

// The limits holding the readout up, each with the level its snooze would wait for.
export function snoozable(g: Gate, r: Readings): [LimitKey, number][] {
  return LIMITS.flatMap((k): [LimitKey, number][] => {
    const line = lineOf(g, k)
    const reading = r[k]
    if (line <= 0 || line >= OFF || g.snooze[k] !== undefined) return []
    if (reading === undefined || reading < line) return []
    return [[k, nextStep(reading, line)]]
  })
}

export function levelLabel(v: number): string {
  return v <= 0 ? 'always' : v >= OFF ? 'off' : `${v}%`
}

export function parseLevel(s: string | undefined): number | null {
  if (s === 'always') return 0
  if (s === 'off') return OFF
  const n = Number((s ?? '').replace(/%$/, ''))
  return s && Number.isFinite(n) && n >= 0 && n <= 100 ? n : null
}

// Heads-up toasts: when a limit crosses its line, and again at 95.
export function toastLevels(line: number): number[] {
  if (line <= 0 || line >= OFF) return []
  return line >= 95 ? [line] : [line, 95]
}
