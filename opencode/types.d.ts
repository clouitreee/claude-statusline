declare module "solid-js" {
  export function createMemo<Value>(fn: () => Value): () => Value
  export function createSignal<Value>(value: Value): [() => Value, (value: Value) => void]
  export function onCleanup(fn: () => void): void
}

declare module "@opentui/solid/jsx-runtime" {
  export namespace JSX {
    type Element = unknown
    interface IntrinsicElements {
      box: Record<string, unknown>
      text: Record<string, unknown>
    }
  }
  export function jsx(type: unknown, props: unknown): JSX.Element
  export function jsxs(type: unknown, props: unknown): JSX.Element
  export const Fragment: unknown
}

declare module "@opencode-ai/plugin/tui" {
  type Color = unknown

  export type TuiPluginApi = {
    route: {
      readonly current:
        | { name: "home" }
        | { name: "session"; params: { sessionID: string } }
        | { name: string; params?: Record<string, unknown> }
    }
    state: {
      readonly path: { directory: string }
      readonly vcs: { branch?: string } | undefined
      readonly provider: ReadonlyArray<{
        id: string
        models: Record<string, { name: string; limit: { context: number } }>
      }>
      session: {
        get(id: string): { directory?: string } | undefined
        diff(id: string): ReadonlyArray<unknown>
        messages(id: string): ReadonlyArray<unknown>
      }
    }
    theme: {
      readonly current: {
        primary: Color
        accent: Color
        success: Color
        warning: Color
        error: Color
        text: Color
        selectedListItemText: Color
        backgroundElement: Color
      }
    }
    slots: {
      register(plugin: {
        order?: number
        slots: { app_bottom?: () => unknown }
      }): string
    }
  }

  export type TuiPlugin = (api: TuiPluginApi, options: unknown, meta: unknown) => Promise<void>
  export type TuiPluginModule = { id?: string; tui: TuiPlugin; server?: never }
}
