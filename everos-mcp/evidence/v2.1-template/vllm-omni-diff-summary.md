# box `~/.local/bin/everos-mcp-vllm-omni` vs launcher v2.1 (read-only comparison, nothing changed)

- vllm-omni launcher: sha256 `c570aac3b8b11d760f44fba301d9a7d7d66ef689c03f15dbed3238118adb1f6b`, mtime 2026-10-17 11:43 SGT. It has **no `N=` line**, so the §3.3 normalization (`sed 's/^N=.*/N=@/'`) changes nothing and normalized == raw = c570aac3 → G1 shows `N-BAD`.
- v2.1 normalized sha: `f543542db2cd6d5fcdaf33e6688700e4c91e19d01d42f144a475f5f601b39ce6`.
- Full unified diff: `vllm-omni-vs-v2.1.diff` (also has live xinyue vs v2.1).
- Its env file `~/.config/everos/vllm-omni.env` (600) already sets the 6 lines incl. `EVEROS_BASE_URL=https://everos.deepvision.sg`, so the v2.1 checks would pass with it unchanged.

| Area | vllm-omni (now) | v2.1 |
|---|---|---|
| Identity | hard-coded name `vllm-omni` in messages, no `N=` line | `N=<N>`, only line that differs per project |
| Env file | `${EVEROS_ENV_FILE:-~/.config/everos/vllm-omni.env}`: **caller can point it at another project's env** (the hole v2 §3.4 closed) | fixed `~/.config/everos/$N.env` |
| Inherited `EVEROS_*` | not unset before sourcing; BASE_URL/API_KEY/SESSION_ID from the caller survive if the env file doesn't set them | unset (incl. SESSION_ID, TAILNET_URL, UPSTREAM_HOST) before sourcing |
| Scope override | same `EVEROS_ALLOW_SCOPE_OVERRIDE=1` logic, written differently (functionally equivalent) | v2 form |
| BASE_URL check | none (missing → everos-mcp falls back to api.evermind.ai with our key) | must equal `https://everos.deepvision.sg` |
| Required vars check | none (missing app/project → silent `default` scope) | 5 required vars |
| Endpoint | always public via Cloudflare (100s 524 limit) | tailnet probe 3s, public only on connect failure, endpoint.log |
| Host header | n/a (public) | `Host: everos.deepvision.sg` on every request |
| Tools exposed | all 7 (read-only relies only on Claude deny / pi toolExposure) | only the 3 read tools; refuses to start if the set differs |
| Version pin / keyword patch / PATH | same (`everos-mcp==0.1.1`, keyword patch, PATH) | same |

Conclusion: vllm-omni is a pre-v2 launcher (older than the v2 template, not just missing tailnet). Replacing it with the v2.1 render (`N=vllm-omni`) needs no env change; do it together with the other 7 copies at rollout. Not changed here.

## 2026-10-17 17:25–17:27 SGT: replaced on both machines (vllm-omni rollout)
- Backup kept in place: `~/.local/bin/everos-mcp-vllm-omni.bak-v1` (box and iMac), copies in `mcp-evidence/vllm-omni/launcher-backups/`. Backup raw sha256 `c570aac3b8b11d760f44fba301d9a7d7d66ef689c03f15dbed3238118adb1f6b` on both (same as above).
- New: `sed 's/^N=<N>$/N=vllm-omni/' templates/everos-mcp-launcher-v2.1.sh`, mode 755. Raw sha256 `7b28f7e916f1362990359c230ff4129445a690b8fc07292a3306fb36b6db4430` on both; normalized `f543542d…b39ce6` on both; `grep ^N=` → `18:N=vllm-omni`; `bash -n` ok (box 5.2, iMac /bin/bash 3.2.57).
- Template copied to the iMac verbatim (raw sha256 `c23a00a3…362aad` on both sides). Env files untouched.
- Behaviour changes in effect: no `EVEROS_ENV_FILE` override, inherited `EVEROS_*` dropped, BASE_URL + 5-var checks, tailnet-first, Host header, server exposes 3 read tools only. endpoint.log after first starts: `endpoint=tailnet url=http://100.64.0.5 health=200` on both.
