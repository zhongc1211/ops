// Pi user extension (EverOS MCP wiring standard v2): ~/.pi/agent/extensions/everos.ts, same bytes on box, iMac and MBA.
// Mounts the EverOS MCP server "everos" for the project that owns the session's working directory, read-only.
// Each project's wrapper is ~/.local/bin/everos-mcp-<N> (key and scope from ~/.config/everos/<N>.env).
// Nothing secret here.
import { realpathSync } from "node:fs";
import { homedir } from "node:os";

const H = homedir();
// [root, N]: a session whose cwd is the root or below it gets project N. Roots missing on a machine never match.
const PROJECTS: ReadonlyArray<readonly [string, string]> = [
  // xinyue-site
  [`${H}/orca/workspaces/xinyue-site`, "xinyue"],
  ["/workspace/repos/xinyue-site", "xinyue"],
  [`${H}/pi/remote/xinyue-site`, "xinyue"],
  [`${H}/pi/remote/xinyue-site-cicd`, "xinyue"],
  [`${H}/pi/remote/xinyue-ci`, "xinyue"],
  [`${H}/orca/projects/xinyue-site`, "xinyue"],
  // deepvision-site
  [`${H}/orca/workspaces/deepvision-site`, "deepvision"],
  ["/workspace/repos/deepvision-site", "deepvision"],
  [`${H}/orca/workspaces/site`, "deepvision"],
  [`${H}/claude/site`, "deepvision"],
  [`${H}/orca/projects/deepvision-site`, "deepvision"],
  // deepvision-ads
  [`${H}/orca/workspaces/deepvision-ads`, "dv-ads"],
  ["/workspace/repos/deepvision-ads", "dv-ads"],
  [`${H}/orca/projects/deepvision-ads`, "dv-ads"],
  // vllm-omni
  [`${H}/orca/workspaces/vllm-omni`, "vllm-omni"],
  ["/workspace/repos/vllm-omni", "vllm-omni"],
  [`${H}/orca/workspaces/repository`, "vllm-omni"],
  [`${H}/orca/projects/vllm-omni`, "vllm-omni"],
];

function real(p: string): string {
  try { return realpathSync(p); } catch { return p; }
}

function projectOf(cwd: string): string | undefined {
  const p = real(cwd);
  for (const [root, n] of PROJECTS) {
    const r = real(root);
    if (p === r || p.startsWith(r + "/")) return n;
  }
  return undefined;
}

function server(n: string) {
  return {
    command: `${H}/.local/bin/everos-mcp-${n}`,
    args: [],
    description: `EverOS lessons for ${n}: recall before starting work`,
    exposure: "hidden",
    toolExposure: { recall_agent_experience: "direct", search_memory: "direct", list_memories: "direct" },
    timeout: 90,
  };
}

export default function (pi: any) {
  // Background pi-subagents children run with PI_SUBAGENT_CHILD=1. Workers do not mount; the parent recalls.
  if (process.env.PI_SUBAGENT_CHILD === "1") return;
  // A normal start runs in the session's directory: register at load, so the server connects with the
  // session and its tools are declared in the first request.
  let mounted = projectOf(process.cwd());
  if (mounted) pi.registerMcpServer("everos", server(mounted));
  // --session, --resume, /resume and fork can open a session from another directory (pi never chdirs).
  // ctx.cwd is the session's directory: follow it.
  pi.on("session_start", (_event: unknown, ctx: { cwd: string }) => {
    const want = projectOf(ctx.cwd);
    if (want === mounted) return;
    if (mounted) pi.unregisterMcpServer("everos");
    if (want) pi.registerMcpServer("everos", server(want));
    mounted = want;
  });
}
