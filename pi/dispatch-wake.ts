// dispatch-wake.ts: Pi extension that wakes the dispatching bot when a dispatched Pi session stops.
// Install: ~/.pi/agent/extensions/dispatch-wake.ts (no "orca-" prefix, so Orca's updates leave it alone).
//
// Only active when the Pi process was started by `notify-run --tty` (ORCA_DISPATCH_BOT is set) and runs
// in TUI mode. Background subagent runners (PI_SUBAGENT_CHILD=1) and rpc/json/print modes are skipped.
// The parent-process check, mute file, dedup and the webhook itself live in `orca-wake send`.
//
//   agent_settled          -> idle (or error when agent_before_settle reported outcome "error"),
//                             unless background subagents are still running; then wait for them.
//   ui_prompt_start + 6 s  -> needs_input (cancelled by ui_prompt_end)
//
// Dedup seq is the session leaf entry id at the time of the pause, so a resumed session never reuses
// an old key.
import { spawn } from "node:child_process"
import * as os from "node:os"
import * as path from "node:path"

const NEEDS_INPUT_DELAY_MS = 6000
// After the last background subagent finishes, pi-subagents usually starts a follow-up turn.
// Give it this long to start before reporting the earlier pause ourselves.
const CHILD_DRAIN_GRACE_MS = 10000

type Ctx = {
  mode?: string
  cwd?: string
  sessionManager?: {
    getSessionId?: () => string
    getSessionFile?: () => string | undefined
    getLeafId?: () => string | null | undefined
    getBranch?: () => unknown[]
    getHeader?: () => { parentSession?: unknown } | null
  }
}

export default function (pi): void {
  if (!process.env.ORCA_DISPATCH_BOT) return
  if (process.env.PI_SUBAGENT_CHILD === "1") return
  const wakeBin = process.env.ORCA_WAKE_BIN || path.join(os.homedir(), ".local/bin/orca-wake")

  const running = new Set<string>() // background subagent run ids
  let lastOutcome: string | undefined
  let pendingIdle: { ctx: Ctx; seq: string } | null = null
  let drainTimer: ReturnType<typeof setTimeout> | null = null
  let promptTimer: ReturnType<typeof setTimeout> | null = null
  let promptDepth = 0

  function eligible(ctx: Ctx | undefined): boolean {
    if (!ctx || ctx.mode !== "tui") return false
    const header = ctx.sessionManager?.getHeader?.()
    if (header && typeof header.parentSession === "string") return false
    return true
  }

  function sessionId(ctx: Ctx): string {
    try {
      return String(ctx.sessionManager?.getSessionId?.() || "unknown")
    } catch {
      return "unknown"
    }
  }

  function leafSeq(ctx: Ctx): string {
    try {
      const id = ctx.sessionManager?.getLeafId?.()
      if (id) return String(id)
    } catch {}
    return "t" + Date.now()
  }

  function lastAssistantText(ctx: Ctx): string {
    try {
      const branch = ctx.sessionManager?.getBranch?.() || []
      for (let i = branch.length - 1; i >= 0; i--) {
        const e = branch[i] as { type?: string; message?: { role?: string; content?: unknown } }
        if (e?.type !== "message" || e.message?.role !== "assistant") continue
        const c = e.message.content
        if (typeof c === "string") return c
        if (Array.isArray(c)) {
          const text = c
            .filter((p) => p && typeof p === "object" && (p as { type?: string }).type === "text")
            .map((p) => String((p as { text?: unknown }).text ?? ""))
            .join("\n")
          if (text) return text
        }
      }
    } catch {}
    return ""
  }

  function send(ctx: Ctx, status: string, seq: string, text: string, note = ""): void {
    const args = ["send", "--agent", "pi", "--status", status, "--session", sessionId(ctx), "--seq", seq,
      "--agent-pid", String(process.pid)]
    if (ctx.cwd) args.push("--cwd", ctx.cwd)
    try {
      const file = ctx.sessionManager?.getSessionFile?.()
      if (file) args.push("--transcript", file)
    } catch {}
    if (note) args.push("--note", note)
    try {
      const child = spawn(wakeBin, args, { detached: true, stdio: ["pipe", "ignore", "ignore"], env: process.env })
      child.on("error", () => {})
      child.stdin?.on("error", () => {})
      child.stdin?.end(text.slice(-8000))
      child.unref()
    } catch {}
  }

  function clearDrain(): void {
    if (drainTimer) clearTimeout(drainTimer)
    drainTimer = null
  }

  function clearPrompt(): void {
    if (promptTimer) clearTimeout(promptTimer)
    promptTimer = null
  }

  function runId(event: unknown): string {
    if (!event || typeof event !== "object") return ""
    const r = event as { id?: unknown; runId?: unknown }
    if (typeof r.id === "string" && r.id) return r.id
    if (typeof r.runId === "string" && r.runId) return r.runId
    return ""
  }

  const bus = (pi as { events?: { on?: (name: string, h: (e: unknown) => void) => void } }).events
  bus?.on?.("subagent:async-started", (e) => {
    const id = runId(e)
    if (id) running.add(id)
  })
  bus?.on?.("subagent:async-complete", (e) => {
    const id = runId(e)
    if (id) running.delete(id)
    if (running.size > 0 || !pendingIdle) return
    clearDrain()
    const p = pendingIdle
    drainTimer = setTimeout(() => {
      drainTimer = null
      if (pendingIdle !== p) return
      pendingIdle = null
      send(p.ctx, "idle", p.seq, lastAssistantText(p.ctx), "background subagents finished")
    }, CHILD_DRAIN_GRACE_MS)
    drainTimer.unref?.()
  })

  pi.on("agent_start", () => {
    // A new run (user input, or the follow-up turn after subagents finish) supersedes the pending pause.
    pendingIdle = null
    clearDrain()
    lastOutcome = undefined
  })

  pi.on("agent_before_settle", (event) => {
    lastOutcome = (event as { outcome?: string })?.outcome
  })

  pi.on("agent_settled", (_event, ctx: Ctx) => {
    if (!eligible(ctx)) return
    const seq = leafSeq(ctx)
    const outcome = lastOutcome
    lastOutcome = undefined
    if (outcome === "error") {
      send(ctx, "error", seq, lastAssistantText(ctx), "agent_before_settle outcome=error")
      return
    }
    if (running.size > 0) {
      pendingIdle = { ctx, seq }
      return
    }
    send(ctx, "idle", seq, lastAssistantText(ctx), outcome === "aborted" ? "run aborted" : "")
  })

  pi.on("ui_prompt_start", (event, ctx: Ctx) => {
    if (!eligible(ctx)) return
    promptDepth++
    if (promptDepth > 1) return
    clearPrompt()
    const ev = event as { kind?: string; title?: string }
    const seq = leafSeq(ctx) + ".p" + Date.now()
    promptTimer = setTimeout(() => {
      promptTimer = null
      send(ctx, "needs_input", seq, ev?.title || "(dialog without title)", "ui_prompt " + (ev?.kind || ""))
    }, NEEDS_INPUT_DELAY_MS)
    promptTimer.unref?.()
  })

  pi.on("ui_prompt_end", () => {
    if (promptDepth > 0) promptDepth--
    if (promptDepth === 0) clearPrompt()
  })

  pi.on("session_shutdown", () => {
    clearPrompt()
    clearDrain()
    pendingIdle = null
  })
}
