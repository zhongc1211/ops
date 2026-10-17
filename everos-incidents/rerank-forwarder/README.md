# EverOS rerank → DashScope intl qwen3-rerank via loopback forwarder (2026-10-17)

Approval: Zack 20:10 SGT 「换，用转发的办法（不动 EverOS 代码）」. EverOS code and everos.toml untouched.

## Why a pure nginx rewrite works (EverOS 1.4.2 code, read only)
- `component/rerank/factory.py`: providers `deepinfra | vllm | dashscope`. The built-in `dashscope` provider accepts only
  `gte-rerank-v2` (hard check in `dashscope_provider.py`, "qwen3-rerank … should be added as a separate branch"), so it can't take qwen3-rerank.
- `vllm_provider.py`: `POST {base_url}/rerank`, body `{model, query, documents}`, `Authorization: Bearer <api_key>` if set,
  parses `results[].index` + `results[].relevance_score`; batch 10 docs.
- DashScope intl `POST https://dashscope-intl.aliyuncs.com/compatible-api/v1/reranks` takes the same body and returns
  `{"object":"list","results":[{"index":0,"relevance_score":0.91},…],"model":"qwen3-rerank","usage":…}` (tested 200, 0.15s).
  → only the path differs; no body mapping, no python service needed.

## What changed (site 157.230.194.108)
1. nginx: new `/etc/nginx/sites-available/everos-rerank-forwarder.conf` (+ symlink in sites-enabled), copy here.
   `listen 127.0.0.1:8031`, `allow 127.0.0.1; deny all`, only `POST /rerank` → DashScope intl `compatible-api/v1/reranks`
   (TLS verify on, SNI, resolver 127.0.0.53); everything else 404/403. Holds no key: EverOS's own Authorization header is passed through.
   Own access log `/var/log/nginx/everos-rerank.log` with a header-free format. `nginx -t` ok, **reload** (not restart) 20:17:23 SGT.
   Backup of all of /etc/nginx: `/root/nginx-etc.bak.20261017T121723Z.tgz`.
2. `/etc/everos/everos.env` (backup `/etc/everos/everos.env.bak.rerank-on-20261017T121809+0000`), appended via `set_rerank_env.py`:
   ```
   EVEROS_RERANK__PROVIDER=vllm
   EVEROS_RERANK__MODEL=qwen3-rerank
   EVEROS_RERANK__BASE_URL=http://127.0.0.1:8031
   EVEROS_RERANK__API_KEY=<same DashScope intl key as EVEROS_EMBEDDING__API_KEY; len 115, sha256[:8] daec8d06>
   ```
   Mode 640 root:everos kept. Key copied file-to-file by the script, never printed or on a command line.
3. One EverOS restart: in-flight check 20:18:09 (0 add/flush in last 10 min, 0 conns to :8000) → restart 20:18:09 → /health ok 20:18:21 SGT (~12s).

## Verification
- `/health` capabilities `rerank: true` (local, tailnet, Cloudflare all 200) — `health-after.txt`. The `rerank_capability_build_failed` startup warning is gone.
- Agent-side hybrid skill search, **no `enable_llm_rerank`**, own scope per project, tailnet — `agent-hybrid-isolation.txt`:
  | project | q | status | cold / warm | skills | foreign |
  |---|---|---|---|---|---|
  | xinyue/xinyue-site (coding-xinyue-site) | 切流量 绑定 | 200 | 3.83s / 0.80s | 5, top `check-bindings-before-shifting-production-traffic` 0.93 | none |
  | deepvision/deepvision-site | tailwind | 200 | 1.06s / 1.31s | 5, top `tailwind-v4-custom-theme-tokens` 0.60 | none |
  | deepvision/deepvision-ads | cf CLI | 200 | 0.97s / 0.79s | 5, top `use-cf-cli-not-wrangler` 0.92 | none |
  | vllm-omni/vllm-omni | NCCL | 200 | 0.87s / 0.72s | 1, `secure-h100-nccl-nvls-and-pod-loss` 0.74 | none |
  Before (19:32): same calls → 422 PROVIDER_NOT_CONFIGURED; with enable_llm_rerank 3.6–5.2s. Forwarder log shows 8 `POST /rerank` 200, upstream 0.08–0.31s.
  User-side hybrid regression (xinyue) 200, 1.07s.
- Not reachable off-box — `reachability-box.txt`: from the box, `100.64.0.5:8031` → connection refused (listener is 127.0.0.1 only);
  `157.230.194.108:8031` → connect timeout (firewall); `http://100.64.0.5/rerank` lands on the EverOS block (401), not the forwarder.
  On site: unauthenticated POST /rerank → DashScope 401 (no key injection), GET → 403, other paths → 404.
- No key in logs: exact-value grep = 0 in everos-rerank.log, nginx error.log, access.log, journal of everos and nginx since 20:00 SGT.

## Rollback (≈15s, one EverOS restart)
1. In-flight check (no add/flush in the last minutes).
2. `sudo cp -p /etc/everos/everos.env.bak.rerank-on-20261017T121809+0000 /etc/everos/everos.env` (or delete the 6 lines under the
   "Rerank via loopback nginx forwarder" comment); check `stat -c '%a %U:%G'` = `640 root:everos`.
3. `sudo systemctl restart everos`; /health → `rerank:false` (agent hybrid then needs `enable_llm_rerank:true` again).
4. Optional: `sudo rm /etc/nginx/sites-enabled/everos-rerank-forwarder.conf && sudo nginx -t && sudo systemctl reload nginx`
   (or restore `/root/nginx-etc.bak.20261017T121723Z.tgz`).

## Notes
- Cost: qwen3-rerank billed per token on the same DashScope intl key (each search ≈ 1 call per 10 candidates, ~100–300 tokens/call in these tests).
- The forwarder's DNS resolve is dynamic (resolver + variable), so a DashScope IP change doesn't need an nginx reload.
- If DashScope is down, EverOS's vllm client retries 3× on 5xx/429 then the agent hybrid search errors; clients can still send `enable_llm_rerank:true` or use keyword.
