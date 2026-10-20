#!/usr/bin/env python3
"""deepvision广告夜审 9b5c20e7 step 4: the night's lessons -> one EverOS session -> /memory/add -> /memory/flush.

Usage: python3 -I dv_ads_lessons.py --lessons L.json --log OUT.json [--ledger L.jsonl] [--dry-run | --readback-only] [--project P]
Reads ~/.config/everos/dv-ads.env (scope deepvision / deepvision-ads / zack / coding-deepvision-ads);
the key goes only into the Authorization header.
--project vllm-omni (2026-10-18) is the vllm night review c392a743: ~/.config/everos/vllm-omni.env (scope
vllm-omni / vllm-omni / zack / coding-vllm-omni), session nightly-review-vllm-omni-<D>,
ledger <D>-vllm-omni-ledger.jsonl. Everything else is the same.

Why a user message (FDV-81): on 2026-10-16 the night review added its 4 lessons as assistant messages only;
add 200 and flush 200 extracted, but no episode was made. EverOS builds the user's episodes from a
conversation, so every session written here starts with one message from sender zack (the night's review
question and context) followed by one assistant message per lesson.

Lessons file (JSON, written by the night review):
  {"date": "2026-10-16",                      # the reviewed SGT day D
   "session_id": "...",                       # optional; default nightly-review-deepvision-ads-<D>
   "at": "2026-10-17T00:10:00+08:00",         # optional; first message time, default now. Later messages +1 s each
   "context": "...",                          # the user (zack) message: what was reviewed, what is asked
   "lessons": [{"label": "L1", "text": "..."}, ...]}   # label is prefixed as "[label] " to the text
Every message is checked for secrets (key, SECRET_RES); one hit stops the run before anything is sent.
A session that already has episodes is not written again (result=ALREADY).

Endpoint and result-unknown handling are copied from the xinyue writer nightly_addflush.py (ops PR #11,
merge e309349) and behave the same: tailnet http://100.64.0.5 with Host: everos.deepvision.sg first,
public EVEROS_BASE_URL only when the connection cannot be made; 502/504/524, a read timeout or a dropped
connection is an unknown result, rechecked after 5/15/30/60 s (session_id episodes, unflushed buffer,
total_count), and resent at most once. Ledger lines (default
~/xinyue-deploy/nightly-review/<D>-deepvision-ads-ledger.jsonl) have the same kinds; see that file's docstring.
Read back (PER-67, everos_readback.py; replaces the 5/15/30/60 s post_check): HTTP 200 is not success.
After an OK write, and for an ALREADY session, the session is read back by session_id under the env's
scope, polled up to everos_readback.READBACK_TIMEOUT_S (180 s); it needs at least one episode. Then
count_after; summary.new_episode_ids is the difference. Not read back -> result=FAIL with reason
"readback_failed: <why>", ledger kind=readback / readback_summary, exit 3 (a write FAIL is still 1).
--dry-run sends no add/flush: it takes the read-only counts and prints the messages it would send
(role, sender, length, first 60 characters).
--readback-only sends no add/flush either: it reads back the lessons file's session (the same check).
EVEROS_WRITE_STUB_URL (drill only): add and flush go to this address and nowhere else; see nightly_addflush.py.
"""
import argparse, http.client, json, os, re, sys, time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))   # python3 -I leaves the script's directory out
import everos_readback

SGT = timezone(timedelta(hours=8))
# --project -> (env file, expected app / project / user / assistant sender); ID 10-16 批
PROJECTS = {
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
               "User-Agent": "deepvision-ads-nightly-lessons/1.0"}
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
    r = get_episodes(env, page_size=100)   # ids of the first 100; the ads project is small
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

def build_messages(env, spec, key, project="deepvision-ads"):
    """(session_id, messages) from the lessons file; raises ValueError on a bad file or a secret-like text."""
    date = spec.get("date") or ""
    datetime.strptime(date, "%Y-%m-%d")
    context = (spec.get("context") or "").strip()
    lessons = spec.get("lessons") or []
    if not context:
        raise ValueError("context (the zack message) is empty")
    if not lessons or not all(isinstance(l, dict) and (l.get("text") or "").strip() for l in lessons):
        raise ValueError("lessons must be a non-empty list of {label, text}")
    sid = spec.get("session_id") or f"nightly-review-{project}-{date}"
    at = datetime.fromisoformat(spec["at"]) if spec.get("at") else datetime.now(SGT)
    t0 = int(at.timestamp() * 1000)
    texts = [("user", context)] + [("assistant", (f"[{l['label']}] " if l.get("label") else "") + l["text"].strip())
                                   for l in lessons]
    msgs = []
    for i, (role, text) in enumerate(texts):
        if (key and key in text) or any(r.search(text) for r in SECRET_RES):
            raise ValueError(f"message {i} looks like it carries a secret; nothing sent")
        if len(text) > MAX_CHARS:
            raise ValueError(f"message {i} is {len(text)} characters (max {MAX_CHARS}); shorten it")
        msgs.append({"sender_id": env["EVEROS_USER_ID"] if role == "user" else env["EVEROS_ASSISTANT_SENDER_ID"],
                     "sender_name": "User" if role == "user" else "Assistant",
                     "role": role, "timestamp": t0 + i * 1000, "content": text})
    return date, sid, msgs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lessons", required=True, help="lessons JSON (see the docstring)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--readback-only", action="store_true", help="no add/flush: read back the session only")
    ap.add_argument("--log", required=True)
    ap.add_argument("--ledger", help="ledger jsonl (default ~/xinyue-deploy/nightly-review/<date>-<project>-ledger.jsonl)")
    ap.add_argument("--project", default="deepvision-ads", choices=sorted(PROJECTS))
    ap.add_argument("--env", help="env file (default: the project's, see PROJECTS)")
    a = ap.parse_args()
    env_path, scope_want = PROJECTS[a.project]
    a.env = a.env or env_path
    env = load_env(a.env)
    if (env.get("EVEROS_APP_ID"), env.get("EVEROS_PROJECT_ID"), env.get("EVEROS_USER_ID"), env.get("EVEROS_ASSISTANT_SENDER_ID")) != scope_want:
        sys.exit("scope mismatch in " + a.env)
    env["_endpoints"] = endpoints(env)
    if os.environ.get("EVEROS_WRITE_STUB_URL"):
        env["_write_endpoints"] = [("write-stub", os.environ["EVEROS_WRITE_STUB_URL"], None)]
        print(f"WRITE STUB: add/flush go to {os.environ['EVEROS_WRITE_STUB_URL']} only (drill)", flush=True)
    key = env.get("EVEROS_API_KEY", "")
    scope = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"]}
    try:
        date, sid, msgs = build_messages(env, json.loads(Path(a.lessons).read_text()), key, a.project)
    except (ValueError, KeyError, OSError) as e:
        sys.exit(f"lessons file {a.lessons}: {e}")
    ledger = Ledger(a.ledger or f"~/xinyue-deploy/nightly-review/{date}-{a.project}-ledger.jsonl", key, a.dry_run)
    print(f"ledger: {ledger.path}", flush=True)
    print("endpoints: " + " -> ".join(f"{n} {u}" for n, u, _ in env["_endpoints"]), flush=True)
    print(f"session_id: {sid}  messages: {len(msgs)} (user {sum(m['role'] == 'user' for m in msgs)}, "
          f"assistant {sum(m['role'] == 'assistant' for m in msgs)})", flush=True)
    for m in msgs:
        print(f"  {m['role']:9} sender={m['sender_id']} ts={m['timestamp']} chars={len(m['content'])} "
              f"{m['content'][:60].replace(chr(10), ' ')}", flush=True)
    before = episode_count(env, ledger, "count_before")
    rec = {"session_id": sid, "date": date, "messages": len(msgs),
           "user_messages": sum(m["role"] == "user" for m in msgs)}
    hits, _, rs, _ = session_counts(env, sid)
    print(f"session {sid}: endpoint={rs.endpoint} http={rs.http} episodes already={hits}", flush=True)
    if a.readback_only:
        rec["result"] = "OK"; rec["readback_only"] = True
    elif hits is None or before.get("http") != 200:
        rec["result"] = "FAIL"; rec["reason"] = "could not read episodes before writing"
    elif hits:
        rec["result"] = "ALREADY"; rec["reason"] = f"session already has {hits} episode(s); not written again"
    elif a.dry_run:
        rec["result"] = "DRY"
    else:
        adds, flush, ok = write_session(env, ledger, scope, {"session_id": sid, "side": "box"}, msgs)
        rec["add"], rec["flush"] = adds, flush
        rec["result"] = "OK" if ok else "FAIL"
        if not ok and flush is None:
            rec["reason"] = "add failed; session stopped before flush"
    print(json.dumps(rec, ensure_ascii=False), flush=True)
    read_back = rec["result"] in everos_readback.OK_ROWS
    if read_back:
        # the session_id index lags the flush (~18 s on 2026-10-17): the read back polls for it
        res = everos_readback.readback(env, post, [everos_readback.episode_target(sid)], a.project, ledger)[0]
        rec["readback"] = {k: res.get(k) for k in ("result", "reason", "count", "polls", "seconds", "found")}
        if res["result"] != "PASS":
            rec["result"], rec["reason"] = "FAIL", everos_readback.failure_reason(res)
    after = episode_count(env, ledger, "count_after") if rec["result"] in ("OK", "FAIL") else before
    new_ids = sorted(set(after.get("episode_ids") or []) - set(before.get("episode_ids") or []))
    ledger.write("summary", sessions=1, result=rec["result"], ok=int(rec["result"] == "OK"),
                 fail=int(rec["result"] == "FAIL"), new_episode_ids=new_ids)
    Path(a.log).write_text(json.dumps([rec], ensure_ascii=False, indent=1))
    print(f"{rec['result']} {sid} {rec.get('reason', '')}".rstrip())
    print(f"episodes before={before.get('total_count')} after={after.get('total_count')} new={new_ids}")
    if read_back and rec["readback"]["result"] != "PASS":
        print("readback_failed: see the readback_failed line above", flush=True)
        return everos_readback.EXIT_READBACK_FAILED
    return 1 if rec["result"] == "FAIL" else 0

if __name__ == "__main__":
    sys.exit(main())
