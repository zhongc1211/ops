#!/usr/bin/env python3
"""naming-check.py — pure-script naming check across both Orca hosts (no model).

Flags (1) workspaces and Orca automations whose name is not "项目 · 编号 描述" (项目 in 心月/vllm/dv广告/dv运维/ops/dv官网/dv营销,
per dev-bot-rules, plus dv营销: a bot in use, not yet in the rules' table; 编号 like PER-38, FDV-36/37 or digits) and
(2) terminals with no title ("untitled") — a warning only.
Exempt: main/primary worktrees (isMainWorktree or name "main"), and automation run workspaces ("auto-orca-run N").
Legacy: names listed in naming-check-legacy-allowlist.json (next to this script, or $NAMING_ALLOWLIST) are reported as
"legacy" and never renamed or counted; anything not in that file still fails.
Each item is reported once (state: $NAMING_STATE or ~/.orca-state/naming-check/reported.json).
Never wakes anyone itself: stuck-check.sh appends this output to its next wake-up message.

  naming-check.py            print NEW violations (not yet reported) and mark them reported
  naming-check.py --peek     print NEW violations without marking
  naming-check.py --all      print every current violation (no marking)
  --json                     machine-readable output (violations / warnings / legacy / errors + counts)
  --input FILE               read {"<host>": {"worktrees": [], "automations": [], "terminals": []}} instead of querying Orca
Hosts: this machine, plus the iMac via `orca --environment iMac` (or $NAMING_IMAC_ENV; set to "" to skip).
Exit 1 if any current violation is not in the legacy allowlist (in every mode, reported before or not);
exit 2 if the host query failed on every host; else 0. Warnings and legacy never change the exit code.
"""
import json, os, re, subprocess, sys

PROJECTS = ("心月", "vllm", "dv广告", "dv运维", "ops", "dv官网", "dv营销")
NAME_RE = re.compile(r"^(%s) · (?:[A-Z]{2,6}-\d+(?:[/、,+-]\d+)*|\d+)(?:\s+\S.*)$" % "|".join(map(re.escape, PROJECTS)))
EXEMPT_RE = re.compile(r"^(main|auto[-_ ]?orca[-_ ]?run[-_ ]?\d+.*|自动任务 ?run ?\d+.*|.+ run \d+)$", re.I)
STATE = os.environ.get("NAMING_STATE", os.path.expanduser("~/.orca-state/naming-check/reported.json"))
ALLOWLIST = os.environ.get("NAMING_ALLOWLIST", os.path.join(os.path.dirname(os.path.abspath(__file__)), "naming-check-legacy-allowlist.json"))
ARGS = sys.argv[1:]
INPUT = ARGS[ARGS.index("--input") + 1] if "--input" in ARGS else None
automations_checked = {}

def orca(args, env=None):
    cmd = ["orca"] + (["--environment", env] if False else []) + args + (["--environment", env] if env else [])
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout)[-300:])
    d = json.loads(r.stdout)
    if not d.get("ok", True):
        raise RuntimeError(json.dumps(d.get("error"))[:300])
    return d["result"]

def lst(res, key):
    return res.get(key, res) if isinstance(res, dict) else res

def check_host(label, env):
    if INPUT:
        d = json.load(open(INPUT, encoding="utf-8"))[label]
        q = lambda k: d.get(k, [])
    else:
        q = lambda k: lst(orca({"worktrees": ["worktree", "list", "--json", "--limit", "500"], "automations": ["automations", "list", "--json"],
                                "terminals": ["terminal", "list", "--json", "--limit", "500"]}[k], env), k)
    out, ws, term = [], q("worktrees"), q("terminals")
    for w in ws:
        name = (w.get("displayName") or "").strip()
        if w.get("isMainWorktree") or EXEMPT_RE.match(name) or EXEMPT_RE.match(os.path.basename(w.get("path", ""))):
            continue
        if not NAME_RE.match(name):
            out.append({"key": "ws|%s|%s" % (label, w.get("id")), "host": label, "kind": "workspace_name",
                        "name": name, "what": "工作区显示名「%s」不符合「项目 · 编号 描述」" % name, "where": w.get("path")})
    autos = q("automations")
    automations_checked[label] = len(autos)
    for a in autos:
        name = (a.get("name") or "").strip()
        if not NAME_RE.match(name):
            out.append({"key": "auto|%s|%s" % (label, a.get("id")), "host": label, "kind": "automation_name",
                        "name": name, "what": "自动任务名「%s」不符合「项目 · 编号 描述」" % name, "where": "automation %s" % (a.get("id") or "")[:8]})
    for t in term:
        if not (t.get("title") or "").strip():
            out.append({"key": "term|%s|%s" % (label, t.get("ptyId") or t.get("handle")), "host": label, "kind": "untitled_terminal", "level": "warning",
                        "what": "终端没有标题（untitled）", "where": t.get("worktreePath") or t.get("worktreeId")})
    return out

def main():
    hosts = [("box", None)]
    imac = os.environ.get("NAMING_IMAC_ENV", "iMac")
    if INPUT:
        hosts = [(h, None) for h in json.load(open(INPUT, encoding="utf-8"))]
    elif imac:
        hosts.append(("iMac", imac))
    found, failed = [], []
    for label, env in hosts:
        try:
            found += check_host(label, env)
        except Exception as e:
            failed.append("%s: %s" % (label, e))
    legacy_keys = {e["key"] for e in json.load(open(ALLOWLIST, encoding="utf-8"))["entries"]} if os.path.exists(ALLOWLIST) else set()
    for v in found:
        if v.get("level") != "warning":
            v["level"] = "legacy" if v["key"] in legacy_keys else "violation"
    bad = [v for v in found if v["level"] == "violation"]
    try:
        seen = json.load(open(STATE))
    except (OSError, ValueError):
        seen = {}
    live = {v["key"] for v in found}
    new = [v for v in found if v["key"] not in seen]
    show = found if "--all" in ARGS else new
    if "--all" not in ARGS and "--peek" not in ARGS and not failed:
        seen = {k: v for k, v in seen.items() if k in live}   # forget fixed ones so they can be reported again
        for v in new:
            seen[v["key"]] = 1
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        json.dump(seen, open(STATE, "w"))
    pick = lambda lvl: [v for v in show if v["level"] == lvl]
    if "--json" in ARGS:
        counts = {lvl: len([v for v in found if v["level"] == lvl]) for lvl in ("violation", "warning", "legacy")}
        counts.update({"violation_by_kind": {k: len([v for v in bad if v["kind"] == k]) for k in ("workspace_name", "automation_name")},
                       "automations_checked": automations_checked})
        print(json.dumps({"violations": pick("violation"), "warnings": pick("warning"), "legacy": pick("legacy"),
                          "errors": failed, "counts": counts}, ensure_ascii=False, indent=1))
    else:
        shown = pick("violation") + pick("warning")
        if shown:
            print("命名检查：%d 项（每项只报一次）" % len(shown))
            for v in shown:
                print("- [%s] %s%s：%s（%s）" % (v["host"], v["kind"], "（提醒）" if v["level"] == "warning" else "", v["what"], v["where"]))
        else:
            print("命名检查：没有新的违规")
        if pick("legacy"):
            print("命名检查：另有 %d 项老名字在豁免表里（legacy，不算违规）" % len(pick("legacy")))
        for f in failed:
            print("命名检查查询失败 —", f)
    sys.exit(2 if len(failed) == len(hosts) else 1 if bad else 0)

main()
