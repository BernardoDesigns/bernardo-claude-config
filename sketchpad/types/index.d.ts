export type Msg = { role: 'you' | 'claude' | 'note'; text: string }

declare module 'claude-code' {
  interface PluginState {
    'sketchpad': {
      messages: Shaped<Msg[]>
      ready: string | null
      busy: boolean
      seesSession: boolean
      model: string
    }
  }
}
