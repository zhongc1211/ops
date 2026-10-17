#!/usr/bin/env python3
"""Manual run of 心月夜审 75b324a4 step 2 only: sessions jsonl -> /memory/add -> /memory/flush.

Usage: python3 -I nightly_addflush.py --date 2026-10-16 [--dry-run] --log OUT.json
Reads ~/.config/everos/xinyue.env; the key goes only into the Authorization header.
Only user/assistant text blocks are sent (no tool calls/results); messages that look
like they carry a secret are dropped and counted.
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path

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

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", required=True)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--log", required=True)
    a = ap.parse_args()
    env = load_env("~/.config/everos/xinyue.env")
    key = env.get("EVEROS_API_KEY", "")
    scope = {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"]}
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
            st, body = post(env, "/api/v2/memory/add", {**scope, "session_id": o["session_id"], "messages": msgs[i:i+CHUNK], "async_mode": False})
            adds.append({"http": st, "status": (body.get("data") or {}).get("status") if isinstance(body.get("data"), dict) else None,
                         "request_id": body.get("request_id"), "error": (body.get("error") or {}).get("code")})
        st, body = post(env, "/api/v2/memory/flush", {**scope, "session_id": o["session_id"]})
        rec["add"] = adds
        rec["flush"] = {"http": st, "status": (body.get("data") or {}).get("status") if isinstance(body.get("data"), dict) else None,
                        "request_id": body.get("request_id"), "error": (body.get("error") or {}).get("code"),
                        "message": (body.get("error") or {}).get("message")}
        ok = all(x["http"] == 200 for x in adds) and st == 200
        rec["result"] = "OK" if ok else "FAIL"
        log.append(rec)
        print(json.dumps(rec, ensure_ascii=False), flush=True)
    Path(a.log).write_text(json.dumps(log, ensure_ascii=False, indent=1))
    for r in log:
        print(r["result"], r["machine"], r["session_id"], r.get("messages"), r.get("reason", ""))

if __name__ == "__main__":
    main()
