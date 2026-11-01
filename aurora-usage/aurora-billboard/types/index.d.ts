export type Limit = { percent: number; resetsAt?: string }

export type Snapshot = {
  fiveHour: Limit | null
  sevenDay: Limit | null
  contextTokens?: number
  contextWindow: number
  contextPercent?: number
  costUsd?: number
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
