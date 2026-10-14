#!/usr/bin/env python3
"""naming-check.py — pure-script naming check across both Orca hosts (no model).

Flags (1) workspaces whose display name is not "项目 · 编号 描述" (项目 in 心月/vllm/dv广告/dv运维/dv营销/ops;
编号 like PER-38, FDV-36/37 or digits) and (2) terminals with no title ("untitled").
Exempt: main/primary worktrees (isMainWorktree or name "main"), and automation run workspaces ("auto-orca-run N").
Each violation is reported once (state: $NAMING_STATE or ~/.orca-state/naming-check/reported.json).
Never wakes anyone itself: stuck-check.sh appends this output to its next wake-up message.

  naming-check.py            print NEW violations (not yet reported) and mark them reported
  naming-check.py --peek     print NEW violations without marking
  naming-check.py --all      print every current violation (no marking)
  --json                     machine-readable output
Hosts: this machine, plus the iMac via `orca --environment iMac` (or $NAMING_IMAC_ENV; set to "" to skip).
Exit 0 always unless a host query failed on both hosts (exit 2).
"""
import json, os, re, subprocess, sys

PROJECTS = ("心月", "vllm", "dv广告", "dv运维", "dv营销", "ops")
NAME_RE = re.compile(r"^(%s) · (?:[A-Z]{2,6}-\d+(?:[/、,+-]\d+)*|\d+)(?:\s+\S.*)$" % "|".join(map(re.escape, PROJECTS)))
EXEMPT_RE = re.compile(r"^(main|auto[-_ ]?orca[-_ ]?run[-_ ]?\d+.*|自动任务 ?run ?\d+.*|.+ run \d+)$", re.I)
STATE = os.environ.get("NAMING_STATE", os.path.expanduser("~/.orca-state/naming-check/reported.json"))
ARGS = sys.argv[1:]

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
    out, ws, term = [], lst(orca(["worktree", "list", "--json", "--limit", "500"], env), "worktrees"), lst(orca(["terminal", "list", "--json", "--limit", "500"], env), "terminals")
    for w in ws:
        name = (w.get("displayName") or "").strip()
        if w.get("isMainWorktree") or EXEMPT_RE.match(name) or EXEMPT_RE.match(os.path.basename(w.get("path", ""))):
            continue
        if not NAME_RE.match(name):
            out.append({"key": "ws|%s|%s" % (label, w.get("id")), "host": label, "kind": "workspace_name",
                        "what": "工作区显示名「%s」不符合「项目 · 编号 描述」" % name, "where": w.get("path")})
    for t in term:
        if not (t.get("title") or "").strip():
            out.append({"key": "term|%s|%s" % (label, t.get("ptyId") or t.get("handle")), "host": label, "kind": "untitled_terminal",
                        "what": "终端没有标题（untitled）", "where": t.get("worktreePath") or t.get("worktreeId")})
    return out

def main():
    hosts = [("box", None)]
    imac = os.environ.get("NAMING_IMAC_ENV", "iMac")
    if imac:
        hosts.append(("iMac", imac))
    found, failed = [], []
    for label, env in hosts:
        try:
            found += check_host(label, env)
        except Exception as e:
            failed.append("%s: %s" % (label, e))
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
    if "--json" in ARGS:
        print(json.dumps({"violations": show, "errors": failed}, ensure_ascii=False, indent=1))
    else:
        if show:
            print("命名检查：%d 项（每项只报一次）" % len(show))
            for v in show:
                print("- [%s] %s：%s（%s）" % (v["host"], v["kind"], v["what"], v["where"]))
        else:
            print("命名检查：没有新的违规")
        for f in failed:
            print("命名检查查询失败 —", f)
    sys.exit(2 if len(failed) == len(hosts) else 0)

main()
