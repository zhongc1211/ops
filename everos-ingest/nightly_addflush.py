#!/usr/bin/env python3
"""心月夜审 75b324a4 step 2: sessions jsonl -> /memory/add -> /memory/flush.

Usage: python3 -I nightly_addflush.py --date 2026-10-16 [--project P] [--dry-run | --readback-only] --log OUT.json
                                      [--ledger L.jsonl] [--sessions-dir DIR]
Reads ~/.config/everos/xinyue.env; the key goes only into the Authorization header.
--project deepvision-ads | vllm-omni (2026-10-18) does the same for that project's capture
(/var/lib/everos-ingest/<project>/<date>/, env dv-ads.env / vllm-omni.env, ledger <date>-<project>-ledger.jsonl)
for the ads (9b5c20e7) and vllm (c392a743) night reviews; the env's scope must be the 10-16 one.
Only user/assistant text blocks are sent (no tool calls/results); messages that look
like they carry a secret are dropped and counted.

Endpoint: every call goes to the tailnet path first (EVEROS_TAILNET_URL, default
http://100.64.0.5, with Host: <host of EVEROS_BASE_URL>; nginx there allows 400s and there is
no Cloudflare 100s limit). Only when connecting fails (refused/unreachable/connect timeout, so
the request was certainly not sent) does the call go to the public EVEROS_BASE_URL; the ledger
line then has endpoint=public and fallback=<reason>. EVEROS_TAILNET_URL= (empty) means public only.

Result unknown: add or flush that gets 502/504/524, a read timeout or a connection dropped after
the request was sent may or may not have landed. EverOS's indexes lag: on 2026-10-17 a flush that
answered 200 extracted showed 0 episodes for its session_id ~1s later and 1 after ~18s. So the
script does not decide at once; it rechecks after RECHECK_DELAYS (5, 15, 30, 60 s, waiting before
each recheck). Each recheck reads three things:
  - /memory/get episode with filters.session_id: more than before this session's first add = extracted;
  - /memory/search with filters.session_id: the unflushed buffer; for an add, the chunk's last
    timestamp in it = buffered;
  - /memory/get episode without filter: total_count, compared with the total before this session.
The first recheck that shows extracted (or, for an add, buffered) ends the rechecks: landed, no resend.
If all four come back without that:
  add:   nothing found -> resend that chunk once, same timestamps;
  flush: still buffered -> flush once (no re-add); nothing found -> re-add every chunk once (same
         timestamps), then flush once;
  total_count went up but nothing for this session -> failed, no resend (see recheck());
  no recheck got a full answer (any of the three reads not 200) -> failed, no resend.
Each session gets at most one resend round. A later unknown is only rechecked (landed or failed).
A failed outcome stops that session.

Ledger (default ~/xinyue-deploy/nightly-review/<date>-<project>-ledger.jsonl, xinyue by default): one JSON line per call,
appended and flushed right after the call returns (an unknown add/flush line is written once its
rechecks are done, after the recheck lines). kind=count_before / count_after are /memory/get episode
counts (total_count + id list) taken before the first write and after the last; kind=session_before
has session_hits (that session's episodes) and total_before (all of the user's) before its first add; kind=add / flush
carry session_id, HTTP status, request_id and the non-text fields of the response data.
kind=recheck is one line per recheck (session_id, call, attempt, delay_s, session_hits, buffered,
buffered_match, total_count, total_before, endpoint, http, http_detail); kind=recheck_decision ends
them with decision landed / resend / failed, the state behind it and a reason when failed.
Every call line has endpoint (tailnet/public) and outcome (ok / unknown→landed / unknown→resent /
failed); resent calls have resend=true. No key, no message text. --dry-run still takes both
counts (read-only) and marks every line dry_run=true.

Read back (PER-67, everos_readback.py): HTTP 200 is not success. After count_after every OK session is
read back by session_id under the env's scope, polled up to everos_readback.READBACK_TIMEOUT_S (180 s);
it must have more episodes than its session_before count. A session that does not pass becomes
result=FAIL with reason "readback_failed: <why>", the ledger gets kind=readback / readback_summary lines,
and the script exits 3 (otherwise 0, as before).
--readback-only sends no add/flush: every session that would be written (readable transcript with text
messages) is read back, needing at least one episode. --sessions-dir reads sessions-<side>.jsonl from
another directory (default /var/lib/everos-ingest/<project>/<date>).
EVEROS_WRITE_STUB_URL (drill only): add and flush go to this address and nowhere else (no fallback);
every other call goes to EverOS as usual. Used with a local server that answers 200 to prove that a
200 write which EverOS never saw ends in readback_failed.
"""
import argparse, http.client, json, os, re, sys, time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))   # python3 -I leaves the script's directory out
import everos_readback

SGT = timezone(timedelta(hours=8))
# --project -> (env file, expected app / project / user / assistant sender); ID 10-16 批, Zack 10-18 13:18
PROJECTS = {
    "xinyue": ("~/.config/everos/xinyue.env", ("xinyue", "xinyue-site", "zack", "coding-xinyue-site")),
    "deepvision-ads": ("~/.config/everos/dv-ads.env", ("deepvision", "deepvision-ads", "zack", "coding-deepvision-ads")),
    "vllm-omni": ("~/.config/everos/vllm-omni.env", ("vllm-omni", "vllm-omni", "zack", "coding-vllm-omni")),
}

def load_env(p):
    env = {}
    for line in Path(p).expanduser().read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env

SECRET_RES = [re.compile(p) for p in (
    r"Bearer\s+[A-Za-z0-9._\-]{20,}", r"\bsk-[A-Za-z0-9_\-]{16,}", r"\bgh[pousr]_[A-Za-z0-9]{20,}",
    r"\bcfut_[A-Za-z0-9]{20,}", r"\bAKIA[0-9A-Z]{16}\b", r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"\bxox[abpr]-[A-Za-z0-9-]{10,}", r"(?i)(api[_-]?key|secret|password|token)\s*[=:]\s*['\"]?[A-Za-z0-9._\-]{24,}",
)]
MAX_CHARS = 4000
CHUNK = 100
TAILNET_DEFAULT = "http://100.64.0.5"
CONNECT_TIMEOUT = 10
TIMEOUT = 420          # nginx on the tailnet path gives EverOS 400s
UNKNOWN_HTTP = {502, 504, 524}   # gateway gave up after forwarding: EverOS may have done the work
RECHECK_DELAYS = (5, 15, 30, 60)   # seconds to wait before each recheck of an unknown result
LANDED = "unknown→landed"
RESENT = "unknown→resent"
OUTCOME_OF_DECISION = {"landed": LANDED, "resend": RESENT}   # recheck decision -> add/flush outcome; else failed
WRITE_PATHS = ("/api/v2/memory/add", "/api/v2/memory/flush")   # the calls EVEROS_WRITE_STUB_URL takes over

def ts_ms(s):
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() * 1000)
    except Exception:
        return None

def transcript_messages(path, env, key):
    msgs, dropped = [], 0
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") not in ("user", "assistant") or o.get("isSidechain") or o.get("isMeta"):
            continue
        m = o.get("message") or {}
        role = m.get("role")
        c = m.get("content")
        if isinstance(c, str):
            text = c
        elif isinstance(c, list):
            text = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
        else:
            text = ""
        text = text.strip()
        if not text or role not in ("user", "assistant"):
            continue
        if text.startswith("<system-reminder>") or text.startswith("<command-") or text.startswith("<local-command"):
            continue
        if (key and key in text) or any(r.search(text) for r in SECRET_RES):
            dropped += 1
            continue
        if len(text) > MAX_CHARS:
            text = text[:MAX_CHARS] + " …[truncated]"
        t = ts_ms(o.get("timestamp", "")) or int(time.time() * 1000)
        msgs.append({
            "sender_id": env["EVEROS_USER_ID"] if role == "user" else env["EVEROS_ASSISTANT_SENDER_ID"],
            "sender_name": "User" if role == "user" else "Assistant",
            "role": role, "timestamp": t, "content": text,
        })
    # strictly increasing timestamps
    last = 0
    for m in msgs:
        if m["timestamp"] <= last:
            m["timestamp"] = last + 1
        last = m["timestamp"]
    return msgs, dropped

def endpoints(env):
    """[(name, base url, Host header or None)], tailnet first."""
    tail = os.environ.get("EVEROS_TAILNET_URL", env.get("EVEROS_TAILNET_URL", TAILNET_DEFAULT)).strip()
    eps = [("tailnet", tail, urlsplit(env["EVEROS_BASE_URL"]).hostname)] if tail else []
    return eps + [("public", env["EVEROS_BASE_URL"], None)]

class ConnectFailed(Exception):
    pass

def send(base, host, path, data, headers, timeout=TIMEOUT):
    u = urlsplit(base)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    conn = cls(u.hostname, u.port, timeout=CONNECT_TIMEOUT)
    try:
        try:
            conn.connect()          # TCP (+TLS); nothing of the request has been sent yet
        except OSError as e:
            raise ConnectFailed(f"{type(e).__name__}: {e}"[:200])
        conn.sock.settimeout(timeout)
        h = dict(headers, Host=host) if host else headers
        conn.request("POST", u.path.rstrip("/") + path, body=data, headers=h)
        r = conn.getresponse()
        return r.status, r.read()
    finally:
        conn.close()

class Resp:
    def __init__(self, http, body, endpoint, outcome, fallback=None):
        self.http, self.body, self.endpoint, self.outcome, self.fallback = http, body, endpoint, outcome, fallback

    @property
    def data(self):
        d = self.body.get("data")
        return d if isinstance(d, dict) else {}

    def fields(self):
        f = {"http": self.http, "endpoint": self.endpoint, "outcome": self.outcome, "request_id": self.body.get("request_id")}
        if self.fallback:
            f["fallback"] = self.fallback
        return f

def post(env, path, body, timeout=TIMEOUT):
    """timeout: read timeout once connected (the read back passes a shorter one)."""
    data = json.dumps(body).encode()
    headers = {"Authorization": "Bearer " + env["EVEROS_API_KEY"], "Content-Type": "application/json",
               # Cloudflare answers the default Python-urllib UA with 403 (error 1010)
               "User-Agent": "xinyue-nightly-addflush/1.1"}
    fallback = None
    eps = env.get("_write_endpoints") if path in WRITE_PATHS else None
    for name, base, host in eps or env["_endpoints"]:
        try:
            st, raw = send(base, host, path, data, headers, timeout)
        except ConnectFailed as e:
            fallback = f"{name} connect failed: {e}"
            continue
        except (OSError, http.client.HTTPException) as e:
            # the request went out and the answer never came back: result unknown
            return Resp(None, {"error": {"code": type(e).__name__, "message": str(e)[:200]}}, name, "unknown", fallback)
        try:
            parsed = json.loads(raw or b"{}")
        except Exception:
            parsed = {}
        parsed = parsed if isinstance(parsed, dict) else {}
        outcome = "ok" if st == 200 else "unknown" if st in UNKNOWN_HTTP else "failed"
        return Resp(st, parsed, name, outcome, fallback)
    # no endpoint could be connected to: nothing was sent
    return Resp(None, {"error": {"code": "ConnectFailed", "message": fallback}}, None, "failed", fallback)

# response fields that hold message/episode text; never copied into the ledger
TEXT_FIELDS = {"content", "messages", "episode", "summary", "subject", "text", "memory", "memories"}

def brief(v, depth=0):
    """Non-text parts of a response: ids, statuses, counts. Long strings are cut."""
    if isinstance(v, dict):
        if depth > 2:
            return "{…}"
        return {k: brief(x, depth + 1) for k, x in v.items() if k not in TEXT_FIELDS}
    if isinstance(v, list):
        if v and all(isinstance(x, dict) for x in v):
            ids = [x.get("id") for x in v if x.get("id") is not None]
            return {"n": len(v), "ids": ids[:200]} if ids else {"n": len(v)}
        return [brief(x, depth + 1) for x in v[:200]]
    if isinstance(v, str) and len(v) > 160:
        return v[:160] + "…"
    return v

class Ledger:
    def __init__(self, path, key, dry):
        self.path, self.key, self.dry = Path(path).expanduser(), key, dry
        self.run = datetime.now(SGT).isoformat(timespec="seconds")
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def write(self, kind, **fields):
        rec = {"time": datetime.now(SGT).isoformat(timespec="seconds"), "run": self.run, "kind": kind, **fields}
        if self.dry:
            rec["dry_run"] = True
        line = json.dumps(rec, ensure_ascii=False)
        if (self.key and self.key in line) or any(r.search(line) for r in SECRET_RES):
            rec = {k: rec[k] for k in ("time", "run", "kind", "session_id", "http", "endpoint", "outcome",
                                       "request_id", "dry_run") if k in rec}
            rec["redacted"] = True
            line = json.dumps(rec, ensure_ascii=False)
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
        return rec

def get_episodes(env, **extra):
    return post(env, "/api/v2/memory/get", {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"],
                                             "user_id": env["EVEROS_USER_ID"], "memory_type": "episode", **extra})

def episode_count(env, ledger, kind):
    """/memory/get episode for the user (agent_id + episode is a 422) -> ledger line."""
    r = get_episodes(env)
    data = r.data
    eps = data.get("episodes") or []
    rec = ledger.write(kind, **r.fields(), total_count=data.get("total_count"),
                       count=data.get("count"), episode_ids=[e.get("id") for e in eps if isinstance(e, dict)],
                       error=(r.body.get("error") or {}).get("code") if isinstance(r.body.get("error"), dict) else None)
    print(f"{kind}: endpoint={r.endpoint} http={r.http} total_count={rec.get('total_count')} count={rec.get('count')}", flush=True)
    return rec

def first_bad_http(*resps):
    return next((r.http for r in resps if r.http != 200), 200)

def session_counts(env, sid):
    """(this session's episode count, overall episode total, Resp, Resp); a count is None when its get was not 200."""
    rs = get_episodes(env, filters={"session_id": sid}, page_size=1)
    rt = get_episodes(env, page_size=1)
    count = lambda r: r.data.get("total_count") if r.http == 200 else None
    return count(rs), count(rt), rs, rt

def buffered_ts(env, sid):
    """(timestamps in ms of this session's messages still in the unflushed buffer or None, count, Resp)."""
    r = post(env, "/api/v2/memory/search", {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"],
                                             "user_id": env["EVEROS_USER_ID"], "query": sid, "method": "keyword",
                                             "top_k": 1, "filters": {"session_id": sid}})
    msgs = r.data.get("unprocessed_messages") or []
    if r.http != 200:
        return None, None, r
    ts = set()
    for m in msgs:
        try:
            ts.add(round(datetime.fromisoformat(str(m.get("timestamp")).replace("Z", "+00:00")).timestamp() * 1000))
        except Exception:
            pass
    return ts, len(msgs), r

def recheck(env, ledger, sid, call, ep_before, total_before, last_ts, can_resend):
    """Recheck an unknown add/flush after each of RECHECK_DELAYS. -> (decision, state).

    decision: landed / resend / failed. state: extracted / buffered / absent / total_up_session_missing
    / unreadable. Writes one kind=recheck line per attempt and one kind=recheck_decision line.
    Without a readable count from before this session's first add nothing can be compared: failed at
    once, without waiting.

    total_count up but nothing under this session_id: the script writes sessions one after another and,
    between this session's session_before and now, sent only this session's add/flush. So within this
    script the rise can only be this session, and the session_id index may simply be behind; that is
    why the rechecks keep going instead of resending. But MCP sessions also write this app/project/
    user, so the rise alone does not prove it landed. If it is still the only sign after the last
    recheck: failed, no resend. A duplicate would sit in memory unnoticed, a failed session is
    reported by the night review and can be written by hand.
    """
    state, landed = "unreadable", False
    for attempt, delay in enumerate(RECHECK_DELAYS if ep_before is not None and total_before is not None else (), 1):
        time.sleep(delay)
        n, total, rs, rt = session_counts(env, sid)
        ts, nbuf, rb = buffered_ts(env, sid)
        resps = {"episodes": rs, "buffer": rb, "total": rt}
        match = bool(ts) and last_ts is not None and any(abs(t - last_ts) <= 1 for t in ts)
        eps = sorted({r.endpoint or "none" for r in resps.values()})
        ledger.write("recheck", session_id=sid, call=call, attempt=attempt, delay_s=delay, session_hits=n,
                     ep_before=ep_before, buffered=nbuf, buffered_match=match, total_count=total,
                     total_before=total_before, endpoint=",".join(eps), http=first_bad_http(*resps.values()),
                     http_detail={k: r.http for k, r in resps.items()})
        if first_bad_http(*resps.values()) != 200 or n is None or total is None:
            continue
        if n > ep_before:
            state, landed = "extracted", True; break
        if call == "add" and match:
            state, landed = "buffered", True; break
        state = ("total_up_session_missing" if total > total_before
                 else "buffered" if nbuf and call == "flush" else "absent")
    if landed:
        decision, reason = "landed", None
    elif state in ("absent", "buffered") and can_resend:
        decision, reason = "resend", None
    else:
        decision = "failed"
        reason = state if state in ("unreadable", "total_up_session_missing") else "not landed, resend already used"
    ledger.write("recheck_decision", session_id=sid, call=call, decision=decision, state=state,
                 **({"reason": reason} if reason else {}))
    return decision, state

def call_fields(r):
    data = r.data
    err = r.body.get("error") if isinstance(r.body.get("error"), dict) else {}
    return {"http": r.http, "endpoint": r.endpoint, "outcome": r.outcome, "status": data.get("status"),
            "request_id": r.body.get("request_id"), "error": err.get("code"), "message": err.get("message")}

def write_session(env, ledger, scope, o, msgs):
    """add every chunk, then flush, with the result-unknown rule. -> (adds, flush, ok)."""
    sid, side = o["session_id"], o.get("side")
    chunks = [msgs[i:i + CHUNK] for i in range(0, len(msgs), CHUNK)]
    ep_before, total_before, rs, rt = session_counts(env, sid)
    o["episodes_before"] = ep_before   # the read back needs more than this
    http = first_bad_http(rs, rt)
    ledger.write("session_before", session_id=sid, session_hits=ep_before, total_before=total_before,
                 http=http, endpoint=rs.endpoint, outcome="ok" if http == 200 else "failed")
    adds, resent = [], False

    def add(ci, resend=False):
        chunk = chunks[ci]
        r = post(env, "/api/v2/memory/add", {**scope, "session_id": sid, "messages": chunk, "async_mode": False})
        line = dict(session_id=sid, machine=side, chunk=ci, messages=len(chunk),
                    first_ts=chunk[0]["timestamp"], last_ts=chunk[-1]["timestamp"])
        if resend:
            line["resend"] = True
        return r, line

    def record(kind, r, line):
        ledger.write(kind, **line, **r.fields(), data=brief(r.body.get("data")), error=brief(r.body.get("error")))
        f = call_fields(r)
        if line.get("resend"):
            f["resend"] = True
        if kind == "add":
            adds.append(f)
        return f

    def settle(kind, r, line, last_ts):
        decision, _ = recheck(env, ledger, sid, kind, ep_before, total_before, last_ts, can_resend=False)
        r.outcome = OUTCOME_OF_DECISION.get(decision, "failed")
        return record(kind, r, line)

    def send_or_settle(kind, r, line, last_ts):
        return settle(kind, r, line, last_ts) if r.outcome == "unknown" else record(kind, r, line)

    for ci in range(len(chunks)):
        r, line = add(ci)
        last_ts = chunks[ci][-1]["timestamp"]
        if r.outcome != "unknown" or resent:
            send_or_settle("add", r, line, last_ts)
            if r.outcome == "failed":
                return adds, None, False
            continue
        decision, _ = recheck(env, ledger, sid, "add", ep_before, total_before, last_ts, can_resend=True)
        r.outcome = OUTCOME_OF_DECISION.get(decision, "failed")
        record("add", r, line)
        if r.outcome == "failed":
            return adds, None, False
        if r.outcome == RESENT:
            resent = True
            r2, line2 = add(ci, resend=True)
            send_or_settle("add", r2, line2, last_ts)
            if r2.outcome == "failed":
                return adds, None, False

    fline = dict(session_id=sid, machine=side)
    last_ts = chunks[-1][-1]["timestamp"]
    r = post(env, "/api/v2/memory/flush", {**scope, "session_id": sid})
    if r.outcome != "unknown" or resent:
        f = send_or_settle("flush", r, fline, last_ts)
        return adds, f, r.outcome not in ("failed", "unknown")
    decision, st = recheck(env, ledger, sid, "flush", ep_before, total_before, last_ts, can_resend=True)
    r.outcome = OUTCOME_OF_DECISION.get(decision, "failed")
    f = record("flush", r, fline)
    if r.outcome != RESENT:
        return adds, f, r.outcome == LANDED
    if st == "absent":
        for ci in range(len(chunks)):
            r2, line2 = add(ci, resend=True)
            send_or_settle("add", r2, line2, chunks[ci][-1]["timestamp"])
            if r2.outcome == "failed":
                return adds, f, False
    r3 = post(env, "/api/v2/memory/flush", {**scope, "session_id": sid})
    f3 = send_or_settle("flush", r3, dict(fline, resend=True), last_ts)
    return adds, f3, r3.outcome not in ("failed", "unknown")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", required=True)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--readback-only", action="store_true", help="no add/flush: read back the sessions only")
    ap.add_argument("--sessions-dir", help="default /var/lib/everos-ingest/<project>/<date>")
    ap.add_argument("--log", required=True)
    ap.add_argument("--ledger", help="write ledger jsonl (default ~/xinyue-deploy/nightly-review/<date>-<project>-ledger.jsonl)")
    ap.add_argument("--project", default="xinyue", choices=sorted(PROJECTS))
    a = ap.parse_args()
    env_path, scope_want = PROJECTS[a.project]
    env = load_env(env_path)
    if tuple(env.get(k) for k in ("EVEROS_APP_ID", "EVEROS_PROJECT_ID", "EVEROS_USER_ID", "EVEROS_ASSISTANT_SENDER_ID")) != scope_want:
        sys.exit("scope mismatch in " + env_path)
    env["_endpoints"] = endpoints(env)
    if os.environ.get("EVEROS_WRITE_STUB_URL"):
        env["_write_endpoints"] = [("write-stub", os.environ["EVEROS_WRITE_STUB_URL"], None)]
        print(f"WRITE STUB: add/flush go to {os.environ['EVEROS_WRITE_STUB_URL']} only (drill)", flush=True)
    key = env.get("EVEROS_API_KEY", "")
    scope = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"]}
    ledger = Ledger(a.ledger or f"~/xinyue-deploy/nightly-review/{a.date}-{a.project}-ledger.jsonl", key, a.dry_run)
    print(f"ledger: {ledger.path}", flush=True)
    print("endpoints: " + " -> ".join(f"{n} {u}" for n, u, _ in env["_endpoints"]), flush=True)
    before = episode_count(env, ledger, "count_before")
    base = Path(a.sessions_dir or f"/var/lib/everos-ingest/{a.project}/{a.date}")
    rows, seen = [], set()
    for side in ("box", "imac", "mba"):
        f = base / f"sessions-{side}.jsonl"
        if not f.is_file():
            # MBA joined 2026-10-18: a missing MBA list is reported but is not a failure
            rows.append({"side": side, ("warn" if side == "mba" else "error"): f"missing {f}"}); continue
        for line in f.read_text().splitlines():
            if not line.strip():
                continue
            o = json.loads(line)
            if o["session_id"] in seen:
                continue
            seen.add(o["session_id"]); o["side"] = side; rows.append(o)
    log = []
    for o in rows:
        rec = {"session_id": o.get("session_id"), "machine": o.get("side"), "workspace": o.get("workspace")}
        o["rec"] = rec
        if "error" in o:
            rec["result"] = "FAIL"; rec["reason"] = o["error"]; log.append(rec); continue
        if "warn" in o:
            rec["result"] = "WARN"; rec["reason"] = o["warn"]; log.append(rec); continue
        tp = o.get("transcript_path")
        if not tp or not os.access(tp, os.R_OK):
            rec["result"] = "FAIL"; rec["reason"] = f"transcript not readable on box: {tp}"; log.append(rec); continue
        msgs, dropped = transcript_messages(tp, env, key)
        rec.update(messages=len(msgs), dropped_secretlike=dropped)
        if not msgs:
            rec["result"] = "SKIP"; rec["reason"] = "no text messages"; log.append(rec); continue
        if a.dry_run:
            rec["result"] = "DRY"; log.append(rec); continue
        if a.readback_only:
            rec["result"] = "OK"; rec["readback_only"] = True; log.append(rec); continue
        adds, flush, ok = write_session(env, ledger, scope, o, msgs)
        rec["add"] = adds
        rec["flush"] = flush
        rec["result"] = "OK" if ok else "FAIL"
        if not ok and flush is None:
            rec["reason"] = "add failed; session stopped before flush"
        log.append(rec)
        print(json.dumps(rec, ensure_ascii=False), flush=True)
    after = episode_count(env, ledger, "count_after")
    new_ids = sorted(set(after.get("episode_ids", [])) - set(before.get("episode_ids", [])))
    written = [o for o in rows if o.get("rec", {}).get("result") == "OK"]
    results = everos_readback.readback(
        env, post, [everos_readback.episode_target(o["session_id"], o.get("episodes_before")) for o in written],
        a.project, ledger) if written and not a.dry_run else []
    for o, res in zip(written, results):
        o["rec"]["readback"] = {k: res.get(k) for k in ("result", "reason", "count", "before", "polls", "seconds", "found")}
        if res["result"] != "PASS":
            o["rec"]["result"], o["rec"]["reason"] = "FAIL", everos_readback.failure_reason(res)
    readback_failed = everos_readback.failed(results)
    ledger.write("summary", sessions=len(log), ok=sum(r["result"] == "OK" for r in log),
                 fail=sum(r["result"] == "FAIL" for r in log), new_episode_ids=new_ids,
                 readback_failed=len(readback_failed))
    Path(a.log).write_text(json.dumps(log, ensure_ascii=False, indent=1))
    for r in log:
        print(r["result"], r["machine"], r["session_id"], r.get("messages"), r.get("reason", ""))
    print(f"episodes before={before.get('total_count')} after={after.get('total_count')} new={new_ids}")
    if readback_failed:
        print(f"readback_failed: {len(readback_failed)} session(s), see the readback_failed lines above", flush=True)
        return everos_readback.EXIT_READBACK_FAILED
    return 0

if __name__ == "__main__":
    sys.exit(main())
