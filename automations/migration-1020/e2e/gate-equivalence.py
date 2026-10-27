#!/usr/bin/env python3
"""gate-equivalence.py: do the old and the new night-review-gate.sh decide the same way when the new store variables are not
set? (B2a, PER-146: G1a and G1b in run-e2e.sh, FAILURE-MODES.md B5.)

gate-equivalence.py --old <scripts dir> --new <scripts dir> --set G1a|G1b --out <dir> [--jobs 8]
  G1a  nothing store-related set (defaults: store host box, store dir ~/xinyue-deploy/nightly-review)
  G1b  only the old names set: NR_BOX_HOST=nas NR_BOX_DIR=<sandbox>/srv/nightly-review
Each scenario runs once per version, each run in its own sandbox (fake HOME, state, lock, NR_DIR) with a clean environment:
PATH=<fakebin>:/usr/bin:/bin:/usr/sbin:/sbin, fakebin/ssh = fake-ssh.py (connects nowhere), the session-list sync is a
recorder, pmset / ioreg / display output comes from files. Wakes go to one mock_webhook.py on 127.0.0.1 (URL path
/<version>/<set>/<scenario>/ops-system, KEY e2e-fake).
Compared: the exit code of every step, the stdout of `reason` (it prints its answer), and after the last step the status
lines (caffeinate=<pid> -> PID, escalated=<machine> -> SET), the takeover file, the synced marker, the lock holder, the files
in the local and fake-ssh stores, the wakes (status, reason, task), the sync calls, and the ssh calls (host, kind, rc, and
the path with <sandbox> -> <SB> and <sandbox>/home -> ~). Other stdout is not compared (wording changed).
Listed but not counted: the ssh path before the ~ step (G1), the wake machine and note, escalated=<machine> (B8).
Writes <out>/<set>/REPORT.md, old.json, new.json. Exit 0 = no counted difference, 1 = differences, 3 = setup check failed.
"""
import argparse, concurrent.futures as cf, datetime as dt, hashlib, json, os, re, shutil, subprocess, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("--old", required=True); ap.add_argument("--new", required=True)
ap.add_argument("--set", required=True, choices=["G1a", "G1b"]); ap.add_argument("--out", required=True)
ap.add_argument("--jobs", type=int, default=8)
A = ap.parse_args()
E = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.abspath(A.out), A.set)
shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
VERS = {"old": os.path.abspath(A.old), "new": os.path.abspath(A.new)}
STOREHOST = "box" if A.set == "G1a" else "nas"
D = "2099-02-01"
GATE_PATH_LINE = "export PATH=/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"


def ep(s):
    return int(dt.datetime.fromisoformat(s + "+08:00").timestamp())


# vllm-omni: MBA 01:20 (watch / backup from +30, box-watch +150); xinyue: MBA 23:40 the evening before
T = dict(M=ep("2026-10-21T01:21:00"), W=ep("2026-10-21T01:50:00"), B=ep("2026-10-21T02:00:00"), X=ep("2026-10-21T03:50:00"),
         EARLY=ep("2026-10-21T01:00:00"), BEFORE=ep("2026-10-21T01:40:00"), LATE=ep("2026-10-21T05:30:00"),
         XM=ep("2026-10-20T23:41:00"), XW=ep("2026-10-21T00:10:00"), XB=ep("2026-10-21T00:20:00"), XX=ep("2026-10-21T02:10:00"))
DONE = "# e2e\n状态：完成\n"
SC = []


def add(name, steps, p="vllm-omni", **kw):
    SC.append(dict(name=name, p=p, steps=steps, **kw))


def summ(p):
    return f"{D}-{p}.md"


V = "vllm-omni"
add("primary-store-done", [("primary", [], T["M"])], store={summ(V): DONE})
add("primary-started-1h-ago", [("primary", [], T["M"])], status=f"state=started machine=mba reason=ok ts={T['M'] - 3600}\n")
add("primary-checking-10min-ago", [("primary", [], T["M"])], status=f"state=checking machine=mba ts={T['M'] - 600}\n")
add("primary-outside-window", [("primary", [], T["EARLY"])])
add("primary-on-battery", [("primary", [], T["M"])], pm=dict(batt="bat"))
add("primary-lid-closed", [("primary", [], T["M"])], pm=dict(io="shut", pmg="nosd"))
add("primary-lid-closed-sleepdisabled", [("primary", [], T["M"])], pm=dict(io="shut", pmg="sd"))
add("primary-lock-busy", [("primary", [], T["M"])], lock="vllm-upstream")
add("primary-own-lock", [("primary", [], T["M"])], lock="night-review-vllm-omni")
add("primary-normal-then-retry", [("primary", [], T["M"]), ("primary", [], T["M"] + 600)])
add("primary-store-down", [("primary", [], T["M"])], down=["STORE"])
add("watch-store-done", [("watch", [], T["W"])], store={summ(V): DONE})
add("watch-mba-offline", [("watch", [], T["W"])], down=["mba"])
add("watch-mba-no-state", [("watch", [], T["W"])])
add("watch-mba-lock-busy", [("watch", [], T["W"])], mba_state=f"state=missed machine=mba reason=lock_busy detail=vllm-upstream ts={T['M']}\n")
add("watch-mba-running", [("watch", [], T["W"])], mba_state=f"state=started machine=mba reason=ok gh=yes caffeinate=1 ts={T['M']}\n")
add("watch-mba-stalled", [("watch", [], T["W"] + 3600)], mba_state=f"state=started machine=mba reason=ok gh=yes caffeinate=1 ts={T['M']}\n")
add("watch-mba-done-not-in-store", [("watch", [], T["W"])], mba_state=f"state=done machine=mba reason=ok files=2 ts={T['M']}\n")
add("watch-store-down-mba-done", [("watch", [], T["W"])], down=["STORE"], mba_state=f"state=done machine=mba reason=ok files=2 ts={T['M']}\n")
add("backup-before-window", [("backup", [], T["BEFORE"])], down=["mba"])
add("backup-after-window", [("backup", [], T["LATE"])], down=["mba"])
add("backup-store-done", [("backup", [], T["B"])], store={summ(V): DONE}, takeover=f"reason=offline since={T['W']}\n")
add("backup-mba-running", [("backup", [], T["B"])], mba_state=f"state=started machine=mba reason=ok ts={T['B'] - 600}\n")
add("backup-mba-offline-takes-over", [("backup", [], T["B"]), ("backup", [], T["B"] + 600)], down=["mba"])
add("backup-already-started", [("backup", [], T["B"])], takeover=f"reason=offline since={T['W']}\n",
    status=f"state=started machine=imac reason=offline ts={T['B'] - 600}\n")
add("backup-lock-busy-under-60min", [("backup", [], T["B"])], takeover=f"reason=offline since={T['B'] - 600}\n", lock="linear-sync")
add("backup-lock-busy-over-60min", [("backup", [], T["B"]), ("backup", [], T["B"] + 600)],
    takeover=f"reason=offline since={T['B'] - 3700}\n", lock="linear-sync")
add("backup-synced-marker", [("backup", [], T["B"])], takeover=f"reason=asleep since={T['W']}\n", synced=True)
add("box-watch-store-done", [("box-watch", [], T["X"])], local_store={summ(V): DONE})
add("box-watch-already-escalated", [("box-watch", [], T["X"])], status=f"escalated=box reason=imac_missed ts={T['X'] - 600}\n")
add("box-watch-imac-running", [("box-watch", [], T["X"])], imac_state=f"state=started machine=imac reason=offline ts={T['X'] - 1800}\n")
add("box-watch-nobody", [("box-watch", [], T["X"]), ("box-watch", [], T["X"] + 600)])
add("box-watch-imac-down", [("box-watch", [], T["X"])], down=["imac"])
add("finish-no-done-line", [("finish", [D, "mba", "ok"], T["B"])], nr={summ(V): "# e2e\n状态：进行中\n"}, lock="night-review-vllm-omni")
add("finish-ok", [("finish", [D, "imac", "offline"], T["B"])], nr={summ(V): DONE, f"{D}-vllm-omni-ledger.jsonl": "{}\n"},
    lock="night-review-vllm-omni")
add("finish-store-down", [("finish", [D, "mba", "ok"], T["B"])], nr={summ(V): DONE}, lock="night-review-vllm-omni", down=["STORE"])
add("reason-no-takeover", [("reason", [D], T["B"])])
add("reason-takeover", [("reason", [D], T["B"])], takeover=f"reason=lock_busy since={T['W']}\n")
add("keepawake", [("keepawake", [], T["B"])])
X = "xinyue"
add("xinyue-primary-normal", [("primary", [], T["XM"])], p=X)
add("xinyue-watch-mba-offline", [("watch", [], T["XW"])], p=X, down=["mba"])
add("xinyue-backup-mba-offline", [("backup", [], T["XB"])], p=X, down=["mba"])
add("xinyue-finish-ok", [("finish", [D, "mba", "ok"], T["XB"])], p=X, lock="night-review-xinyue",
    nr={summ(X): DONE, f"{D}-xinyue-ledger.jsonl": "{}\n", f"{D}-addflush.json": "[]\n"})
add("xinyue-box-watch-nobody", [("box-watch", [], T["XX"])], p=X)

FIX = os.path.join(OUT, "fixtures"); os.makedirs(FIX)
PM = {"ac": "Now drawing from 'AC Power'\n", "bat": "Now drawing from 'Battery Power'\n",
      "sd": " SleepDisabled\t\t1\n sleep 0\n", "nosd": " sleep 1\n",
      "open": '    "AppleClamshellState" = No\n', "shut": '    "AppleClamshellState" = Yes\n',
      "displays": "  Resolution: 2560 x 1664\n  Connection Type: Internal\n"}
for k, v in PM.items():
    open(os.path.join(FIX, k), "w").write(v)
BIN = os.path.join(OUT, "fakebin"); os.makedirs(BIN)
shutil.copy(os.path.join(E, "fake-ssh.py"), os.path.join(BIN, "ssh")); os.chmod(os.path.join(BIN, "ssh"), 0o755)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)


def env_for(sb, sc, ver, now, pm):
    e = {"HOME": f"{sb}/home", "PATH": f"{BIN}:/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "GH_NO_UPDATE_NOTIFIER": "1",
         "NR_STATE": f"{sb}/state", "HEAVY_LOCK_DIR": f"{sb}/lock/heavy.lock", "NR_DIR": f"{sb}/nr", "NR_SYNC": f"{sb}/sync.sh",
         "NR_PMSET_BATT": f"{FIX}/{pm.get('batt', 'ac')}", "NR_PMSET_G": f"{FIX}/{pm.get('pmg', 'sd')}",
         "NR_IOREG": f"{FIX}/{pm.get('io', 'open')}", "NR_DISPLAYS": f"{FIX}/displays", "NR_CAFFEINATE_T": "1",
         "FAKE_SSH_LOG": f"{sb}/ssh.jsonl", "FAKE_SSH_ROOT": f"{sb}/fake",
         "FAKE_SSH_DOWN": " ".join(STOREHOST if h == "STORE" else h for h in sc.get("down", [])),
         "NR_NOW": str(now), "NR_D": D}
    if A.set == "G1b":
        e.update(NR_BOX_HOST="nas", NR_BOX_DIR=f"{sb}/srv/nightly-review")
    return e


def local_store(sb):
    return f"{sb}/home/xinyue-deploy/nightly-review" if A.set == "G1a" else f"{sb}/srv/nightly-review"


def listing(d):
    out = {}
    for r, _, fs in os.walk(d):
        for f in fs:
            p = os.path.join(r, f)
            out[os.path.relpath(p, d)] = hashlib.sha256(open(p, "rb").read()).hexdigest()[:12]
    return dict(sorted(out.items()))


def run(ver, sc, port):
    S = VERS[ver]; p = sc["p"]
    sb = os.path.join(OUT, "sb", ver, sc["name"])
    write(f"{sb}/home/.config/grokbot/webhooks/ops-system.env",
          f"URL=http://127.0.0.1:{port}/{ver}/{A.set}/{sc['name']}/ops-system\nKEY=e2e-fake\n")
    write(f"{sb}/sync.sh", f'#!/bin/bash\necho "$@" >> {sb}/sync-calls\n')
    st = f"{sb}/state/{p}"; os.makedirs(st, exist_ok=True); os.makedirs(f"{sb}/nr", exist_ok=True)
    for f, t in sc.get("store", {}).items():
        write(f"{sb}/fake/{STOREHOST}/store/{f}", t)
    for f, t in sc.get("local_store", {}).items():
        write(f"{local_store(sb)}/{f}", t)
    if "mba_state" in sc:
        write(f"{sb}/fake/mba/state/{p}/{D}.status", sc["mba_state"])
    if "imac_state" in sc:
        write(f"{sb}/fake/imac/state/{p}/{D}.status", sc["imac_state"])
    if "status" in sc:
        write(f"{st}/{D}.status", sc["status"])
    if "takeover" in sc:
        write(f"{st}/{D}.takeover", sc["takeover"])
    if sc.get("synced"):
        write(f"{st}/{D}.synced", "")
    for f, t in sc.get("nr", {}).items():
        write(f"{sb}/nr/{f}", t)
    pm = sc.get("pm", {})
    if sc.get("lock"):
        subprocess.run(["/bin/bash", f"{S}/heavy-lock.sh", "acquire", sc["lock"]], env=env_for(sb, sc, ver, 0, pm),
                       capture_output=True, timeout=60)
    steps = []
    for role, args, now in sc["steps"]:
        argv = ["/bin/bash", f"{S}/night-review-gate.sh", role] + ([] if role == "keepawake" else [p]) + args
        r = subprocess.run(argv, env=env_for(sb, sc, ver, now, pm), capture_output=True, text=True, timeout=300)
        steps.append({"role": role, "args": args, "now": now, "rc": r.returncode, "stdout": r.stdout, "stderr": r.stderr})
    owner = open(f"{sb}/lock/heavy.lock/owner").read() if os.path.exists(f"{sb}/lock/heavy.lock/owner") else ""
    calls = [json.loads(l) for l in open(f"{sb}/ssh.jsonl", encoding="utf-8")] if os.path.exists(f"{sb}/ssh.jsonl") else []
    return {"sb": sb, "steps": steps,
            "status": open(f"{st}/{D}.status").read().splitlines() if os.path.exists(f"{st}/{D}.status") else [],
            "takeover": open(f"{st}/{D}.takeover").read() if os.path.exists(f"{st}/{D}.takeover") else None,
            "synced": os.path.exists(f"{st}/{D}.synced"),
            "lock": re.sub(r"^name=(\S*).*", r"\1", owner.strip()) or None,
            "local_store": listing(local_store(sb)), "fake_stores": {h: listing(f"{sb}/fake/{h}/store") for h in ("box", "nas", "mba", "imac")
                                                                      if os.path.isdir(f"{sb}/fake/{h}/store")},
            "sync_calls": open(f"{sb}/sync-calls").read().splitlines() if os.path.exists(f"{sb}/sync-calls") else [],
            "ssh": calls}


def norm_path(s, sb):
    return s.replace(sb + "/home", "~").replace(sb, "<SB>")


def compared(o, wakes):
    sb = o["sb"]
    return {"rc": [s["rc"] for s in o["steps"]],
            "reason_stdout": [s["stdout"] for s in o["steps"] if s["role"] == "reason"],
            "status": [re.sub(r"escalated=\S+", "escalated=SET", re.sub(r"caffeinate=\d+", "caffeinate=PID", l)) for l in o["status"]],
            "takeover": o["takeover"], "synced": o["synced"], "lock": o["lock"],
            "local_store": o["local_store"], "fake_stores": o["fake_stores"],
            "wakes": [(w["status"], w["reason"], w["task"]) for w in wakes], "sync_calls": o["sync_calls"],
            "ssh": [(c["host"], c["kind"], c["rc"], norm_path(c["path"], sb)) for c in o["ssh"]]}


def listed(o, wakes):
    sb = o["sb"]
    return {"ssh_path": [(c["host"], c["kind"], c["path"].replace(sb, "<SB>")) for c in o["ssh"] if c["path"]],
            "wake_machine_note": [(w["machine"], w["note"]) for w in wakes],
            "escalated": [m for l in o["status"] for m in re.findall(r"escalated=\S+", l)]}


# setup checks: the gate's PATH line is the one this harness assumes, and under it `ssh` is fake-ssh.py
for ver, S in VERS.items():
    if GATE_PATH_LINE not in open(f"{S}/night-review-gate.sh", encoding="utf-8").read():
        print(f"setup: {ver} night-review-gate.sh has no '{GATE_PATH_LINE}'"); sys.exit(3)
probe = os.path.join(OUT, "probe"); os.makedirs(f"{probe}/home")
r = subprocess.run(["/bin/bash", "-c", GATE_PATH_LINE + "; command -v ssh"], capture_output=True, text=True,
                   env={"HOME": f"{probe}/home", "PATH": f"{BIN}:/usr/bin:/bin:/usr/sbin:/sbin"})
if r.stdout.strip() != os.path.join(BIN, "ssh"):
    print(f"setup: under the gate's PATH ssh is '{r.stdout.strip()}', not {BIN}/ssh"); sys.exit(3)

hooks, portf, stop = os.path.join(OUT, "hooks.jsonl"), os.path.join(OUT, "port"), os.path.join(OUT, "mock-stop")
mock = subprocess.Popen([sys.executable, "-I", os.path.join(E, "mock_webhook.py"), hooks, portf, "1800", stop])
for _ in range(50):
    if os.path.exists(portf) and open(portf).read().strip():
        break
    time.sleep(0.2)
port = open(portf).read().strip()
t0 = time.time()
res = {"old": {}, "new": {}}
with cf.ThreadPoolExecutor(max_workers=A.jobs) as ex:
    futs = {ex.submit(run, ver, sc, port): (ver, sc["name"]) for ver in VERS for sc in SC}
    for f in cf.as_completed(futs):
        ver, name = futs[f]; res[ver][name] = f.result()
open(stop, "w").close(); mock.wait(timeout=30)
elapsed = time.time() - t0
recs = [json.loads(l) for l in open(hooks, encoding="utf-8")] if os.path.exists(hooks) else []
bad_auth = sum(1 for x in recs if not x["auth_ok"])


def wakes(ver, name):
    return [x["body"] for x in recs if x["path"].startswith(f"/{ver}/{A.set}/{name}/")]


rows, diffs, notes = [], [], []
for sc in SC:
    n = sc["name"]; o, w = res["old"][n], res["new"][n]
    co, cw = compared(o, wakes("old", n)), compared(w, wakes("new", n))
    lo, lw = listed(o, wakes("old", n)), listed(w, wakes("new", n))
    d = [k for k in co if co[k] != cw[k]]
    rows.append((n, co["rc"], cw["rc"], d))
    for k in d:
        diffs.append(f"- {n}: {k}: old {json.dumps(co[k], ensure_ascii=False)} / new {json.dumps(cw[k], ensure_ascii=False)}")
    for k in lo:
        if lo[k] != lw[k]:
            notes.append(f"- {n}: {k}: old {json.dumps(lo[k], ensure_ascii=False)} / new {json.dumps(lw[k], ensure_ascii=False)}")
for ver in VERS:
    json.dump(res[ver], open(os.path.join(OUT, f"{ver}.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
sha = {v: hashlib.sha256(open(f"{S}/night-review-gate.sh", "rb").read()).hexdigest() for v, S in VERS.items()}
desc = {"G1a": "nothing store-related set (store host box, ~/xinyue-deploy/nightly-review)",
        "G1b": "only the old names set (NR_BOX_HOST=nas, NR_BOX_DIR=<SB>/srv/nightly-review)"}[A.set]
L = [f"# {A.set}: old and new night-review-gate.sh, {desc}", "",
     f"- old: {VERS['old']}/night-review-gate.sh sha256 {sha['old']}", f"- new: {VERS['new']}/night-review-gate.sh sha256 {sha['new']}",
     f"- {len(SC)} scenarios, {sum(len(s['steps']) for s in SC)} gate calls per version, {elapsed:.0f} s; "
     f"ssh = fake-ssh.py (connects nowhere), wakes = mock_webhook.py on 127.0.0.1 ({len(recs)} received, {bad_auth} with a wrong KEY)",
     f"- result: {'no counted difference' if not diffs else f'{len(diffs)} counted difference(s)'}", "",
     "| scenario | exit codes old | exit codes new | differing fields |", "|---|---|---|---|"]
L += [f"| {n} | {' '.join(map(str, a))} | {' '.join(map(str, b))} | {', '.join(d) or '-'} |" for n, a, b, d in rows]
L += ["", "## Counted differences", ""] + (diffs or ["none"])
L += ["", "## Listed, not counted (the intended changes: ~ no longer expanded here, stuck wakes say machine=imac)", ""] + (notes or ["none"])
open(os.path.join(OUT, "REPORT.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print(f"{A.set}: {len(SC)} scenarios, {len(diffs)} counted difference(s), {len(notes)} listed; {OUT}/REPORT.md")
sys.exit(1 if diffs or bad_auth else 0)
