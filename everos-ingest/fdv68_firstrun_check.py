#!/usr/bin/env python3
"""FDV-68 one-shot check of the first deepvision-site collection night (D = 2026-10-16).

Read-only: reads the collection lists, Orca automation run records and EverOS (memory/get
only). Prints PASS/FAIL lines plus a summary; writes a markdown report to --out.
Exit 0 = all PASS, 1 = any FAIL. The EverOS key is read from ~/.config/everos/deepvision.env
and only goes into the Authorization header; it is never printed.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

SGT = timezone(timedelta(hours=8))
D = "2026-10-16"
LIST_DIR = Path(f"/var/lib/everos-ingest/deepvision-site/{D}")
COLLECT_BOX = "207ff52e-2dfb-4365-9b3d-3951ef3054ca"
COLLECT_IMAC = "34fe1ab0-7b3d-4e6a-917a-2c254e0e6dc6"
NIGHT_REVIEW = "43c55a22-35fb-428e-b0a5-65128ca3c332"
SCOPE = {"app_id": "deepvision", "project_id": "deepvision-site"}
OTHERS = [
    {"app_id": "xinyue", "project_id": "xinyue-site"},
    {"app_id": "deepvision", "project_id": "deepvision-ads"},
    {"app_id": "vllm-omni", "project_id": "vllm-omni"},
    {"app_id": "default", "project_id": "default"},
]
# Window that run records must fall in: the scheduled night after D.
NIGHT_START = datetime.fromisoformat(f"{D}T23:00:00+08:00")

lines: list[str] = []
fails = 0


def check(ok: bool, name: str, detail: str) -> None:
    global fails
    fails += not ok
    lines.append(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")


def note(name: str, detail: str) -> None:
    lines.append(f"INFO  {name}: {detail}")


def env() -> dict:
    out = {}
    for line in open(os.path.expanduser("~/.config/everos/deepvision.env"), encoding="utf-8"):
        k, sep, v = line.strip().partition("=")
        if sep and not k.startswith("#"):
            out[k] = v
    return out


E = env()


def post(path: str, payload: dict) -> dict:
    req = urllib.request.Request(
        E["EVEROS_BASE_URL"].rstrip("/") + path, data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + E["EVEROS_API_KEY"], "Content-Type": "application/json",
                 "User-Agent": "fdv68-firstrun-check/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def episodes(sc: dict) -> list[dict]:
    rows, page = [], 1
    while True:
        d = post("/api/v2/memory/get", {**sc, "memory_type": "episode", "user_id": "zack", "page": page, "page_size": 100})["data"]
        rows += d.get("episodes", [])
        if len(rows) >= (d.get("total_count") or 0) or not d.get("episodes"):
            return rows
        page += 1


def runs(aid: str, imac: bool) -> list[dict]:
    cmd = ["orca", "automations", "runs", "--id", aid, "--json"] + (["--environment", "iMac-tailnet"] if imac else [])
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[-300:])
    return [r for r in json.loads(p.stdout).get("result", {}).get("runs", [])
            if (r.get("scheduledFor") or r.get("createdAt") or 0) / 1000 >= NIGHT_START.timestamp()]


def read_list(name: str) -> list[dict] | None:
    p = LIST_DIR / name
    if not p.is_file():
        return None
    return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    now = datetime.now(SGT)
    note("time", f"now={now.isoformat(timespec='seconds')} D={D} yesterday={(now - timedelta(days=1)).strftime('%Y-%m-%d')}")

    # 1. collection runs (precheck exit 1 = done, model not started)
    for aid, imac, label in ((COLLECT_IMAC, True, "iMac 34fe1ab0"), (COLLECT_BOX, False, "box 207ff52e")):
        try:
            rs = runs(aid, imac)
        except Exception as e:  # noqa: BLE001
            check(False, f"run record {label}", f"orca automations runs failed: {e}")
            continue
        if not rs:
            check(False, f"run record {label}", "no scheduled run since D 23:00")
            continue
        r = rs[0]
        pr = r.get("precheckResult") or {}
        check(pr.get("exitCode") == 1 and not pr.get("timedOut"),
              f"run record {label}", f"status={r.get('status')} precheck exit={pr.get('exitCode')} timedOut={pr.get('timedOut')} "
              f"stdout_tail={str(pr.get('stdout') or '')[-160:]!r} stderr_tail={str(pr.get('stderr') or '')[-160:]!r}")

    # 2. collection lists on box
    kept_ids, excluded_ids, with_tx = set(), set(), set()
    for m in ("box", "imac"):
        rows = read_list(f"sessions-{m}.jsonl")
        ex = read_list(f"sessions-{m}.excluded.jsonl")
        check(rows is not None, f"list {m}", f"{LIST_DIR}/sessions-{m}.jsonl " + (f"{len(rows)} rows" if rows is not None else "MISSING"))
        check(ex is not None, f"excluded list {m}", f"{len(ex)} rows" if ex is not None else "MISSING")
        for r in rows or []:
            kept_ids.add(r["session_id"])
            tp = r.get("transcript_path")
            if tp:
                with_tx.add(r["session_id"])
                ok = os.access(tp, os.R_OK)
                if m == "imac":
                    ok = ok and tp.startswith(str(LIST_DIR / "imac") + "/") and (os.stat(tp).st_mode & 0o077) == 0
                check(ok, f"transcript {m} {r['session_id'][:8]}", tp)
            note(f"row {m}", f"{r['session_id']} {r.get('linear_id')} {r.get('included_by', '')[:40]} | {r.get('include_rule', '')[:60]}")
        for r in ex or []:
            excluded_ids.add(r["session_id"])
            note(f"excluded {m}", f"{r['session_id']} {r.get('reason', '')[:70]}")
    note("totals", f"kept={len(kept_ids)} with_transcript={len(with_tx)} excluded={len(excluded_ids)}")

    # 3. night review run and EverOS episodes in the deepvision-site scope
    try:
        nr = runs(NIGHT_REVIEW, False)
        nr_status = nr[0].get("status") if nr else None
    except Exception as e:  # noqa: BLE001
        nr_status = f"error: {e}"
    note("night review 43c55a22", f"latest run status since D 23:00: {nr_status}")
    dv = episodes(SCOPE)
    wrong_scope = [e["id"] for e in dv if (e.get("app_id"), e.get("project_id")) != (SCOPE["app_id"], SCOPE["project_id"])]
    check(not wrong_scope, "deepvision-site episode scope fields", f"{len(dv)} episodes; wrong scope: {wrong_scope or 0}")
    dv_sessions = {e.get("session_id") for e in dv}
    unknown = sorted(s for s in dv_sessions - kept_ids if s)
    check(not (dv_sessions & excluded_ids), "no excluded session written", f"{sorted(dv_sessions & excluded_ids) or 0}")
    note("deepvision-site episodes", f"count={len(dv)} sessions={len(dv_sessions)} not-in-list={unknown or 0}")
    if nr_status == "completed":
        check(len(dv_sessions & with_tx) > 0 or not with_tx, "night review wrote episodes",
              f"{len(dv_sessions & with_tx)}/{len(with_tx)} listed sessions with transcript have episodes")
    else:
        check(False, "night review wrote episodes", f"43c55a22 not completed yet (status={nr_status}); episode count not judged")

    # 4. other projects: no deepvision-site session leaked in
    ours = kept_ids | excluded_ids | dv_sessions
    for sc in OTHERS:
        rows = episodes(sc)
        leak = sorted({e.get("session_id") for e in rows} & ours)
        wrong = [e["id"] for e in rows if (e.get("app_id"), e.get("project_id")) != (sc["app_id"], sc["project_id"])]
        check(not leak and not wrong, f"isolation {sc['app_id']}/{sc['project_id']}",
              f"{len(rows)} episodes; deepvision-site sessions found: {leak or 0}; wrong scope rows: {wrong or 0}")
    skills = post("/api/v2/memory/get", {**SCOPE, "agent_id": "coding-deepvision-site", "memory_type": "agent_skill", "page_size": 100})["data"]
    check(skills.get("total_count") == 8, "deepvision-site agent_skill count", f"{skills.get('total_count')} (expected 8)")

    verdict = "PASS" if not fails else f"FAIL ({fails})"
    lines.append(f"RESULT {verdict}")
    body = "\n".join(lines)
    Path(args.out).write_text(f"# FDV-68 采集首跑核查（D={D}）\n\n- 运行：{now.isoformat(timespec='seconds')}\n- 结果：**{verdict}**\n\n```\n{body}\n```\n", encoding="utf-8")
    print("\n".join(l for l in lines if not l.startswith("INFO  row") and not l.startswith("INFO  excluded")))
    print(f"report: {args.out}")
    return 0 if not fails else 1


if __name__ == "__main__":
    raise SystemExit(main())
