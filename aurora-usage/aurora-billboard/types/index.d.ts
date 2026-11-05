export type Limit = { percent: number; resetsAt?: string }

export type Snapshot = {
  fiveHour: Limit | null
  sevenDay: Limit | null
  contextTokens?: number
  contextWindow: number
  contextPercent?: number
  costUsd?: number
}

export type LimitKey = '5h' | '7d'

// The lines and snoozes, as they sit in the shared file. A missing line means
// the default, a missing snooze means not snoozed.
export type Gate = {
  showAt: Partial<Record<LimitKey, number>>
  snooze: Partial<Record<LimitKey, number>>
}

// ~/.claude/aurora-usage.json, shared with the floating HUD (main.swift reads
// and writes the same keys).
export type Shared = {
  v?: 1
  updatedAt?: number
  fiveHour?: Limit | null
  sevenDay?: Limit | null
  theme?: string
  glyph?: 'thin' | 'block'
  showAt?: Gate['showAt']
  snooze?: Gate['snooze']
}

declare module 'claude-code' {
  interface PluginState {
    'aurora-billboard': {
      snapshot: Shaped<Snapshot | null>
      model: string | null
      theme: string
      glyph: 'thin' | 'block'
      now: number
      gate: Gate
    }
  }
}
