// Shared palette. The floating HUD (AuroraHUD.swift) carries the same values,
// so both readouts always look like one system.

export type Theme = {
  name: string
  label: string
  ok: string // start of the bar's spectrum
  warn: string // middle
  hot: string // end
  track: string // empty cells
  mute: string // labels like "5h"
  accent: string // model + context text
}

export const THEMES: Record<string, Theme> = {
  aurora: {
    name: 'aurora',
    label: 'Aurora (green to amber to coral)',
    ok: '#8bc66b',
    warn: '#e5b454',
    hot: '#e0685c',
    track: '#4a4f5a',
    mute: '#8b8f98',
    accent: '#c99be8',
  },
  ember: {
    name: 'ember',
    label: 'Ember (sand to Claude orange to brick)',
    ok: '#e3c08d',
    warn: '#d97757',
    hot: '#b8402f',
    track: '#4d4339',
    mute: '#9a8f80',
    accent: '#e3c08d',
  },
  tide: {
    name: 'tide',
    label: 'Tide (teal to blue to violet)',
    ok: '#5fd1c3',
    warn: '#5b8def',
    hot: '#b06ae8',
    track: '#3c4656',
    mute: '#8693a6',
    accent: '#8fb8ff',
  },
  mono: {
    name: 'mono',
    label: 'Mono (quiet grays, white when hot)',
    ok: '#7a7f88',
    warn: '#b3b7be',
    hot: '#ffffff',
    track: '#3d4048',
    mute: '#7a7f88',
    accent: '#b3b7be',
  },
}

export const DEFAULT_THEME = 'aurora'

export function themeOf(name: string | undefined): Theme {
  return THEMES[name ?? ''] ?? THEMES[DEFAULT_THEME]!
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  return [
    parseInt(h.slice(0, 2), 16),
    parseInt(h.slice(2, 4), 16),
    parseInt(h.slice(4, 6), 16),
  ]
}

function rgbToHex(r: number, g: number, b: number): string {
  const c = (n: number) =>
    Math.round(Math.max(0, Math.min(255, n)))
      .toString(16)
      .padStart(2, '0')
  return `#${c(r)}${c(g)}${c(b)}`
}

function mix(a: string, b: string, t: number): string {
  const [r1, g1, b1] = hexToRgb(a)
  const [r2, g2, b2] = hexToRgb(b)
  return rgbToHex(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
}

// Position 0..1 along the spectrum ok -> warn -> hot. A cell's color is fixed
// by where it sits on the bar, so a fuller bar reaches further into the hot end.
export function spectrum(theme: Theme, t: number): string {
  const x = Math.max(0, Math.min(1, t))
  return x < 0.5 ? mix(theme.ok, theme.warn, x * 2) : mix(theme.warn, theme.hot, (x - 0.5) * 2)
}

export function fmtDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return 'now'
  const totalMin = Math.floor(ms / 60000)
  const d = Math.floor(totalMin / 1440)
  const h = Math.floor((totalMin % 1440) / 60)
  const m = totalMin % 60
  if (d > 0) return `${d}d${h}h`
  if (h > 0) return `${h}h${String(m).padStart(2, '0')}m`
  return `${m}m`
}

export function fmtTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`
  return String(n)
}

// "claude-opus-5-5" -> "Opus 5.5", "claude-sonnet-5-5-20261001" -> "Sonnet 5.5"
export function prettyModel(id: string): string {
  const m = id.match(/claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?/i)
  if (!m) return id
  const family = m[1]!.charAt(0).toUpperCase() + m[1]!.slice(1)
  return m[3] ? `${family} ${m[2]}.${m[3]}` : `${family} ${m[2]}`
}
