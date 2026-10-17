# 2026-10-17 EverOS flush 524: fdv-68-acceptance-box-pi-1442

Read-only investigation. Nothing was changed on site or the iMac (no restart, no config edit, no re-flush).
Times are SGT (UTC+8); raw logs are in UTC (SGT = UTC + 8h).

## Timeline
| SGT | Event | Source |
|---|---|---|
| 14:42:46.5 | Timestamps on the two client messages | sqlite-session-state.txt |
| 14:42:50.1 | `POST /add` returned 200 accumulated; 2 messages went into the buffer | journal, nginx |
| 14:42:53.5 | `POST /flush` arrived. The buffer was drained into memcell `mc_5a7ba609a7c2` and conversation_status was updated. agent_case was skipped (no_tool_single_user). | journal, sqlite |
| 14:42:53.67 | Episode-extract LLM call 1 to magpie returned 499 after 59.97s with in=0/out=0, so the upstream sent nothing | magpie-usage |
| 14:43:54.04 | SDK retry 2 returned 499 after 60.05s | magpie-usage, journal "Retrying request" |
| 14:44:55.09 | SDK retry 3 returned 499 after 60.03s | magpie-usage |
| ~14:44:33 | Cloudflare's 100s origin limit was hit and the client got 524. nginx logged 499 (client closed) at 14:44:55. | nginx-access |
| 14:45:55 | EverOS raised `LLMError: Request timed out` (unhandled). The request ended with a 500 that no one received. | everos-journal-pi1442-flush-excerpt.txt |
| 14:49:56 to 14:52:43 | The imac-pi and imac-claude flushes were fine; LLM calls took 2 to 7s | journal, magpie |

## Root cause
- The upstream codex/gpt-6.1-sol route (via magpie, chatgpt.com account) stalled. It returned no tokens for 60s, three times in a row.
- EverOS 1.4.2 runs episode extraction **synchronously inside /flush**. The LLM timeout is 60s and the OpenAI SDK default is max_retries=2, so the worst case is 3 × 60s ≈ 182s. That is longer than Cloudflare's 100s proxy limit.
- `_extract_with_retry` retries only on ValueError, so the timeout became a 500.
- The network was not the cause. Magpie received every attempt within milliseconds (14:42:53.667), and the tailnet path is direct.
- The memcell is written **before** extraction, and nothing re-runs it on failure. That leaves an orphan memcell, an empty buffer, and no episode, atomic_fact or profile.

Recurrence: magpie shows 21 EverOS calls with status 499 since 10-15. Today there were 19 out of 133: 00:15 to 00:18, 03:00 to 03:09, 03:43 to 03:44, and 14:42 to 14:44. The earlier ones were background OME jobs, which retry on their own. This is the first one on the synchronous flush path. For successful calls, p95 = 41s and p99 = 55s, so a 60s deadline leaves little headroom.

## Late success? No.
- `grep` for the session finds nothing in `deepvision/` md files or in lancedb.
- The only rows are: `memcell` (1), `conversation_status` (1), and ome `run_record` extract_agent_case (success/skip).
- `unprocessed_buffer` has 0 rows for this session.

## Ingress correction
There is **no Cloudflare Tunnel or cloudflared** on site. everos.deepvision.sg is a Cloudflare-proxied DNS record (Flexible SSL). It goes to host nginx :80 (`/etc/nginx/sites-enabled/everos.conf`, `proxy_read_timeout 400s`) and then to 127.0.0.1:8000. The 100s limit is Cloudflare's own proxy timeout, which can only be changed on Enterprise plans. nginx was not the limit.

## Health (15:02 SGT)
- /health is ok, both locally and through Cloudflare.
- Cascade is healthy with 0 pending.
- NRestarts = 0.
- Magpie answers from site with 401 on unauthenticated `/v1/models` in about 0.19s.
- Tailnet site→imac is direct (165.173.24.76:41641); pings were 8 to 98ms.
- The last real LLM calls at 14:52 were fine.
- Memory: about 413 MB used, against MemoryHigh 500M / Max 700M. The host has 957 MB RAM and about 235 MB available.

## Retry verdict
- **A plain re-flush does nothing.** The buffer is empty, so it returns `no_extraction`.
- **Recovery is safe now:** re-send the same `/add` (same 2 messages, **same timestamps**, which gives the same message_ids), then `/flush`. No episode or fact landed, so this won't create duplicates. The orphan memcell `mc_5a7ba609a7c2` stays in system.db; it's only cosmetic.
- Try once. If it returns 524 again, do not retry blind. First check `episodes/episode-2026-10-17.md` for FDV-68-acceptance-box-pi-1442, because a later, longer call could finish after Cloudflare gives up.

## Proposals (none applied)
1. **Clients:** treat 524 as "unknown". Verify with get/search. If nothing is there, re-add with the same timestamps and flush once.
2. **Avoid Cloudflare's 100s for flush:** let the MCP or ingest client reach nginx over the tailnet (site 100.64.0.5:80, Host everos.deepvision.sg; nginx allows 400s). This is a new access path, so it needs Zack's approval.
3. **Magpie:** add a fallback model or route for the EverOS caller key when codex first-byte takes more than about 20 to 30s, or investigate the codex stalls.
4. **EverOS config:** `EVEROS_LLM__TIMEOUT_SECONDS` is the only option; the SDK retry count for the main LLM is not configurable in 1.4.2. Setting it to about 28s would keep 3 attempts under 100s, but it would break the slower background calls (p95 41s). Not recommended alone.
5. **Async flush:** not available in 1.4.2; flush is synchronous. The no-upgrade constraint stands.
6. Side note: /etc/everos/everos.env is mode 640 root:everos. The brief said 600, but the file header says it is meant to be 640.

## Files
- `everos-journal-0635-0658Z.txt`: full EverOS journal for 06:35 to 06:58Z, including tracebacks
- `everos-journal-pi1442-flush-excerpt.txt`: the failing flush only, without tracebacks
- `everos-llm-retries-since-start.txt`: all LLM retries and unhandled errors since 10-15 19:39Z
- `magpie-usage-1430-1459SGT.txt`: magpie usage records, plus 499 history and latency stats. Emails and caller keys removed.
- `nginx-access-0635-0658Z.txt`
- `sqlite-session-state.txt`: rows for the session from a /tmp copy of system.db and ome.db. The copy was deleted afterwards.
- `health-snapshot.txt`, `code-refs-everos-1.4.2.txt`
