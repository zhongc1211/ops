# EverOS 1.4.2 — turn on embedding with DashScope INTL (proposal, NOT applied)

Status 2026-10-17 18:49 SGT: key validated and **staged** in `/etc/everos/everos.env` as a commented line
`#STAGED# EVEROS_EMBEDDING__API_KEY=…` (len 115, sha256 prefix `daec8d06`). EverOS has not been restarted;
`/health` still shows `embed:false, rerank:false`. `everos.toml` unchanged. Backup of the env before the change:
`/etc/everos/everos.env.bak.embedding-20261017T104903+0000` (site clock is UTC = 18:49:03 SGT).

Why staged and not active: the unit has `Restart=always`, and `/var/lib/everos/everos.toml` still says
`[embedding] model="Qwen/Qwen3-Embedding-4B" base_url="https://api.deepinfra.com/v1/openai"` (api_key empty). An active key
alone would make embedding "available" on ANY restart (crash, OOM at MemoryMax=700M, reboot) and point the DashScope key at
DeepInfra (401 on every embed, failed cascade rows, skill/reflection strategies firing and failing). Activating the key and
the model/base_url lines in one step avoids that.

## 1. Validation (box 18:2x SGT, site 18:49 SGT; key via stdin, never on argv)
| Call | Result |
|---|---|
| GET compatible-mode/v1/models | 200, 100 models; embedding: text-embedding-v4, text-embedding-v3, qwen3.7-text-embedding |
| POST compatible-mode/v1/embeddings text-embedding-v4 "测试" | 200, dim 1024 (default), 1.0s from box, 0.19s from site |
| same with dimensions=1024 | 200, dim 1024. Allowed: 64,128,256,512,768,1024,1536,2048,3072 (2560 → 400) |
| qwen3.7-text-embedding | 200, dim 1024, 0.9s |
| rerank native `api/v1/services/rerank/text-rerank/text-rerank` qwen3-rerank | 200 (`output.results` index/relevance_score) |
| same, gte-rerank-v2 | 400 "Model not exist." (gte-rerank: 403 AccessDenied) — not offered on intl for this key |
| `compatible-api/v1/reranks` qwen3-rerank `{model,query,documents}` | 200 (`results` at top level) |
| `compatible-api/v1/rerank` (singular) | 404 |
The sk-ws key works on the plain intl endpoint; no workspace-specific host was needed.

## 2. How EverOS 1.4.2 reads it (read from the installed code)
- Precedence: init args > env (`EVEROS_<SECTION>__<KEY>`, systemd `EnvironmentFile=/etc/everos/everos.env`) > `/var/lib/everos/everos.toml` > shipped defaults.
  So env lines override the toml; **no toml edit is needed**.
- Embedding (`EmbeddingSettings`, OpenAI-compatible client): `EVEROS_EMBEDDING__MODEL`, `__API_KEY`, `__BASE_URL`, `__DIMENSIONS`,
  `__TIMEOUT_SECONDS`(30), `__MAX_RETRIES`(3), `__BATCH_SIZE`(10), `__MAX_CONCURRENT`(10), `__QUERY_MAX_CONCURRENT`(4).
  Capability = model + api_key + base_url all set (cached at process start → restart needed).
- Vector width: LanceDB `vector` column is fixed at **1024** (`component/embedding/factory.py _DEFAULT_DIM=1024`); longer vectors are
  truncated client-side. text-embedding-v4 returns 1024 by default; set `DIMENSIONS=1024` explicitly so DashScope truncates/normalizes
  server-side and a default change can't bite. (DeepInfra Qwen3-Embedding-4B is 2560 native → would have been truncated; no vectors
  from it exist.) Batch size 10 matches DashScope's per-request limit for v4.
- Re-index: embedding has never been available on this store (health `embed:false` since install; logs show
  `embedding_capability_build_failed`), so there are no vectors to migrate. Existing episodes/cases/skills need a **backfill** to get
  vectors (`everos cascade backfill`), which refuses to run while the server is running (exclusive lock).
- Rerank (`RerankSettings.provider` ∈ deepinfra | vllm | dashscope): **cannot use this key without a code change**:
  - `dashscope` provider hard-codes `gte-rerank-v2` (raises on any other model); this key has no gte-rerank-v2 on intl.
  - `vllm` provider POSTs `{base_url}/rerank`; DashScope's compatible path is `/reranks` → 404.
  - Options for later (each needs its own approval): a tiny local shim/nginx rewrite `/rerank → /compatible-api/v1/reranks`, a patch
    adding qwen3-rerank to the dashscope provider, or another rerank vendor. Leave rerank off for now.
  - Effect: HYBRID memory search does not use rerank (RRF fusion; "HYBRID defaults to no LLM rerank"). `knowledge` routes require
    rerank and stay off. Whether `agentic_search` is enabled with embed only will be visible in `/health disabled_features` after restart.

## 3. Exact change (waiting on Zack's yes for the restart)
`/etc/everos/everos.env` (back up first; keep 640 root:everos; never print values):
```diff
-#STAGED# EVEROS_EMBEDDING__API_KEY=<key>
+EVEROS_EMBEDDING__API_KEY=<key>
+EVEROS_EMBEDDING__MODEL=text-embedding-v4
+EVEROS_EMBEDDING__BASE_URL=https://dashscope-intl.aliyuncs.com/compatible-mode/v1
+EVEROS_EMBEDDING__DIMENSIONS=1024
```
No rerank lines. No toml change (optional later tidy-up: set the toml `[embedding]` to the same model/base_url so the file isn't misleading).

## 4. Steps after Zack says yes
1. Pre-check: no in-flight `/flush`/`/add` (nginx access log last 2 min, as in the tiktoken change); `systemctl show everos -p NRestarts`.
2. `cp -p /etc/everos/everos.env /etc/everos/everos.env.bak.embedding-on-<ts>`; apply the diff above (sed `s/^#STAGED# //` + append 3 lines); check mode/owner.
3. `systemctl restart everos`; wait for `/health` → expect `capabilities.embed: true`, `vector_search`/`hybrid_search`/`skill_extraction`/`reflection` gone from `disabled_features`; `rerank:false`, `knowledge` still disabled.
4. Smoke (tailnet endpoint, ops/everos-smoke only): `/add` + `/flush` one message → 200; then `search` with `method=vector` and `method=hybrid` → 200 with results; journal shows no `embedding_*failed`.
5. Backfill existing data (server must be stopped for this exclusive phase; plan ~minutes of downtime):
   `systemctl stop everos` → `sudo -u everos bash -c 'set -a; . /etc/everos/everos.env; set +a; /opt/everos/venv/bin/everos cascade backfill --root /var/lib/everos --phase vectors'`
   (it prints a token estimate and asks y/n; then `--phase clusters`, then `--phase skills`, or `--phase all`) → `systemctl start everos`.
   Cost: text-embedding-v4 on a few thousand rows is cents; the skills phase also calls the LLM (magpie, existing quota).
6. Verify counts unchanged (`/api/v2/memory/get` totals per scope before/after) and §12 step 1 of the MCP standard: hybrid search 200 with results for the 4 scopes.

## 5. Default search mode and skill extraction (what each needs)
- Server default: `SearchRequest.method` already defaults to `hybrid` in 1.4.2; it only 422s today because embedding is off. Nothing to change server-side.
- Clients: the MCP launcher v2.1 forces `keyword` (`EVEROS_MCP_SEARCH_METHOD` default). Per MCP standard §12 (embedding upgrade path):
  pilot one project by adding `EVEROS_MCP_SEARCH_METHOD=hybrid` to its `~/.config/everos/<N>.env`, re-run its §11 cell + semantic queries;
  then a new template version removes the keyword patch (new canonical sha, all 8 copies at once, rerun 16 cells).
- Skill extraction: OME strategies `trigger_skill_clustering` and `extract_agent_skill` (and `reflect_episodes`, profile clustering) are
  enabled by default in `/var/lib/everos/ome.toml` and only gated by the embedding capability → they start running automatically after
  the restart (more LLM calls through magpie `group/everos-llm`). To keep them off initially, set `enabled = false` under
  `[strategies.extract_agent_skill]` / `[strategies.trigger_skill_clustering]` in ome.toml (hot-reloaded, no restart) before step 3.
  Existing cases get skills via backfill `--phase skills`. Coding-session write tools stay disabled (standard §6).

## 6. Rollback
- Fast: restore `/etc/everos/everos.env.bak.embedding-on-<ts>` (or re-comment the key line and delete the 3 lines) → `systemctl restart everos`
  → `/health` embed:false. Clients on keyword search are unaffected throughout.
- Vectors written to LanceDB are harmless when embedding is off (keyword path ignores them); to drop them: stop server,
  `everos cascade rebuild --root /var/lib/everos` (markdown is the source of truth), start.
- Remove the key entirely: restore `/etc/everos/everos.env.bak.embedding-20261017T104903+0000` (pre-key) and rotate the key in Model Studio.
