// Offline test for pi/dispatch-wake.ts: fake Pi event bus, fake orca-wake that records its arguments.
// No Pi, no webhook. Needs Node 22.6+ (type stripping).
//
//   node --experimental-strip-types tests/pi-ext.test.mjs
import { spawnSync } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-ext-"))
const calls = path.join(tmp, "calls.log")
const bin = path.join(tmp, "orca-wake")
fs.writeFileSync(bin, `#!/bin/sh\nprintf '%s\\n' "$*" >> "${calls}"\ncat > /dev/null\n`, { mode: 0o755 })
fs.copyFileSync(path.join(here, "../pi/dispatch-wake.ts"), path.join(tmp, "dispatch-wake.mts"))

Object.assign(process.env, {
  ORCA_DISPATCH_BOT: "unit-bot",
  ORCA_WAKE_BIN: bin,
  ORCA_WAKE_PI_EXIT_GRACE_S: "1",
  ORCA_WAKE_PI_MAX_WAIT_S: "3",
})
delete process.env.PI_SUBAGENT_CHILD
const ext = (await import(path.join(tmp, "dispatch-wake.mts"))).default

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
let leaf = 0
function session(name) {
  const h = {}
  const ev = {}
  ext({ on: (n, f) => (h[n] = f), events: { on: (n, f) => (ev[n] = f) } })
  const ctx = {
    mode: "tui",
    cwd: tmp,
    sessionManager: {
      getSessionId: () => name,
      getLeafId: () => "leaf" + leaf,
      getBranch: () => [{ type: "message", message: { role: "assistant", content: "reply " + leaf } }],
      getHeader: () => null,
    },
  }
  return {
    turn() {
      leaf++
      h.agent_start?.({}, ctx)
      h.agent_before_settle?.({ outcome: "completed" }, ctx)
      h.agent_settled?.({}, ctx)
    },
    start: () => h.agent_start?.({}, ctx),
    bus: (n, e) => ev[n]?.(e),
  }
}
function sent(name) {
  try {
    return fs.readFileSync(calls, "utf8").split("\n").filter((l) => l.includes("--session " + name + " "))
  } catch {
    return []
  }
}

let pass = 0
let fail = 0
function check(label, cond, extra = "") {
  if (cond) pass++
  else fail++
  console.log((cond ? "ok   " : "FAIL ") + label + (cond ? "" : "  " + extra))
}

// 1. Runner exits without a result: wake after exit grace + drain grace, note says so.
const a = session("crash")
a.bus("subagent:async-started", { id: "r1" })
a.turn()
check("crash: no wake while the run is active", sent("crash").length === 0)
a.bus("subagent:process-terminal", { runId: "r1", state: "observed" })
// 2. Normal finish: runner exits, async-complete follows within the grace, follow-up turn starts.
const b = session("normal")
b.bus("subagent:async-started", { id: "r2" })
b.turn()
b.bus("subagent:process-terminal", { runId: "r2", state: "observed" })
await sleep(300)
b.bus("subagent:async-complete", { runId: "r2" })
await sleep(500)
b.turn() // the follow-up turn pi-subagents starts after delivering the result
// 3. Run never ends: wake when the cap expires.
const c = session("cap")
c.bus("subagent:async-started", { id: "r3" })
c.turn()
// 4. process-terminal for an unknown run is ignored.
const d = session("unknown")
d.bus("subagent:process-terminal", { runId: "zzz" })
d.turn()

await sleep(1000)
check("unknown run id: plain idle wake right away", sent("unknown").length === 1, sent("unknown").join(" | "))
check("normal: one wake for the follow-up turn", sent("normal").length === 1, sent("normal").join(" | "))
await sleep(3000)
check("cap: one wake after the cap", sent("cap").length === 1 && /still running after/.test(sent("cap")[0]),
  sent("cap").join(" | "))
await sleep(8500)
const cr = sent("crash")
check("crash: one wake after exit grace + drain", cr.length === 1 && /exited without a result: r1/.test(cr[0]),
  cr.join(" | "))
check("normal: still one wake (no crash wake)", sent("normal").length === 1, sent("normal").join(" | "))
check("cap: still one wake", sent("cap").length === 1)

fs.rmSync(tmp, { recursive: true, force: true })
console.log(`${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
