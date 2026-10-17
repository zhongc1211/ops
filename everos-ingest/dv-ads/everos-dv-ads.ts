// Pi user extension: mount the deepvision-ads EverOS MCP server only in deepvision-ads checkouts.
// Same wrapper as Claude Code (~/.local/bin/everos-mcp-dv-ads: keyword search, key read from
// ~/.config/everos/dv-ads.env, scope deepvision/deepvision-ads/coding-deepvision-ads). Nothing secret here.
// Read-only tools are declared directly; write tools stay hidden (closing write-back is off for now).
import { realpathSync } from "node:fs";
import { homedir } from "node:os";

const ROOTS = [`${homedir()}/orca/workspaces/deepvision-ads`, "/workspace/repos/deepvision-ads"];

function inDvAds(cwd: string): boolean {
  let p = cwd;
  try { p = realpathSync(cwd); } catch {}
  return ROOTS.some((r) => p === r || p.startsWith(r + "/"));
}

export default function (pi: any) {
  if (!inDvAds(process.cwd())) return;
  pi.registerMcpServer("everos", {
    command: `${homedir()}/.local/bin/everos-mcp-dv-ads`,
    args: [],
    description: "deepvision-ads lessons and past sessions in EverOS (recall before you start work)",
    exposure: "hidden",
    toolExposure: {
      recall_agent_experience: "direct",
      search_memory: "direct",
      list_memories: "direct",
    },
    timeout: 90,
  });
}
