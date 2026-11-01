export type Limit = { percent: number; resetsAt?: string }

export type Snapshot = {
  fiveHour: Limit | null
  sevenDay: Limit | null
  contextTokens?: number
  contextWindow: number
  contextPercent?: number
  costUsd?: number
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
}

declare module 'claude-code' {
  interface PluginState {
    'aurora-billboard': {
      snapshot: Shaped<Snapshot | null>
      model: string | null
      theme: string
      glyph: 'thin' | 'block'
      now: number
    }
  }
}
