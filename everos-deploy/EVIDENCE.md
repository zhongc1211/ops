# EverOS on the site VPS: deploy evidence

- Date: 2026-10-16 SGT (VPS clock 2026-10-15 18:30–18:50 UTC)
- Host: `ssh site` (root@157.230.194.108, Ubuntu 22.04.5, 957Mi RAM, 25G disk)
- Done by: a Claude Code session in the Orca ops worktree `everos-vps-deploy`, for owner dr eggbot
- Result: EverOS 1.4.2 is running under systemd on `127.0.0.1:8000`. `https://everos.deepvision.sg/health` returns 200 through Cloudflare (DNS record was already in place; this session did not change DNS).

## 1. Before cleanup

```
$ docker ps -a
deepvision-origin-tls   nginx:stable-alpine                 Up 9 minutes             (host network, :443)
headscale               ghcr.io/juanfont/headscale:0.29.3   Up 9 minutes (healthy)   :8443->8080/tcp, :3478/udp
site-app-1              deepvision-site:latest              Up 9 minutes             :80->3000/tcp

$ free -h
Mem:   total 957Mi  used 256Mi  free 78Mi  buff/cache 622Mi  available 546Mi
Swap:  0B

$ df -h /
/dev/vda1  25G  7.3G  17G  31%
```

Running systemd services were only the OS baseline plus docker/containerd and the DigitalOcean agents. Nothing else app-related.

## 2. What was stopped or removed

| Item | Action | Data | How to restore |
|---|---|---|---|
| `site-app-1` (old website, compose in `/opt/site`) | `docker-compose down`: container and `site_default` network removed | `/opt/site/data` bind mount kept; image `deepvision-site:latest` kept | `cd /opt/site && docker-compose up -d` (needs :80 back from host nginx) |
| `headscale` (`/opt/headscale`) | `docker-compose stop`. **The `docker system prune -f` that followed also deleted the stopped container.** | Config, TLS and DB are bind mounts under `/opt/headscale/{config,tls,lib}`, all intact (`db.sqlite`, `noise_private.key`, `derp_server_private.key` checked). Image kept. No named volumes existed. | `cd /opt/headscale && docker-compose up -d` |
| `deepvision-origin-tls` | **Kept, not changed** | — | — |
| `docker system prune -f` (without `-a`) | Removed the 2 stopped containers, 2 unused networks and dangling image layers: 824.7MB | No named volumes existed before or after | — |

Why headscale was stopped: it has 4 registered nodes (`mbp`, `iphone`, `office`, `imac`) per `/opt/headscale/OPERATIONS.md`, but the VPS had only just been powered back on, so nothing had depended on it recently. I could not confirm whether it is still in use, so I stopped it per the brief and did not delete any data. **Someone needs to decide whether to bring it back.** While it is down, `headscale.deepvision.sg:8443` (DNS-only record) is unreachable, so those Tailscale clients cannot log in through it or use the `site` DERP relay. It used 42MiB (limit 192m).

Leftover images, not deleted (prune without `-a` keeps them): `caddy:2-alpine`, `node:20-alpine`, `node:22-alpine`, `deepvision-site:latest`, `headscale:0.29.3`, `nginx:stable-alpine`.

### Added (not in the brief)

- **1 GiB swap**: `/swapfile` in `/etc/fstab`, `vm.swappiness=10` (`/etc/sysctl.d/99-everos-swap.conf`). The box had no swap, and EverOS uses about 250Mi at idle.

## 3. After cleanup, before install

```
$ free -h
Mem:   total 957Mi  used 203Mi  free 72Mi  buff/cache 681Mi  available 598Mi
```

598Mi available, above the 400Mi target.

## 4. EverOS install

| Item | Value |
|---|---|
| Version | `everos 1.4.2` (PyPI); health reports `"version":"1.4.2"` |
| Python | 3.12, installed by uv 0.13.1 (`/usr/local/bin/uv`), interpreter under `/opt/everos/python` |
| venv | `/opt/everos/venv` (544M) |
| Memory root | **`/var/lib/everos`** (`everos init --root /var/lib/everos`). Separate from Raven's `~/.raven/everos`, which was not touched |
| Run user | system user `everos` (home `/var/lib/everos`, nologin) |
| Bind | `127.0.0.1:8000` only (`ss` shows `127.0.0.1:8000`) |
| systemd | `/etc/systemd/system/everos.service`, enabled. `Restart=always`, `MemoryHigh=500M`, `MemoryMax=700M`, `ProtectSystem=strict`, write access only to `/var/lib/everos` |
| Restart check | `kill -9` on the main PID: systemd restarted it (PID 3569 → 5017, `NRestarts=1`) and `/health` was green again |

### Config as written

`/var/lib/everos/everos.toml`: the unchanged `everos init` template (mode 640). Secrets are kept out of it.

`/etc/everos/everos.env` (root:everos 640, read through `EnvironmentFile=`):

```
EVEROS_ROOT=/var/lib/everos
EVEROS_API__HOST=127.0.0.1
EVEROS_API__PORT=8000
EVEROS_MEMORY__TIMEZONE=Asia/Singapore
EVEROS_LOG_FORMAT=json
EVEROS_LOG_LEVEL=INFO
EVEROS_LLM__API_KEY=placeholder-not-configured
```

- **LLM is a placeholder.** The model and base URL are the template defaults (`openai/gpt-4.1-mini` via `https://openrouter.ai/api/v1`), and the key is a placeholder string. `/health` reports `llm: true` because a key value exists, but any `/add` → extraction call will fail authentication until a real key is put in `/etc/everos/everos.env` followed by `systemctl restart everos`.
- No embedding, rerank or multimodal. Keyword search works; `method: hybrid` (the default) returns 422. Clients must send `"method":"keyword"`, as HANDOFF already says.
- Timezone set to `Asia/Singapore` so date buckets match the SGT nightly review. This was my choice; if UTC is wanted, change it before any data is imported.

### Health JSON (local `curl -fsS http://127.0.0.1:8000/health`, and identical via the public URL)

```json
{"status":"ok","version":"1.4.2","capabilities":{"llm":true,"embed":false,"rerank":false,"multimodal_llm":false,"parser":true},"disabled_features":["vector_search","hybrid_search","reflection","skill_extraction","agentic_search","knowledge","multimodal_upload"],"cascade":{"healthy":true,"reasons":[],"pending":0,"failed_permanent":0,"failed_retryable":0,"drain_consecutive_failures":0,"unrecoverable_total":0,"optimize_failure_streak":0,"prune_stale_seconds":0.7}}
```

## 5. Reverse proxy

| Item | Value |
|---|---|
| Server | Host nginx 1.18.0 (apt), systemd `nginx`, enabled, listens on `:80` only. The `deepvision-origin-tls` container still owns `:443` |
| Site config | `/etc/nginx/sites-available/everos.conf` (symlinked into `sites-enabled`); Ubuntu `default` site removed |
| Auth include | `/etc/nginx/everos-auth.conf` (root 600) |
| Token | `/etc/everos/proxy-token` (root 600, 64 hex chars). Not copied anywhere else |
| Routing | `server_name everos.deepvision.sg` → `http://127.0.0.1:8000`; any other Host gets `444` |
| TLS | None at the origin. The zone is Flexible, so Cloudflare connects to the origin over HTTP :80 |

**Bearer token gate (added, not in the brief).** EverOS has no built-in auth: its config and SECURITY notes say to put a gateway in front before exposing it. Without a gate, anyone could read and write memory through the public hostname. nginx now requires `Authorization: Bearer <token>` on every path except `GET /health`, and strips that header before passing the request to EverOS. everos-mcp 0.1.0 sends exactly this header when `EVEROS_API_KEY` is set (`everos_mcp/client.py:63`), so **the MCP config in HANDOFF-coding.md needs one more env var: `EVEROS_API_KEY=<contents of /etc/everos/proxy-token>`**. HANDOFF was not edited in this session.

Checks run:

| Request | Result |
|---|---|
| `curl -fsS http://127.0.0.1:8000/health` (on the VPS) | 200, JSON above |
| `GET https://everos.deepvision.sg/health` (from iMac, through Cloudflare) | 200, same JSON |
| `POST https://everos.deepvision.sg/api/v2/memory/search` without token | 401 |
| Same with token, `{"agent_id":"coding-smoke","app_id":"smoke","project_id":"smoke","query":"deploy","method":"keyword","top_k":3}` | 200, empty result (`{"episodes":[],…,"agent_skills":[]}`) |
| `POST /api/v2/memory/search` on :8000 without `method` (hybrid) | 422, as expected without embedding |
| `https://deepvision.sg/` (apex, Worker) | 307, unchanged |

Search was only a read; the `smoke` space was not written to. `default` was not touched.

## 6. Final state

```
$ free -h            (EverOS running, after the restart test)
Mem:   total 957Mi  used 447Mi  free 69Mi  buff/cache 439Mi  available 350Mi
Swap:  1.0Gi used 2.0Mi

$ docker ps -a
deepvision-origin-tls   Up

$ ss -ltnp
0.0.0.0:443     nginx (deepvision-origin-tls container)
0.0.0.0:80      nginx (host, everos proxy)
127.0.0.1:8000  everos

$ df -h /
/dev/vda1  25G  8.1G  17G  34%
```

## 7. Not done (per brief)

- Did not change DNS (the `everos` A record already resolves to Cloudflare), apex/www, or the zone SSL mode.
- Did not change automation `75b324a4`, did not attach MCP, did not import LESSONS.
- Mac daily backup: skipped per Zack (PLAN §5 step 2).
- No E2E with a real MCP client; only HTTP checks with curl.

## 8. Open risks

1. **LLM key is a placeholder.** Health is green, but writes (`/add`, `/flush` extraction) will fail until a real key is configured. Needs an owner decision on the provider (OpenRouter or another).
2. **Headscale is down** (container removed, data kept). If the tailnet still uses it, restore with `cd /opt/headscale && docker-compose up -d` (about 42Mi RAM).
3. **Memory is tight.** 350Mi available with EverOS idle at about 250Mi; the 1 GiB swap is a buffer. Large `/add` batches or turning on embedding/LanceDB vector work could push it into swap. The systemd `MemoryMax=700M` limits the damage to EverOS itself.
4. **Origin traffic is plain HTTP** (Flexible). To move to Full (strict), the origin needs a certificate covering `everos.deepvision.sg`; the existing Origin CA cert only covers `deepvision.sg` and `www.deepvision.sg`. Then add a `listen 443 ssl` server, which means coordinating with the `deepvision-origin-tls` container that holds :443.
5. **The origin-tls container now returns 502 for the apex at the origin.** It proxies `deepvision.sg` on :443 to `127.0.0.1:80`, which is now the EverOS nginx and returns 444 for other hosts. The public apex is served by the Worker (307 checked), so users are not affected, but the container's job is now unclear.
6. **Single shared bearer token.** Anyone with the token has full read/write access. There is no per-client token and no rotation process. Rotate with `openssl rand -hex 32 > /etc/everos/proxy-token`, regenerate `/etc/nginx/everos-auth.conf`, reload nginx, then update every MCP config.
7. **Port 80 is open to the internet** (`ufw` is inactive). HANDOFF/DNS-PLAN says the DO cloud firewall `deepvision-site-origin` only allows Cloudflare IPs on 80/443; this session did not verify that firewall.
8. No backup of `/var/lib/everos` (Mac backup skipped per Zack).

## 9. Post-deploy: headscale restore + Tailscale + magpie LLM (2026-10-16 SGT)

Zack: restore headscale as control plane; put Tailscale on site/iMac/box; keep Cloudflare for EverOS; LLM = magpie over Tailscale.

| Item | Result |
|---|---|
| headscale restore | `cd /opt/headscale && /usr/local/bin/docker-compose up -d`; health 200 on `:8443` |
| Nodes online | `imac 100.64.0.4`, `site 100.64.0.5`, `box 100.64.0.6` |
| Nodes offline (kept) | `mbp 100.64.0.1`, `iphone 100.64.0.2`, `office 100.64.0.3` |
| EverOS LLM | `EVEROS_LLM__BASE_URL=http://100.64.0.4:3425/v1`, model `codex/gpt-6.1-sol` (Zack's decision; earlier runs used claude-haiku-5-5); `/add`+`/flush` produced episode + atomic_fact |
| Cloudflare | `https://everos.deepvision.sg` left as-is (Zack: tunnel 留着) |
| OPERATIONS.md | Updated on site with nodes + restore + box `/etc/hosts` caveat |
| Mac daily backup | Skipped for now (Zack: 除了 imac 备份) |

Secrets (proxy-token, magpie gateway key) stay only on the host env files; **not** in this repo.
