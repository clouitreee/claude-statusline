/** @jsxImportSource @opentui/solid */
import type { TuiPlugin, TuiPluginApi, TuiPluginModule } from "@opencode-ai/plugin/tui"
import { createMemo, createSignal, onCleanup } from "solid-js"

type AssistantMessage = {
  role: "assistant"
  providerID: string
  modelID: string
  mode: string
  tokens: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
}

type Segment = {
  text: string
  tone: "primary" | "neutral" | "success" | "warning" | "error" | "accent"
}

const env = (globalThis as typeof globalThis & {
  process?: { env?: Record<string, string | undefined> }
}).process?.env ?? {}

function clean(value: unknown, limit = 24): string {
  return String(value ?? "")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
    .trim()
    .slice(0, limit)
}

function modelShort(value: string): string {
  const model = clean(value, 32)
  if (/opus/i.test(model)) return "OPS"
  if (/sonnet/i.test(model)) return "SNT"
  if (/haiku/i.test(model)) return "HKU"
  return model.replace(/^claude[- ]/i, "").slice(0, 14) || "READY"
}

function hostAlias(): string {
  const hostname = clean(env.HOSTNAME ?? env.HOST, 64)
  const mappings = (env.STATUSLINE_HOST_MAP ?? "").split(/\s+/)
  for (const mapping of mappings) {
    const separator = mapping.indexOf("=")
    if (separator < 1) continue
    if (mapping.slice(0, separator) === hostname) return clean(mapping.slice(separator + 1), 12).toUpperCase()
  }
  return "LOCAL"
}

function activeSession(api: TuiPluginApi): string | undefined {
  const route = api.route.current
  if (route.name !== "session" || !route.params) return undefined
  const sessionID = route.params.sessionID
  return typeof sessionID === "string" ? sessionID : undefined
}

function lastAssistant(api: TuiPluginApi, sessionID: string | undefined): AssistantMessage | undefined {
  if (!sessionID) return undefined
  const messages = api.state.session.messages(sessionID)
  for (let index = messages.length - 1; index >= 0; index -= 1) {
    const message = messages[index] as Partial<AssistantMessage>
    if (message.role === "assistant" && message.modelID && message.providerID && message.tokens) {
      return message as AssistantMessage
    }
  }
  return undefined
}

function contextRemaining(api: TuiPluginApi, message: AssistantMessage | undefined): number | undefined {
  if (!message) return undefined
  const provider = api.state.provider.find((item) => item.id === message.providerID)
  const limit = provider?.models[message.modelID]?.limit.context
  if (!limit) return undefined
  const tokens = message.tokens
  const used = tokens.input + tokens.output + tokens.reasoning + tokens.cache.read + tokens.cache.write
  return Math.max(0, Math.min(100, Math.round(100 - (used / limit) * 100)))
}

function effortShort(mode: string | undefined): string | undefined {
  if (!mode) return undefined
  const value = clean(mode, 8).toUpperCase()
  const known: Record<string, string> = { LOW: "L", MEDIUM: "M", HIGH: "H", XHIGH: "XH", MAX: "MAX" }
  return known[value] ?? value.slice(0, 3)
}

function Statusline(props: { api: TuiPluginApi }) {
  const [clock, setClock] = createSignal(new Date())
  const interval = setInterval(() => setClock(new Date()), 30_000)
  onCleanup(() => clearInterval(interval))

  const mode = clean(env.AGENT_STATUSLINE_MODE ?? env.OPENCODE_STATUSLINE_MODE ?? "ops", 8).toLowerCase()
  const sessionID = createMemo(() => activeSession(props.api))
  const assistant = createMemo(() => lastAssistant(props.api, sessionID()))
  const session = createMemo(() => {
    const id = sessionID()
    return id ? props.api.state.session.get(id) : undefined
  })
  const segments = createMemo<Segment[]>(() => {
    const message = assistant()
    const provider = message ? props.api.state.provider.find((item) => item.id === message.providerID) : undefined
    const model = message ? provider?.models[message.modelID]?.name ?? message.modelID : "READY"
    const branch = clean(props.api.state.vcs?.branch, 12)
    const dirty = sessionID() ? props.api.state.session.diff(sessionID()!).length > 0 : false
    const remaining = contextRemaining(props.api, message)
    const effort = effortShort(message?.mode)
    const list: Segment[] = [
      { text: `OPENCODE:${modelShort(model)}`, tone: "primary" },
      { text: hostAlias(), tone: "neutral" },
      { text: branch ? `${branch}${dirty ? "*" : ""}` : "no-git", tone: branch ? (dirty ? "warning" : "success") : "neutral" },
    ]
    if (remaining !== undefined) {
      list.push({
        text: `CTX→${remaining}%`,
        tone: remaining >= 25 ? "success" : remaining >= 10 ? "warning" : "error",
      })
    }
    if (effort) list.push({ text: `EFF:${effort}`, tone: effort === "L" || effort === "M" ? "success" : "accent" })
    if (mode === "ops" || mode === "debug") {
      list.push({ text: clock().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }), tone: "neutral" })
    }
    if (mode === "debug") {
      const directory = clean(session()?.directory ?? props.api.state.path.directory, 24)
      if (directory) list.push({ text: directory.split("/").filter(Boolean).slice(-2).join("/"), tone: "neutral" })
    }
    return list
  })

  const colors = () => {
    const theme = props.api.theme.current
    return {
      primary: theme.primary,
      neutral: theme.backgroundElement,
      success: theme.success,
      warning: theme.warning,
      error: theme.error,
      accent: theme.accent,
      foreground: theme.selectedListItemText,
      neutralForeground: theme.text,
    }
  }

  return (
    <box width="100%" flexDirection="row" flexShrink={0}>
      {segments().map((segment) => (
        <box backgroundColor={colors()[segment.tone]} paddingLeft={1} paddingRight={1} flexShrink={0}>
          <text fg={segment.tone === "neutral" ? colors().neutralForeground : colors().foreground}>{segment.text}</text>
        </box>
      ))}
    </box>
  )
}

const tui: TuiPlugin = async (api) => {
  api.slots.register({
    order: 1_000,
    slots: {
      app_bottom() {
        return <Statusline api={api} />
      },
    },
  })
}

const plugin: TuiPluginModule & { id: string } = {
  id: "bugroo.agent-statusline",
  tui,
}

export default plugin
