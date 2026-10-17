#!/usr/bin/env python3
"""心月夜审 75b324a4 step 2: sessions jsonl -> /memory/add -> /memory/flush.

Usage: python3 -I nightly_addflush.py --date 2026-10-16 [--dry-run] --log OUT.json [--ledger L.jsonl]
Reads ~/.config/everos/xinyue.env; the key goes only into the Authorization header.
Only user/assistant text blocks are sent (no tool calls/results); messages that look
like they carry a secret are dropped and counted.

Ledger (default ~/xinyue-deploy/nightly-review/<date>-xinyue-ledger.jsonl): one JSON line per call,
appended and flushed right after the call returns. kind=count_before / count_after are
/memory/get episode counts (total_count + id list) taken before the first write and after
the last; kind=add / flush carry session_id, HTTP status, request_id and the non-text fields
of the response data. No key, no message text. --dry-run still takes both counts
(read-only) and marks every line dry_run=true.
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone
from pathlib import Path

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

def post(env, path, body):
    req = urllib.request.Request(env["EVEROS_BASE_URL"].rstrip("/") + path, data=json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + env["EVEROS_API_KEY"], "Content-Type": "application/json",
                 # Cloudflare answers the default Python-urllib UA with 403 (error 1010)
                 "User-Agent": "xinyue-nightly-addflush/1.0"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except Exception:
            return e.code, {}
    except (urllib.error.URLError, OSError) as e:
        # no HTTP status (DNS/TLS/connection/timeout): record it and go on, the ledger shows http=null
        return None, {"error": {"code": type(e).__name__, "message": str(getattr(e, "reason", e))[:200]}}

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
            rec = {k: rec[k] for k in ("time", "run", "kind", "session_id", "http", "request_id", "dry_run") if k in rec}
            rec["redacted"] = True
            line = json.dumps(rec, ensure_ascii=False)
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
        return rec

def episode_count(env, ledger, kind):
    """/memory/get episode for the user (agent_id + episode is a 422) -> ledger line."""
    st, body = post(env, "/api/v2/memory/get", {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"],
                                                "user_id": env["EVEROS_USER_ID"], "memory_type": "episode"})
    data = body.get("data") if isinstance(body.get("data"), dict) else {}
    eps = data.get("episodes") or []
    rec = ledger.write(kind, http=st, request_id=body.get("request_id"), total_count=data.get("total_count"),
                       count=data.get("count"), episode_ids=[e.get("id") for e in eps if isinstance(e, dict)],
                       error=(body.get("error") or {}).get("code") if isinstance(body.get("error"), dict) else None)
    print(f"{kind}: http={st} total_count={rec.get('total_count')} count={rec.get('count')}", flush=True)
    return rec

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--log", required=True)
    ap.add_argument("--ledger", help="write ledger jsonl (default ~/xinyue-deploy/nightly-review/<date>-xinyue-ledger.jsonl)")
    a = ap.parse_args()
    env = load_env("~/.config/everos/xinyue.env")
    key = env.get("EVEROS_API_KEY", "")
    scope = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"]}
    ledger = Ledger(a.ledger or f"~/xinyue-deploy/nightly-review/{a.date}-xinyue-ledger.jsonl", key, a.dry_run)
    print(f"ledger: {ledger.path}", flush=True)
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
        adds = []
        for i in range(0, len(msgs), CHUNK):
            chunk = msgs[i:i+CHUNK]
            st, body = post(env, "/api/v2/memory/add", {**scope, "session_id": o["session_id"], "messages": chunk, "async_mode": False})
            adds.append({"http": st, "status": (body.get("data") or {}).get("status") if isinstance(body.get("data"), dict) else None,
                         "request_id": body.get("request_id"), "error": (body.get("error") or {}).get("code")})
            ledger.write("add", session_id=o["session_id"], machine=o.get("side"), chunk=i // CHUNK, messages=len(chunk),
                         first_ts=chunk[0]["timestamp"], last_ts=chunk[-1]["timestamp"], http=st,
                         request_id=body.get("request_id"), data=brief(body.get("data")), error=brief(body.get("error")))
        st, body = post(env, "/api/v2/memory/flush", {**scope, "session_id": o["session_id"]})
        ledger.write("flush", session_id=o["session_id"], machine=o.get("side"), http=st,
                     request_id=body.get("request_id"), data=brief(body.get("data")), error=brief(body.get("error")))
        rec["add"] = adds
        rec["flush"] = {"http": st, "status": (body.get("data") or {}).get("status") if isinstance(body.get("data"), dict) else None,
                        "request_id": body.get("request_id"), "error": (body.get("error") or {}).get("code"),
                        "message": (body.get("error") or {}).get("message")}
        ok = all(x["http"] == 200 for x in adds) and st == 200
        rec["result"] = "OK" if ok else "FAIL"
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
