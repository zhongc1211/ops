# Fix for the 2026-10-17 flush 524: tailnet path + magpie fallback for EverOS

Zack approved this himself at 15:30 SGT: 「EverOS flush 走 tailnet 直连 site nginx（仅 tailnet、沿用 key）+ magpie 给 EverOS 配备用模型（用现有额度）」.
Work was done 15:31–15:55 SGT (UTC+8). No secrets appear in this folder; every bearer is shown as `<redacted>`.

| Item | Result |
|---|---|
| A. Tailnet path to site nginx | **PASS** |
| B1. Magpie fallback on upstream errors | **PASS** |
| B2. Fallback when the primary goes silent for 20–30s | **NOT POSSIBLE in magpie 0.1.1255 for EverOS's non-streamed calls.** Not hacked around; options are listed below. |

## A. Tailnet path (site nginx)

### Client endpoint
- **URL:** `http://100.64.0.5` (same API paths: `/api/v2/memory/add`, `/flush`, `/search`, `/get`; `/health` needs no auth)
- **Host header:** any value works; send `Host: everos.deepvision.sg` for clarity
- **Auth:** the same bearer as today, `Authorization: Bearer <EVEROS_API_KEY / proxy-token>`. No new key was created.
- **Timeouts:** nginx allows 400s. There is no Cloudflare in this path, so its 100s limit does not apply.
- **Public path:** `https://everos.deepvision.sg` is unchanged and still works (health 200; 401 without a key).

### What changed
- **New file** `/etc/nginx/sites-available/everos-tailnet.conf` (mode 600), symlinked from `sites-enabled/`. A copy is in this folder as `everos-tailnet.conf`.
  - It is a `server { listen 100.64.0.5:80; ... }` block.
  - It uses the same `$everos_authorized` map, the same 400s timeouts, the same `/health` exception, and the same `Authorization ""` stripping toward EverOS.
  - It also has `allow 100.64.0.0/10; deny all;`.
- **nginx reloaded.** `everos.conf` was not modified.
- **Boot safety:** nginx's `After=` does not include tailscaled, so I did not use `ip_nonlocal_bind`, and I did not change the firewall.
  - nginx already has a wildcard `listen 80` (in `everos.conf`). Because of that, the address-specific listen is not bound separately: nginx keeps the single `0.0.0.0:80` socket and picks this server by each connection's local address.
  - `ss` after the reload shows only `0.0.0.0:80` and `[::]:80`. nginx therefore cannot fail at boot when tailscale0 isn't up yet.
  - **Never add `bind` to that listen line.**
- **Isolation:**
  - Only packets addressed to 100.64.0.5 reach the block, and those arrive on tailscale0.
  - The existing tailscale iptables chain `ts-input` already drops 100.64.0.0/10 sources that don't come in on tailscale0.
  - ufw is inactive and was not changed.
  - From the iMac and the box, public IP :80 times out; something upstream already filters it, most likely a provider firewall.
  - From site itself, `http://157.230.194.108/` with `Host: 100.64.0.5` or any other host gets nginx's 444 (empty reply). It never reaches the tailnet block or EverOS.
  - Evidence: `a-isolation-tests-site.txt`, `a-access-tests-imac.txt`, `a-access-tests-box.txt`.

### Backups
- `/etc/nginx/sites-available/everos.conf.bak.20261017T073531Z`
- `/root/nginx-etc.bak.20261017T073531Z.tgz` (all of /etc/nginx before the change)

### Rollback
`rm /etc/nginx/sites-enabled/everos-tailnet.conf && nginx -t && systemctl reload nginx`
Optionally, delete the file in `sites-available/` too.

### Tests (all through http://100.64.0.5, app `ops` / project `everos-smoke`)
| From | Session | add | flush | Episode in md |
|---|---|---|---|---|
| box 100.64.0.6 | everos-smoke-box-tailnet-20261017153726 | 200 accumulated (5.5s) | 200 extracted (6.8s) | yes, plus 7 atomic facts |
| iMac 100.64.0.4 | everos-smoke-imac-tailnet-20261017153758 | 200 accumulated (5.2s) | 200 extracted (10.0s) | yes, plus 6 atomic facts |

- Without a key or with a wrong key: 401.
- md file: `/var/lib/everos/ops/everos-smoke/users/smoke-user/episodes/episode-2026-10-17.md`
- Evidence: `a-e2e-box.txt`, `a-e2e-imac.txt`, `a-e2e-md-check.txt`, `e2e-md-landed.txt`
- Script: `everos-smoke.sh` (reads the token from a file and never prints it)

## B. Magpie fallback model for EverOS

### What changed
- **Magpie, on the iMac:** new routing group `group/everos-llm` ("EverOS LLM"), created with the magpie CLI.
  - `routing=order`
  - `stays=off`, so each call starts on the primary again
  - members `codex/gpt-6.1-sol` → `grok/grok-4.7`
  - `firstToken: 25` added in `providers.json`. Config is in `b-magpie-group-everos-llm.json`.
- **The fallback is Grok 4.7 on the existing SuperGrok sign-in.** Magpie's catalog lists its cost as 0. The 7-day window was 41% used. No new account, card or plan was needed, and nothing new costs money.
  - Claude stays off in magpie.
  - I didn't use codex/gpt-6-astra because it is the same codex account, so it would most likely stall along with the primary.
- **No other agent's model or route was changed.** The existing group "永不卡住" was left as it was.
- **EverOS, on site:** in `/etc/everos/everos.env`, `EVEROS_LLM__MODEL` changed from `codex/gpt-6.1-sol` to `group/everos-llm`. Mode is still 640 root:everos. No other line changed.
- **EverOS was restarted** at 07:47:57Z (15:47:57 SGT) after the backup. It is healthy, with 0 restarts since.

### Backups
- `~/.config/magpie/providers.json.bak.20261017T153900+0800` (iMac)
- `~/.config/magpie/settings.json.bak.20261017T153900+0800` (iMac; not modified)
- `/etc/everos/everos.env.bak.20261017T074757Z` (site)

### Rollback
1. On site: `sed -i 's#^EVEROS_LLM__MODEL=.*#EVEROS_LLM__MODEL=codex/gpt-6.1-sol#' /etc/everos/everos.env && systemctl restart everos`. Alternatively, copy the `.bak` back with `cp -a` and restart.
2. On the iMac: `magpie group rm everos-llm`. Alternatively, restore `providers.json` from the `.bak` file; magpie reloads it.

### Tests
- **Magpie direct tests** (`b-magpie-direct-tests.txt`). The temporary test-only providers `stalltest` and `stalltest2` (a silent local listener, then a closed port) took the primary's place in the group:
  - Primary refused the connection (non-streamed request): failed over in 98ms, and grok served.
  - Primary silent, request **streamed**: magpie cut it with "no first token in 25s", and grok served.
  - Primary silent, request **not streamed** (EverOS's shape), on both the chat and the translated Messages path: **not cut**; the request hung until the client gave up.
- **EverOS E2E with the primary broken** (closed port), session `everos-smoke-box-fallback-20261017154818`:
  - add 200 and flush 200 extracted. The episode and 6 atomic facts landed.
  - Magpie traces (`b-magpie-traces.txt`) show the try on the primary failing with 502 connection refused and grok/grok-4.7 serving all 5 EverOS calls.
- **Primary restored:** members are back to `codex/gpt-6.1-sol, grok/grok-4.7`, and the test providers were removed.
  - box `everos-smoke-box-primary-restored-20261017155126` and iMac `everos-smoke-imac-primary-restored-20261017155225`: add and flush 200, episodes landed. Every call was served by codex/gpt-6.1-sol on the first try.
- The primary was swapped out only from 15:40 to 15:51. EverOS used the group only from 15:47:57, and the only EverOS traffic in that window was the test.

### What B does and doesn't cover
- **Covered:** codex errors before replying fail over to grok immediately. That includes 5xx, overload, connection reset or refused, 429, and out-of-quota. Magpie then rests codex for a minute or more, so the next calls go straight to grok.
- **Not covered: today's incident**, where codex sent nothing for 60s. In magpie 0.1.1255, `firstToken` applies only to client-**streamed** requests, and EverOS 1.4.2 sends non-streamed chat completions. When EverOS's own 60s timeout fires, it cancels the request (499). Magpie doesn't fail over on a cancel, and EverOS's SDK retries go back to codex.
- **Options:**
  - Magpie: ask upstream to make `firstToken` (or a per-provider stall timeout) also apply to non-streamed requests. The feature request "per-provider first-byte timeout" is open on yetone/magpie, and this is a natural extension. Then nothing else needs to change.
  - EverOS: an LLM setting that makes it stream. 1.4.2 has none, and `EVEROS_LLM__EXTRA={"stream":true}` would break the SDK's response parsing, so I didn't do it. Upgrading is ruled out.
  - A small local shim on the iMac that turns non-streamed calls into streamed ones. This is exactly the "hack" the brief said not to build, so it was not done.
  - Use the tailnet path (A) for flush. With nginx at 400s, EverOS's worst case of 3 × 60s ≈ 182s now finishes and returns an error instead of a Cloudflare 524. The client can then re-add with the same timestamps and flush again.

## C. tiktoken cache moved out of PrivateTmp (Zack approved 16:08 SGT: 「批准：改分词缓存并重启 EverOS」)

### What changed
- **Env file:** `/etc/everos/everos.env` gained a comment line and `TIKTOKEN_CACHE_DIR=/var/lib/everos/.cache/tiktoken`. Mode is still 640 root:everos, and no other line changed.
- **Directory:** created `/var/lib/everos/.cache/tiktoken` (owner everos:everos, mode 755).
- **Unit:** no change needed. `ReadWritePaths=/var/lib/everos` already covers the new directory under `ProtectSystem=strict`. `PrivateTmp` only affects /tmp, and `sudo -u everos test -w` passed.
- **Backup:** `/etc/everos/everos.env.bak.20261017T080854Z`

### Restarts
Before each restart I checked: no established connections to :8000, the last add/flush in the access log had already finished, and cascade pending was 0.

| | Issued (SGT) | Healthy (SGT) |
|---|---|---|
| Restart 1 | 16:09:14 | 16:09:25 |
| Restart 2 | 16:10:55 | 16:11:09 |

### Results
| Check | Result |
|---|---|
| (1) /health after each restart | **PASS**: ok; NRestarts=0; the new process has `TIKTOKEN_CACHE_DIR` set (`c-restart1.txt`) |
| (2) add+flush over 100.64.0.5 after restart 1 | **PASS**: session everos-smoke-box-after-restart1-20261017160940, add 200 in 13.3s, flush 200 extracted in 18.2s, episode landed. `fb374d41…` (o200k, 3,613,922 B) appeared in the cache dir at 08:09:45Z = 16:09:45 SGT (`c-e2e-after-restart1.txt`, `c-cache-after-restart1.txt`) |
| (3) first add after restart 2 | **PASS**: session everos-smoke-box-after-restart2-20261017161118, add 200 in **9.3s** (it was 99s before this fix), flush 200 extracted in 12.3s, episode landed. The cache file's mtime is still 08:09:45.591Z with the same size, so nothing was downloaded again. The first LLM call reached magpie 3.3s after the request started; the rest was the codex call itself (`c-e2e-after-restart2.txt`, `c-after-restart2-check.txt`, `c-magpie-calls.txt`) |
| (4) public https://everos.deepvision.sg/health | **PASS**: 200 (`c-public-health.txt`). The tailnet /health also returns 200. |

All EverOS LLM calls in these tests were served by codex/gpt-6.1-sol, the group's primary.

### Rollback
`cp -a /etc/everos/everos.env.bak.20261017T080854Z /etc/everos/everos.env && systemctl restart everos`
The directory `/var/lib/everos/.cache/tiktoken` is harmless if left in place.

### Remaining observation (not changed)
jieba also rebuilds `jieba.cache` (about 9 MB) in the private /tmp after each restart. It is built locally, not downloaded, and takes a few seconds. In these tests it happened during the flush after the first add, not inside the add. If it ever matters, `TMPDIR` or jieba's own cache setting could point it under /var/lib/everos. That needs a separate approval.

## Files
- **A:** `everos-tailnet.conf`, `a-access-tests-imac.txt`, `a-access-tests-box.txt`, `a-isolation-tests-site.txt`, `a-e2e-box.txt`, `a-e2e-imac.txt`, `a-e2e-md-check.txt`
- **B:** `b-magpie-group-everos-llm.json`, `b-magpie-direct-tests.txt`, `b-everos-env-change.txt`, `b-e2e-fallback.txt`, `b-e2e-primary-restored.txt`, `b-e2e-imac-primary-restored.txt`, `b-magpie-traces.txt`, `stall_server.py` / `stall_server.log` (test-only, stopped)
- **C:** `c-env-change.txt`, `c-restart1.txt`, `c-e2e-after-restart1.txt`, `c-cache-after-restart1.txt`, `c-restart2.txt`, `c-e2e-after-restart2.txt`, `c-after-restart2-check.txt`, `c-magpie-calls.txt`, `c-public-health.txt`
- **Both:** `e2e-md-landed.txt` (all 5 smoke sessions: episode plus atomic facts), `everos-smoke.sh`
