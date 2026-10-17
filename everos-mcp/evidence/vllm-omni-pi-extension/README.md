# vllm-omni rows in the pi extension `everos.ts` (box + iMac) — 2026-10-17 17:38–17:45 SGT, eggbot

Approval: Zack 16:56 SGT 「批，按 v2 推进」 (MCP standard v2). Request from Coding助手: the pi table had no vllm-omni rows.

## Change
- Files: box `/home/box/.pi/agent/extensions/everos.ts`, iMac `/Users/jiawenwang/.pi/agent/extensions/everos.ts`.
- Before: both sha256 `e166098f0c0cdbfcc36272ff2b19dc9b901d46b83e8fff3929c1ab509679354d` (checked before editing).
- Added exactly the §5.1 block after the deepvision-ads rows (comment line + 3 rows), nothing else (`box-edit.diff`, same diff on the iMac):
  ```
    // vllm-omni
    [`${H}/orca/workspaces/vllm-omni`, "vllm-omni"],
    ["/workspace/repos/vllm-omni", "vllm-omni"],
    [`${H}/orca/workspaces/repository`, "vllm-omni"],
  ```
- After: both sha256 `743e3d27d88e7d77f3a52fac4371dbd13b95091baad84772e86453f7516214fd`; box == iMac byte-identical (`cmp`), and identical to
  `EV/everos.ts` and to the §5.1 code block. The standard already records 743e3d27 (§5.1 line "目前在 box 上测过的版本", §5.2 `应为 743e3d27…`),
  so **the standard was not edited** (no backup needed).
- Backups (outside `extensions/` on purpose, so pi never loads them and G4 sees no stray file):
  box `/home/box/.pi/agent/everos.ts.bak-20261017-173827`, iMac `/Users/jiawenwang/.pi/agent/everos.ts.bak-20261017-173849` (both e166098f).
  Copies here: `box-everos.ts.before`, `box-everos.ts.after`, `imac-everos.ts.after`.
- Rollback: `install -m 644 ~/.pi/agent/everos.ts.bak-<ts> ~/.pi/agent/extensions/everos.ts` on each machine; open pi sessions need `/reload`.
- Env IDs (non-secret lines, both machines, mode 600): app vllm-omni / project vllm-omni / sender = agent coding-vllm-omni / user zack, BASE_URL public.
- Not touched: launchers (both machines already had `everos-mcp-vllm-omni` = v2.1 f543542d, installed by someone else 17:25 box / 17:27 iMac), env files, EverOS.

## Verification
| Check | box | iMac |
|---|---|---|
| Mapping: real file loaded with node type stripping + fake `pi` (`map-check.mjs`), 23 cwds | PASS 23/23 (`box-map-check.txt`) | PASS 23/23 (`imac-map-check.txt`) |
| vllm-omni roots + subdirs → `everos-mcp-vllm-omni`, hidden, direct = 3 read tools | ok | ok |
| `vllm-omni-other`, `repository2`, D2 clones (`~/pi/remote/vllm-omni`, `~/claude/gpu/vllm-omni`), ops, ~ → none | ok | ok |
| xinyue / deepvision / dv-ads rows unchanged (all 11 roots → same N) | ok | ok |
| `PI_SUBAGENT_CHILD=1` → no registration | ok | ok |
| pi 1.0.4 real load, rpc mode, `/mcp` in a vllm-omni worktree | `everos: connected, 3 tools (hidden)`, stderr empty, 0 messages (`box-pi-load.txt`) | same (`imac-pi-load.txt`) |
| pi in an unmapped cwd (ops) | No MCP servers configured | same |
| G4 (sha, no `everos-*.ts`, no everos in mcp.json) | pass | pass |
No model was called (messageCount 0); MCP connect only did initialize/tools/list.

Note: iMac `~/orca/workspaces/vllm` is upstream vllm-project/vllm, not vllm-omni, so it is correctly unmapped.
Older RESULT.md files that mention e166098f (`../box-pi/RESULT.md`, `../imac-pi/RESULT.md`, deepvision ones) were left as historical records.
