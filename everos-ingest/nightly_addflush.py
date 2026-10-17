#!/usr/bin/env python3
"""心月夜审 75b324a4 step 2: sessions jsonl -> /memory/add -> /memory/flush.

Usage: python3 -I nightly_addflush.py --date 2026-10-16 [--dry-run] --log OUT.json [--ledger L.jsonl]
Reads ~/.config/everos/xinyue.env; the key goes only into the Authorization header.
Only user/assistant text blocks are sent (no tool calls/results); messages that look
like they carry a secret are dropped and counted.

Endpoint: every call goes to the tailnet path first (EVEROS_TAILNET_URL, default
http://100.64.0.5, with Host: <host of EVEROS_BASE_URL>; nginx there allows 400s and there is
no Cloudflare 100s limit). Only when connecting fails (refused/unreachable/connect timeout, so
the request was certainly not sent) does the call go to the public EVEROS_BASE_URL; the ledger
line then has endpoint=public and fallback=<reason>. EVEROS_TAILNET_URL= (empty) means public only.

Result unknown: add or flush that gets 502/504/524, a read timeout or a connection dropped after
the request was sent may or may not have landed. The script then checks this session:
/memory/get episode with filters.session_id (extracted) and /memory/search with
filters.session_id (unflushed buffer, matched on the chunk's last timestamp).
  add unknown:   landed -> no resend; not landed -> resend that chunk once, same timestamps.
  flush unknown: extracted -> done; still buffered -> flush once; neither -> resend every chunk
                 once (same timestamps), then flush once.
Each session gets at most one resend round. Any later unknown is only checked (landed or
failed), a failed outcome stops that session.

Ledger (default ~/xinyue-deploy/nightly-review/<date>-xinyue-ledger.jsonl): one JSON line per call,
appended and flushed right after the call returns (an unknown add/flush line is written once its
check is done, after the check lines). kind=count_before / count_after are /memory/get episode
counts (total_count + id list) taken before the first write and after the last; kind=session_before
is that session's episode count before its first add; kind=add / flush carry session_id, HTTP
status, request_id and the non-text fields of the response data; kind=check is a landed check.
Every call line has endpoint (tailnet/public) and outcome (ok / unknown→landed / unknown→resent /
failed); resent calls have resend=true. No key, no message text. --dry-run still takes both
counts (read-only) and marks every line dry_run=true.
"""
import argparse, http.client, json, os, re, sys, time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

SGT = timezone(timedelta(hours=8))

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
LANDED = "unknown→landed"
RESENT = "unknown→resent"

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

def send(base, host, path, data, headers):
    u = urlsplit(base)
    cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
    conn = cls(u.hostname, u.port, timeout=CONNECT_TIMEOUT)
    try:
        try:
            conn.connect()          # TCP (+TLS); nothing of the request has been sent yet
        except OSError as e:
            raise ConnectFailed(f"{type(e).__name__}: {e}"[:200])
        conn.sock.settimeout(TIMEOUT)
        h = dict(headers, Host=host) if host else headers
        conn.request("POST", u.path.rstrip("/") + path, body=data, headers=h)
        r = conn.getresponse()
        return r.status, r.read()
    finally:
        conn.close()

class Resp:
    def __init__(self, http, body, endpoint, outcome, fallback=None):
        self.http, self.body, self.endpoint, self.outcome, self.fallback = http, body, endpoint, outcome, fallback

    def fields(self):
        f = {"http": self.http, "endpoint": self.endpoint, "outcome": self.outcome, "request_id": self.body.get("request_id")}
        if self.fallback:
            f["fallback"] = self.fallback
        return f

def post(env, path, body):
    data = json.dumps(body).encode()
    headers = {"Authorization": "Bearer " + env["EVEROS_API_KEY"], "Content-Type": "application/json",
               # Cloudflare answers the default Python-urllib UA with 403 (error 1010)
               "User-Agent": "xinyue-nightly-addflush/1.1"}
    fallback = None
    for name, base, host in env["_endpoints"]:
        try:
            st, raw = send(base, host, path, data, headers)
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
    data = r.body.get("data") if isinstance(r.body.get("data"), dict) else {}
    eps = data.get("episodes") or []
    rec = ledger.write(kind, **r.fields(), total_count=data.get("total_count"),
                       count=data.get("count"), episode_ids=[e.get("id") for e in eps if isinstance(e, dict)],
                       error=(r.body.get("error") or {}).get("code") if isinstance(r.body.get("error"), dict) else None)
    print(f"{kind}: endpoint={r.endpoint} http={r.http} total_count={rec.get('total_count')} count={rec.get('count')}", flush=True)
    return rec

def session_episodes(env, ledger, kind, sid):
    """This session's extracted episode count, or None when the get did not answer 200."""
    r = get_episodes(env, filters={"session_id": sid}, page_size=1)
    data = r.body.get("data") if isinstance(r.body.get("data"), dict) else {}
    n = data.get("total_count") if r.http == 200 else None
    ledger.write(kind, session_id=sid, what="episodes", **r.fields(), total_count=n, error=brief(r.body.get("error")))
    return n

def buffered_ts(env, ledger, sid):
    """Timestamps (ms) of this session's messages still in EverOS's unflushed buffer, or None."""
    r = post(env, "/api/v2/memory/search", {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"],
                                             "user_id": env["EVEROS_USER_ID"], "query": sid, "method": "keyword",
                                             "top_k": 1, "filters": {"session_id": sid}})
    data = r.body.get("data") if isinstance(r.body.get("data"), dict) else {}
    msgs = data.get("unprocessed_messages") or []
    ts = None
    if r.http == 200:
        ts = set()
        for m in msgs:
            try:
                ts.add(round(datetime.fromisoformat(str(m.get("timestamp")).replace("Z", "+00:00")).timestamp() * 1000))
            except Exception:
                pass
    ledger.write("check", session_id=sid, what="buffer", **r.fields(), buffered=len(msgs), error=brief(r.body.get("error")))
    return ts

def landed_state(env, ledger, sid, ep_before, last_ts):
    """extracted / buffered / absent, or None when a check call failed."""
    n = session_episodes(env, ledger, "check", sid)
    ts = buffered_ts(env, ledger, sid)
    if n is None or ts is None or ep_before is None:
        return None
    if n > ep_before:
        return "extracted"
    if last_ts is not None and any(abs(t - last_ts) <= 1 for t in ts):
        return "buffered"
    return "absent"

def call_fields(r):
    data = r.body.get("data") if isinstance(r.body.get("data"), dict) else {}
    err = r.body.get("error") if isinstance(r.body.get("error"), dict) else {}
    return {"http": r.http, "endpoint": r.endpoint, "outcome": r.outcome, "status": data.get("status"),
            "request_id": r.body.get("request_id"), "error": err.get("code"), "message": err.get("message")}

def write_session(env, ledger, scope, o, msgs):
    """add every chunk, then flush, with the result-unknown rule. -> (adds, flush, ok)."""
    sid, side = o["session_id"], o.get("side")
    chunks = [msgs[i:i + CHUNK] for i in range(0, len(msgs), CHUNK)]
    ep_before = session_episodes(env, ledger, "session_before", sid)
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
        """An unknown with the resend already used: check only, set r.outcome and record."""
        st = landed_state(env, ledger, sid, ep_before, last_ts)
        landed = st == "extracted" if kind == "flush" else st in ("extracted", "buffered")
        r.outcome = LANDED if landed else "failed"
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
        st = landed_state(env, ledger, sid, ep_before, last_ts)
        r.outcome = LANDED if st in ("extracted", "buffered") else "failed" if st is None else RESENT
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
    st = landed_state(env, ledger, sid, ep_before, last_ts)
    r.outcome = LANDED if st == "extracted" else "failed" if st is None else RESENT
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
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--log", required=True)
    ap.add_argument("--ledger", help="write ledger jsonl (default ~/xinyue-deploy/nightly-review/<date>-xinyue-ledger.jsonl)")
    a = ap.parse_args()
    env = load_env("~/.config/everos/xinyue.env")
    env["_endpoints"] = endpoints(env)
    key = env.get("EVEROS_API_KEY", "")
    scope = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"]}
    ledger = Ledger(a.ledger or f"~/xinyue-deploy/nightly-review/{a.date}-xinyue-ledger.jsonl", key, a.dry_run)
    print(f"ledger: {ledger.path}", flush=True)
    print("endpoints: " + " -> ".join(f"{n} {u}" for n, u, _ in env["_endpoints"]), flush=True)
    before = episode_count(env, ledger, "count_before")
    base = Path(f"/var/lib/everos-ingest/xinyue/{a.date}")
    rows, seen = [], set()
    for side in ("box", "imac"):
        f = base / f"sessions-{side}.jsonl"
        if not f.is_file():
            rows.append({"side": side, "error": f"missing {f}"}); continue
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
        if "error" in o:
            rec["result"] = "FAIL"; rec["reason"] = o["error"]; log.append(rec); continue
        tp = o.get("transcript_path")
        if not tp or not os.access(tp, os.R_OK):
            rec["result"] = "FAIL"; rec["reason"] = f"transcript not readable on box: {tp}"; log.append(rec); continue
        msgs, dropped = transcript_messages(tp, env, key)
        rec.update(messages=len(msgs), dropped_secretlike=dropped)
        if not msgs:
            rec["result"] = "SKIP"; rec["reason"] = "no text messages"; log.append(rec); continue
        if a.dry_run:
            rec["result"] = "DRY"; log.append(rec); continue
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
    ledger.write("summary", sessions=len(log), ok=sum(r["result"] == "OK" for r in log),
                 fail=sum(r["result"] == "FAIL" for r in log), new_episode_ids=new_ids)
    Path(a.log).write_text(json.dumps(log, ensure_ascii=False, indent=1))
    for r in log:
        print(r["result"], r["machine"], r["session_id"], r.get("messages"), r.get("reason", ""))
    print(f"episodes before={before.get('total_count')} after={after.get('total_count')} new={new_ids}")

if __name__ == "__main__":
    main()
