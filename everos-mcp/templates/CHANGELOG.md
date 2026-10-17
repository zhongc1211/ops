# EverOS MCP launcher CHANGELOG

## v2.2 (2026-10-17, eggbot; Zack 20:04 SGT via Coding助手: 「试点没问题就推」; vllm hybrid pilot variant A passed)
Template: `everos-mcp-launcher-v2.2.sh` (`N=<N>` placeholder). Canonical normalized sha (§3.3: `sed 's/^N=.*/N=@/' | shasum -a 256`):
`befbd0921afc36751323e70152c382f84e4d4257b01d526c597287f8aad7a3c3`. Replaces v2.1 `f543542d…b39ce6` and the vllm pilot draft A `acf10e59…3ab05f7`.
Based on the vllm pilot launcher draft A (`mcp-evidence/vllm-omni/hybrid-pilot/everos-mcp-vllm-omni.hybrid-draft-A`, raw 85cecc4b).

Changes from v2.1:
1. **Hybrid by default.** `EVEROS_MCP_SEARCH_METHOD` default `hybrid` (was `keyword`); only `hybrid|keyword` are accepted, else exit 1
   (`vector` is not allowed: in EverOS 1.4.2 it returns episodes without atomic facts).
2. **No enable_llm_rerank, ever.** Both tracks send `method=hybrid` without `enable_llm_rerank`; EverOS reranks server-side
   (qwen3-rerank via the site-local forwarder, /health `rerank:true` since 20:18:21 SGT). The pilot's `EVEROS_MCP_AGENT_RERANK` knob is removed.
   If the server's rerank goes away, agent-track hybrid returns 422 PROVIDER_NOT_CONFIGURED → set `EVEROS_MCP_SEARCH_METHOD=keyword`
   in the env file (no script change) or roll back to v2.1.
3. **Atomic facts in search_memory.** everos-mcp 0.1.1 `_fmt_episode` drops `episodes[].atomic_facts`; the wrapper wraps it so each episode
   is followed by up to 8 `  - fact: <content>` lines (in 1.4.2 facts only come back nested in hybrid episodes).
4. **Client-side scope filter.** Returned episodes/skills/cases/profiles whose `app_id`/`project_id`/`user_id|agent_id` are set and differ from
   the env file's scope are dropped and counted (`foreign_dropped=`). Second layer only; the gate saw 0 (episode id strings like
   `zack_ep_20261017_00000001` repeat across scopes as different records, so isolation is judged on scope fields, not ids).
5. **search.log.** Each search appends one line to `${XDG_STATE_HOME:-~/.local/state}/everos-mcp/search.log`:
   `track= method= enable_llm_rerank=absent top_k= outcome= ms= agent_skills= agent_cases= episodes= atomic_facts= foreign_dropped=`
   (no key, headers or query text).
6. Header comment: pilot text replaced by the v2.2 search description; `launcher v2.2`.

Unchanged: tailnet-first probe and Host header, endpoint ledger, server-side read-only (3 tools), scope lock, env checks, `everos-mcp==0.1.1` pin, PATH.
Env files need no change. pi extension unchanged (it only spawns `~/.local/bin/everos-mcp-<n>`; sha 743e3d27).
Gate + rollout evidence: `mcp-evidence/v2.2-rollout/`.

## v2.1 (2026-10-17, eggbot; Zack 16:56 SGT 「批，按 v2 推进」)
Template: `everos-mcp-launcher-v2.1.sh` (`N=<N>` placeholder). Canonical normalized sha (§3.3: `sed 's/^N=.*/N=@/' | shasum -a 256`):
`f543542db2cd6d5fcdaf33e6688700e4c91e19d01d42f144a475f5f601b39ce6`. Replaces v2 `a165609f…e15ff01a` and xinyue's sample `d5267256…`.

Changes from v2 (and from the xinyue PR #10 sample it is based on):
1. **Tailnet first.** One `/health` probe at start (3s, no key, `Host: everos.deepvision.sg`) to `EVEROS_TAILNET_URL`
   (default `http://100.64.0.5`). Connected → everos-mcp uses the tailnet URL. Falls back to the public URL **only when the
   probe cannot connect** (refused, no route, DNS, connect timeout). A tailnet answer other than 200 (e.g. 502/503) stays on the tailnet
   (EverOS itself is the problem; public reaches the same origin). xinyue's sample fell back on any non-200.
2. **Explicit Host on every request.** The python wrapper adds `Host: everos.deepvision.sg` to everos-mcp's request headers
   (xinyue's sample only sent it on the probe; MCP calls went out with `Host: 100.64.0.5`, which works only because of the
   address-specific nginx block).
3. **Endpoint ledger.** Every start appends `endpoint=tailnet|public url=… health=… curl_rc=… connect=…` to
   `${XDG_STATE_HOME:-~/.local/state}/everos-mcp/endpoint.log`; a public fallback also prints one stderr line.
4. **Server-side read-only.** Before `server.main()` the wrapper removes every tool except `recall_agent_experience`,
   `search_memory`, `list_memories`, and refuses to start if the remaining set differs (e.g. a future everos-mcp adds a tool).
   Claude deny (§4.4) and pi `toolExposure` (§5.1) stay as they are; they become a second layer. Turning on `record_trajectory`
   later needs a new template version (as §6 already says).
5. **Endpoint from the env file only.** `EVEROS_TAILNET_URL` (optional) is read only from `~/.config/everos/<N>.env`; inherited
   values are unset. It must be `off` or `http://100.64–127.x.y[:port]` (tailnet CGNAT range), else exit 1, so the key can't be
   sent to an arbitrary host. `EVEROS_BASE_URL` must still be the public URL (unchanged v2 check).
6. Header no longer says "no longer byte-identical"; all 8 copies are again byte-identical except `N=`.

Unchanged: scope lock and `EVEROS_ALLOW_SCOPE_OVERRIDE`, 5 required vars, `everos-mcp==0.1.1` pin, keyword search patch, PATH.
Env files need no change (EVEROS_TAILNET_URL is optional). Evidence: `mcp-evidence/v2.1-template/`.
