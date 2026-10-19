#!/usr/bin/env python3
"""Read back what a night review wrote to EverOS (PER-67 step 4.1, lesson T9 / FDV-81: add and flush both
answered 200 and no episode was made). HTTP 200 is not success: a write counts only once it can be read back
under the project's own scope.

Used by nightly_addflush.py (xinyue / deepvision-ads / vllm-omni sessions) and dv_ads_lessons.py (ads / vllm
lessons) after their writes, and on its own for the deepvision-site night review, whose writer dv_addflush.py
lives in the deepvision-site repo (scripts/everos/), and for any read-back-only run:

  python3 -I everos_readback.py --project P [--from-log LOG.json ...] [--session SID ...] [--skill NAME ...]
                                [--report OUT.json] [--ledger L.jsonl]

  --project      xinyue | deepvision-site | deepvision-ads | vllm-omni; picks the env file and the scope
                 (SCOPES, the 10-16 IDs) and stops if the env file does not hold that scope.
  --from-log     a writer's --log JSON (nightly_addflush / dv_addflush / dv_ads_lessons): every row with
                 result OK or ALREADY is read back by its session_id; dv_addflush rows carry episodes_before,
                 then more than that many are needed. FAIL / NOT_RUN rows are the writer's own failures and
                 are not read back again.
  --session      a session_id to read back (e.g. one written by hand or by a rerun); at least one episode.
  --skill        an agent_skill name to read back (agent side: app / project / agent_id of the env).
  --query-project-id  query with this project_id instead of the env's, still expecting the env's scope.
                 Only for the forced-failure drill (wrong scope must fail); never in a night review.

What a read back checks:
  episode:     /memory/get memory_type=episode with app_id / project_id / user_id of the env and
               filters.session_id. Every returned episode must carry exactly that app_id, project_id,
               user_id and session_id (else scope_mismatch at once). PASS when total_count > before
               (before = the session's episodes before the write, 0 when unknown).
  agent_skill: /memory/get memory_type=agent_skill with app_id / project_id / agent_id, all pages (the API
               has no name filter: filters.name is a 422), exact match on the name EverOS stores (below); the
               match must carry that agent_id, app_id and project_id.
EverOS stores a skill under sanitize_skill_name(name) (1.4.2 core/persistence/markdown/path_safety.py
sanitize_dirname): NFC, spaces to "_", drop everything but word characters, "-" and ".", cut to 50
characters, "unnamed" when that leaves "", "." or "..". No lower-casing, no trailing "-" stripped. The
record's name and id (<agent_id>_<stored name>) hold only the stored name, so two names that store the same
are one record in EverOS. A record is taken as the target's only when it can be told apart: if more than one
record has the stored name, or two targets of the same read back store the same, a record counts only when
its content or description writes out the target's full name; when none does, that is readback_failed
reason=ambiguous at once. A record that writes out another full name with the same stored prefix is not the
target's.
EverOS extracts after flush and its indexes lag (10-17: 0 episodes ~1 s after a 200 flush, 1 after ~18 s;
10-19 rerun: 4 sessions still 0 at ~5 s). So every target is polled every POLL_S seconds until it passes or
READBACK_TIMEOUT_S has gone by since the read back started. A request that fails (cannot connect, non-200,
no answer within REQUEST_TIMEOUT_S) is retried inside the same time limit; post() gets that shorter read
timeout so one hung request cannot carry the read back past its limit.
Failures are reported as readback_failed with a reason:
  not_found           every answer was 200 and the session / skill was never there
  not_more_than_before  the session has episodes, but not more than before this write
  scope_mismatch      a returned record carries another app / project / user / agent / session
  ambiguous           skill only: the stored (cut) name is shared and no record can be told apart
  request_failed      no read back request got a 200 (last http and error code are in the line)
Exit code (CLI): 0 all PASS (or nothing to check), 3 any readback_failed, 2 bad arguments / env.
Output has ids, timestamps and scope fields only: no key, no episode or skill text.
"""
import argparse, hashlib, json, os, re, sys, time, unicodedata
from pathlib import Path

READBACK_TIMEOUT_S = 180   # upper limit for one read back, from its start; then it is readback_failed
POLL_S = 10                # wait between two polls of a target that has not passed yet
REQUEST_TIMEOUT_S = 30     # read timeout of one read back request (never past the read back's end)
PAGE_SIZE = 100
SKILL_NAME_MAX = 50        # EverOS 1.4.2 path_safety._MAX_DIRNAME_LEN
EXIT_READBACK_FAILED = 3

# --project -> (env file, app / project / user / assistant sender); ID 10-16 批, the same as the writers'
SCOPES = {
    "xinyue": ("~/.config/everos/xinyue.env", ("xinyue", "xinyue-site", "zack", "coding-xinyue-site")),
    "deepvision-site": ("~/.config/everos/deepvision.env", ("deepvision", "deepvision-site", "zack", "coding-deepvision-site")),
    "deepvision-ads": ("~/.config/everos/dv-ads.env", ("deepvision", "deepvision-ads", "zack", "coding-deepvision-ads")),
    "vllm-omni": ("~/.config/everos/vllm-omni.env", ("vllm-omni", "vllm-omni", "zack", "coding-vllm-omni")),
}
OK_ROWS = ("OK", "ALREADY")

def episode_target(session_id, before=None):
    return {"kind": "episode", "session_id": session_id, "before": before}

def stored_skill_name(name):
    """The name EverOS 1.4.2 stores a skill under (sanitize_skill_name, see the module docstring)."""
    slug = re.sub(r"[^\w\-.]", "", unicodedata.normalize("NFC", name).replace(" ", "_"))[:SKILL_NAME_MAX]
    return slug if slug not in ("", ".", "..") else "unnamed"

def skill_target(name):
    return {"kind": "agent_skill", "name": name, "stored": stored_skill_name(name)}

def _full_names(skill, stored):
    """Full names starting with the stored name that a record's content / description writes out."""
    text = "\n".join(v for v in (skill.get("content"), skill.get("description")) if isinstance(v, str))
    return set(re.findall(re.escape(stored) + r"[\w\-.]*", text)) - {stored}

def scope_of(env):
    """The scope a read back expects: the env's (the callers have checked the env against their table)."""
    return {"app_id": env["EVEROS_APP_ID"], "project_id": env["EVEROS_PROJECT_ID"],
            "user_id": env["EVEROS_USER_ID"], "agent_id": env["EVEROS_ASSISTANT_SENDER_ID"]}

def _error_code(r):
    e = r.body.get("error")
    return e.get("code") if isinstance(e, dict) else None

def _poll_episode(env, post, t, query, expect, timeout):
    """-> (state, http, error, count, found); state: pass / wait / scope_mismatch / http."""
    r = post(env, "/api/v2/memory/get", {"app_id": query["app_id"], "project_id": query["project_id"],
                                         "user_id": query["user_id"], "memory_type": "episode",
                                         "filters": {"session_id": t["session_id"]}, "page_size": PAGE_SIZE}, timeout=timeout)
    if r.http != 200:
        return "http", r.http, _error_code(r), None, []
    eps = [e for e in (r.data.get("episodes") or []) if isinstance(e, dict)]
    found = [{"id": e.get("id"), "timestamp": e.get("timestamp")} for e in eps]
    want = {"app_id": expect["app_id"], "project_id": expect["project_id"], "user_id": expect["user_id"],
            "session_id": t["session_id"]}
    bad = [{"id": e.get("id"), **{k: e.get(k) for k in want if e.get(k) != v}} for e in eps
           if any(e.get(k) != v for k, v in want.items())]
    count = r.data.get("total_count")
    count = len(eps) if count is None else count
    if bad:
        return "scope_mismatch", 200, None, count, bad
    return ("pass" if count > (t.get("before") or 0) else "wait"), 200, None, count, found

def _poll_skill(env, post, t, query, expect, timeout):
    page, seen, total, match = 1, 0, None, []
    while True:
        r = post(env, "/api/v2/memory/get", {"app_id": query["app_id"], "project_id": query["project_id"],
                                             "agent_id": query["agent_id"], "memory_type": "agent_skill",
                                             "page": page, "page_size": PAGE_SIZE}, timeout=timeout)
        if r.http != 200:
            return "http", r.http, _error_code(r), None, []
        skills = [s for s in (r.data.get("agent_skills") or []) if isinstance(s, dict)]
        total = r.data.get("total_count") if r.data.get("total_count") is not None else total
        seen += len(skills)
        match += [s for s in skills if s.get("name") == t["stored"]]
        if not skills or total is None or seen >= total:
            break
        page += 1
    want = {"app_id": expect["app_id"], "project_id": expect["project_id"], "agent_id": expect["agent_id"]}
    bad = [{"id": s.get("id"), **{k: s.get(k) for k in want if s.get(k) != v}} for s in match
           if any(s.get(k) != v for k, v in want.items())]
    if bad:
        return "scope_mismatch", 200, None, len(match), bad
    named = {id(s): _full_names(s, t["stored"]) for s in match}
    match = [s for s in match if not named[id(s)] or t["name"] in named[id(s)]]   # drop another full name's
    if len(match) > 1 or (match and t.get("clash")):
        own = [s for s in match if t["name"] in named[id(s)]]
        if len(own) != 1:
            return "ambiguous", 200, None, len(match), [{"id": s.get("id")} for s in match]
        match = own
    return ("pass" if match else "wait"), 200, None, len(match), [{"id": s.get("id")} for s in match]

def readback(env, post, targets, project, ledger=None, query_scope=None):
    """Poll every target until it passes or READBACK_TIMEOUT_S is up. -> list of result dicts.

    post(env, path, body, timeout=...) is the caller's transport (nightly_addflush.post / dv_ads_lessons.post: tailnet
    first, public only when the connection cannot be made) and returns their Resp. query_scope replaces the
    queried app / project / user / agent (drill only); the expected scope stays the env's.
    """
    expect = scope_of(env)
    query = dict(expect, **(query_scope or {}))
    stored = [t["stored"] for t in targets if t["kind"] == "agent_skill"]
    targets = [dict(t, clash=stored.count(t["stored"]) > 1) if t["kind"] == "agent_skill" else t for t in targets]
    t0 = time.monotonic()
    results = []
    for t in targets:
        res = {"project": project, "kind": t["kind"], "result": None,
               **({"session_id": t["session_id"]} if t["kind"] == "episode"
                  else {"name": t["name"], "stored_name": t["stored"]}),
               "query": {k: query[k] for k in (("app_id", "project_id", "user_id") if t["kind"] == "episode"
                                               else ("app_id", "project_id", "agent_id"))},
               "polls": 0, "got_200": False, "count": None, "found": []}
        if t["kind"] == "episode":
            res["before"] = t.get("before")
        results.append(res)
    pending = list(zip(targets, results))
    while pending:
        still = []
        for t, res in pending:
            poll = _poll_episode if t["kind"] == "episode" else _poll_skill
            left = READBACK_TIMEOUT_S - (time.monotonic() - t0)
            state, http, err, count, found = poll(env, post, t, query, expect, max(1, min(REQUEST_TIMEOUT_S, left)))
            res["polls"] += 1
            res["last_http"], res["last_error"] = http, err
            if http == 200:
                res["got_200"], res["count"], res["found"] = True, count, found
            if state in ("pass", "scope_mismatch", "ambiguous"):
                res["result"] = "PASS" if state == "pass" else "readback_failed"
                if state != "pass":
                    res["reason"] = state
                res["seconds"] = round(time.monotonic() - t0, 1)
            else:
                still.append((t, res))
        pending = still
        if not pending:
            break
        if time.monotonic() - t0 + POLL_S > READBACK_TIMEOUT_S:
            for t, res in pending:
                res["result"] = "readback_failed"
                res["reason"] = ("request_failed" if not res["got_200"]
                                 else "not_found" if not res["count"] else "not_more_than_before")
                res["seconds"] = round(time.monotonic() - t0, 1)
            break
        time.sleep(POLL_S)
    for res in results:
        if ledger:   # Ledger.write takes kind itself: the target's kind goes in as target
            ledger.write("readback", target=res["kind"], **{k: v for k, v in res.items() if k != "kind"})
        what = (f"session_id={res['session_id']}" if res["kind"] == "episode" else f"name={res['name']}"
                + (f" stored_name={res['stored_name']}" if res["stored_name"] != res["name"] else ""))
        q = "/".join(str(v) for v in res["query"].values())
        if res["result"] == "PASS":
            print(f"readback PASS project={project} kind={res['kind']} {what} scope={q} count={res['count']} "
                  f"ids={','.join(str(f['id']) for f in res['found'])} after={res['seconds']}s", flush=True)
        else:
            print(f"readback_failed project={project} kind={res['kind']} {what} scope={q} reason={res['reason']} "
                  f"count={res['count']} before={res.get('before')} last_http={res['last_http']} "
                  f"last_error={res['last_error']} polls={res['polls']} after={res['seconds']}s", flush=True)
    if ledger:
        ledger.write("readback_summary", project=project, targets=len(results),
                     passed=sum(r["result"] == "PASS" for r in results),
                     readback_failed=sum(r["result"] != "PASS" for r in results))
    return results

def failed(results):
    return [r for r in results if r["result"] != "PASS"]

def failure_reason(res):
    """One line for a writer's log row, e.g. 'readback_failed: not_found (episode, polled 18x, 180.2s)'."""
    return f"readback_failed: {res['reason']} ({res['kind']}, polled {res['polls']}x, {res['seconds']}s)"

def targets_from_log(path):
    rows = json.loads(Path(path).read_text())
    rows = rows if isinstance(rows, list) else [rows]
    return [episode_target(r["session_id"], r.get("episodes_before")) for r in rows
            if isinstance(r, dict) and r.get("result") in OK_ROWS and r.get("session_id")]

def git_blob_sha(path):
    """Same as `git hash-object <path>`: ties a report to the commit that holds this file."""
    data = Path(path).read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()

def main():
    ap = argparse.ArgumentParser(description="read back night-review writes from EverOS (read-only)")
    ap.add_argument("--project", required=True, choices=sorted(SCOPES))
    ap.add_argument("--from-log", action="append", default=[])
    ap.add_argument("--session", action="append", default=[])
    ap.add_argument("--skill", action="append", default=[])
    ap.add_argument("--report", help="write the results as JSON here")
    ap.add_argument("--ledger", help="append kind=readback lines to this ledger jsonl")
    ap.add_argument("--query-project-id", help="drill only: query this project_id, still expect the env's")
    a = ap.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import nightly_addflush as transport   # same post / endpoints / load_env / Ledger as the writers
    env_path, scope_want = SCOPES[a.project]
    env = transport.load_env(env_path)
    if tuple(env.get(k) for k in ("EVEROS_APP_ID", "EVEROS_PROJECT_ID", "EVEROS_USER_ID", "EVEROS_ASSISTANT_SENDER_ID")) != scope_want:
        print("scope mismatch in " + env_path, file=sys.stderr)
        return 2
    env["_endpoints"] = transport.endpoints(env)
    if os.environ.get("EVEROS_PUBLIC_URL"):   # drill: point the public fallback somewhere else too
        env["_endpoints"] = [e for e in env["_endpoints"] if e[0] != "public"] + [("public", os.environ["EVEROS_PUBLIC_URL"], None)]
    try:
        targets = [t for p in a.from_log for t in targets_from_log(p)]
    except (OSError, ValueError, KeyError) as e:
        print(f"cannot read --from-log: {e}", file=sys.stderr)
        return 2
    have = {t["session_id"] for t in targets}
    targets += [episode_target(s) for s in a.session if s not in have]
    targets += [skill_target(n) for n in a.skill]
    print("endpoints: " + " -> ".join(f"{n} {u}" for n, u, _ in env["_endpoints"]), flush=True)
    print(f"readback project={a.project} targets={len(targets)} timeout={READBACK_TIMEOUT_S}s poll={POLL_S}s", flush=True)
    ledger = transport.Ledger(a.ledger, env.get("EVEROS_API_KEY", ""), False) if a.ledger else None
    qs = {"project_id": a.query_project_id} if a.query_project_id else None
    results = readback(env, transport.post, targets, a.project, ledger, qs) if targets else []
    bad = failed(results)
    if a.report:
        Path(a.report).write_text(json.dumps({
            "project": a.project, "expected_scope": scope_of(env), "query_override": qs,
            "everos_readback_py_git_blob": git_blob_sha(__file__), "timeout_s": READBACK_TIMEOUT_S,
            "result": "readback_failed" if bad else "PASS", "results": results}, ensure_ascii=False, indent=1))
    print(f"readback {'readback_failed' if bad else 'PASS'} project={a.project} passed={len(results) - len(bad)} "
          f"failed={len(bad)}" + ("" if targets else " (nothing to check)"), flush=True)
    return EXIT_READBACK_FAILED if bad else 0

if __name__ == "__main__":
    sys.exit(main())
