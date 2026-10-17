# EverOS MCP launcher v2.2 — gate + rollout (2026-10-17, eggbot)

Approval: Zack 20:04 SGT via Coding助手 (「试点没问题就推」), gated on a user-memory check (Coding助手 20:2x). Times SGT (UTC+8).
Template: `templates/everos-mcp-launcher-v2.2.sh` (copy here). Normalized sha (`sed 's/^N=.*/N=@/' | shasum -a 256`):
**`befbd0921afc36751323e70152c382f84e4d4257b01d526c597287f8aad7a3c3`**. Diffs: `template-vs-pilotA.diff`, `template-v21-vs-v22.diff`. Changelog: `templates/CHANGELOG.md` §v2.2.
EverOS server config untouched, no restart. pi extension unchanged (box + iMac `743e3d27…`). Env files unchanged.

## 1. Gate (20:28–20:30, box, before any launcher was changed) — PASS
Launchers generated from the v2.2 template into `/tmp/v22-gate/`, driven over real MCP stdio (`tools/mcp_session.py`:
initialize → tools/list → tools/call), `XDG_STATE_HOME=gate/state-box`. Files `gate/box/mcp-*.txt`, logs `gate/state-box/everos-mcp/`.
| project | call | result |
|---|---|---|
| xinyue | search_memory 「不允许用 wrangler 部署」 | 8 episodes, **24 atomic facts** in the output (e.g. 「提交的部署规则禁止使用 wrangler deploy。」) |
| xinyue | search_memory 「网站图标找不到」 (no keyword overlap) | 1 episode, 3 facts (studio /favicon.ico 404) |
| xinyue | search_memory 「tailwind」 (cross: deepvision topic) | 0 |
| xinyue | recall 「切流量 绑定」 | 2 skills |
| deepvision-site | search_memory 「tailwind」 | 0 (user track; agent track has the tailwind skill) |
| deepvision-site | search_memory 「不允许用 wrangler 部署」 (cross: xinyue's query) | 12 episodes / 33 facts, all deepvision-site (FDV-61/65); xinyue's fact texts absent (grep = 0) |
| deepvision-site | search_memory 「网站图标找不到」 (cross) | 7 / 18, all deepvision-site; 「studio 登录页」 absent |
| deepvision-site | recall 「tailwind」 | 1 skill |
| control dv-ads | search 「cf CLI」 0; 「不允许用 wrangler 部署」 1 ep / 3 facts (own scope); recall 「cf CLI」 5 skills |
| control vllm-omni | search ×2 → 0 (no user memory); recall 「NCCL」 → 1 skill |
- search.log: every call `method=hybrid enable_llm_rerank=absent outcome=ok foreign_dropped=0`; endpoint.log: all `endpoint=tailnet health=200`; stderr empty.
- Server-side isolation (`gate/box/api-xcheck.txt`, `tools/xcheck_ids.py`, same body, tailnet): 18 searches, every returned item has its own
  app/project and owner, **foreign=0**. Agent-skill hybrid without enable_llm_rerank re-run: xinyue 2, deepvision 1, dv-ads 5, vllm 1, 0.6–0.8s;
  cross agent queries (dv-site 「切流量 绑定」, vllm 「cf CLI」) → 0.
- Finding: episode id strings repeat across scopes (`zack_ep_20261017_00000001..03` exist in xinyue, deepvision-site and dv-ads as different
  sessions/subjects — `gate/box/id-overlap-detail.txt`). Not a leak; isolation must be judged on app_id/project_id, not id. Added as standard §13 #19.
- Token check: 0 (`gate/box/token-check.txt`; final check below).

## 2. Standard / changelog (20:30)
Backups: `MCP-WIRING-STANDARD-v2.md.bak-20261017-203005`, `templates/CHANGELOG.md.bak-20261017-203005`. Diff `standard.diff`:
§3.2 pointer → v2.2; §3.3 loop skips `*.bak*` and expects `befbd092…`; §3.3 bullets (current/old values, evidence, rollback); §3.4 two rows;
§12 progress note (steps 1–3, wrapper kept, no enable_llm_rerank, no vector); §13 #1 updated, #19 added.

## 3. Rollout (8/8 MATCH)
Backups in place: `~/.local/bin/everos-mcp-<n>.bak-v21-pre-v22` (cp -p, cmp ok). vllm-omni's backup is the pilot draft A (85cecc4b);
the v2.1 copy is still `everos-mcp-vllm-omni.bak-v21-pre-hybrid`.
| time | machine | n | before raw / norm | after raw | after norm | checks | MCP call (search_memory / recall, real stdio) |
|---|---|---|---|---|---|---|---|
| 20:30:56 | box | xinyue | b7966109… / f543542d (v2.1) | 447bf9f6… | befbd092 MATCH | N-ok, bash -n | 8 ep / 24 facts; 10 skills |
| 20:30:59 | box | deepvision | 0d866b74… / f543542d | 8d666531… | MATCH | N-ok, bash -n | 18 ep / 51 facts; 5 skills |
| 20:31:03 | box | dv-ads | 6c8116ba… / f543542d | 092aa706… | MATCH | N-ok, bash -n | 0 (「cf CLI」 user); 5 skills |
| 20:31:05 | box | vllm-omni | 85cecc4b… / acf10e59 (pilot A) | 7382eebc… | MATCH | N-ok, bash -n | 0 (no user memory); 1 skill |
| 20:31:42 | iMac | xinyue | b7966109… / f543542d | 447bf9f6… | MATCH | N-ok, /bin/bash 3.2 -n | 8 ep / 24 facts; 10 skills |
| 20:31:47 | iMac | deepvision | 0d866b74… / f543542d | 8d666531… | MATCH | N-ok, /bin/bash 3.2 -n | 18 ep / 51 facts; 5 skills |
| 20:31:49 | iMac | dv-ads | 6c8116ba… / f543542d | 092aa706… | MATCH | N-ok, /bin/bash 3.2 -n | 0; 5 skills |
| 20:31:50 | iMac | vllm-omni | 85cecc4b… / acf10e59 | 7382eebc… | MATCH | N-ok, /bin/bash 3.2 -n | 0; 1 skill |
Full lines: `box/install.txt`, `imac/install.txt`; outputs `*/mcp-<n>.txt`; `*/search-log.txt` (all hybrid, rerank absent, ok, foreign_dropped=0);
`*/endpoint.txt` (all tailnet 200); `*/g1.txt` (new §3.3 loop: 4× N-ok befbd092 per machine, pi ext 743e3d27).
Nightly windows (23:30, 00:10) not touched: rollout finished 20:31:52.

## Rollback
Per copy: `install -m 755 ~/.local/bin/everos-mcp-<n>.bak-v21-pre-v22 ~/.local/bin/everos-mcp-<n>` (vllm → pilot A; for v2.1 use `.bak-v21-pre-hybrid`).
Without changing scripts: `EVEROS_MCP_SEARCH_METHOD=keyword` in the project env file.

## Not done
- No Claude Code / pi model sessions (16-grid §11 re-run, §12 step 3); only direct MCP stdio calls through the installed launchers.
  Already-running Claude/pi sessions keep the old MCP process until they restart.
- HANDOFF §2 / PLAN keyword notes (§12 step 6) not edited.

Token check: box `token-check-final.txt` (53 files incl. evidence, box search/endpoint logs, standard, changelog, template) = 0; iMac logs + rollout dir = 0.
