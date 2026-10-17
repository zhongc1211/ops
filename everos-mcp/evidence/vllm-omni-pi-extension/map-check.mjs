// Non-destructive load + mapping check for ~/.pi/agent/extensions/everos.ts: imports the real file (node type stripping),
// hands it a fake `pi` that only records registerMcpServer/unregisterMcpServer, then replays session_start for each cwd.
// Starts no MCP server, calls no model, writes nothing.
import { homedir } from "node:os";
import { pathToFileURL } from "node:url";
import { copyFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
const H = homedir();
const src = `${H}/.pi/agent/extensions/everos.ts`;
const tmp = mkdtempSync(`${tmpdir()}/everos-map-`) + "/everos.mts"; copyFileSync(src, tmp); // .mts => ESM for node
const mod = await import(pathToFileURL(tmp).href);
let handler, mounted = null; const log = [];
const pi = {
  registerMcpServer: (name, cfg) => { mounted = cfg; log.push(["register", name, cfg.command]); },
  unregisterMcpServer: (name) => { mounted = null; log.push(["unregister", name]); },
  on: (ev, fn) => { if (ev === "session_start") handler = fn; },
};
process.chdir("/");                       // load-time cwd matches nothing
mod.default(pi);
console.log("loaded OK; load-time registration at cwd=/ :", log.length ? JSON.stringify(log) : "none");
const cases = [
  // [cwd, expected N or null]
  [`${H}/orca/workspaces/vllm-omni`, "vllm-omni"],
  [`${H}/orca/workspaces/vllm-omni/vllm-FDV-1-some-task/src`, "vllm-omni"],
  ["/workspace/repos/vllm-omni", "vllm-omni"],
  ["/workspace/repos/vllm-omni/tests", "vllm-omni"],
  [`${H}/orca/workspaces/repository`, "vllm-omni"],
  [`${H}/orca/workspaces/repository/wt-1`, "vllm-omni"],
  [`${H}/orca/workspaces/vllm-omni-other`, null],
  [`${H}/orca/workspaces/repository2`, null],
  [`${H}/pi/remote/vllm-omni`, null],          // D2: not mounted
  [`${H}/claude/gpu/vllm-omni`, null],         // D2: not mounted
  [`${H}/orca/workspaces/xinyue-site/x`, "xinyue"],
  ["/workspace/repos/xinyue-site", "xinyue"],
  [`${H}/pi/remote/xinyue-site`, "xinyue"],
  [`${H}/pi/remote/xinyue-site-cicd`, "xinyue"],
  [`${H}/pi/remote/xinyue-ci`, "xinyue"],
  [`${H}/orca/workspaces/deepvision-site/a`, "deepvision"],
  ["/workspace/repos/deepvision-site", "deepvision"],
  [`${H}/orca/workspaces/site`, "deepvision"],
  [`${H}/claude/site`, "deepvision"],
  [`${H}/orca/workspaces/deepvision-ads/b`, "dv-ads"],
  ["/workspace/repos/deepvision-ads", "dv-ads"],
  ["/workspace/ops", null],
  [H, null],
];
let fail = 0;
for (const [cwd, want] of cases) {
  handler({}, { cwd });
  const got = mounted ? mounted.command.replace(`${H}/.local/bin/everos-mcp-`, "") : null;
  const ok = got === want; if (!ok) fail++;
  const extra = mounted ? ` exposure=${mounted.exposure} direct=${Object.keys(mounted.toolExposure).join(",")}` : "";
  console.log(`${ok ? "ok  " : "FAIL"} ${cwd.replace(H, "~")} -> ${got ?? "(none)"}${extra}`);
}
process.env.PI_SUBAGENT_CHILD = "1"; const log2 = []; process.chdir("/");
mod.default({ registerMcpServer: () => log2.push("r"), unregisterMcpServer: () => {}, on: () => log2.push("on") });
console.log(`PI_SUBAGENT_CHILD=1: registrations=${log2.length} (expect 0)`);
console.log(fail ? `RESULT FAIL (${fail})` : "RESULT PASS"); process.exit(fail ? 1 : 0);
