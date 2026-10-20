#!/usr/bin/env python3
"""Fake `orca` CLI for the stuck-check scan-guard test. Never talks to a real Orca.

Reads FAKE_ORCA_FIXTURE (JSON): {"<env or iMac>": {"worktrees": [...], "terminals": [...]},
"slow": [{"match": "<substring of the joined args>", "sleep": <seconds>}]}. FAKE_ORCA_DELAY (seconds)
is added to every call. Every call is appended to FAKE_ORCA_LOG as one line: <ts> <args>.
"""
import json
import os
import sys
import time

args = sys.argv[1:]
env = "iMac"
if "--environment" in args:
    i = args.index("--environment")
    env = args[i + 1]
    args = args[:i] + args[i + 2:]
args = [a for a in args if a != "--json"]
line = " ".join(args)
fx = json.load(open(os.environ["FAKE_ORCA_FIXTURE"], encoding="utf-8"))
with open(os.environ["FAKE_ORCA_LOG"], "a", encoding="utf-8") as f:
    f.write("%.1f %s %s\n" % (time.time(), env, line))
time.sleep(float(os.environ.get("FAKE_ORCA_DELAY") or 0))
for rule in fx.get("slow") or []:
    if rule["match"] in "%s %s" % (env, line):
        time.sleep(rule["sleep"])
host = fx.get(env) or {}


def ok(result):
    print(json.dumps({"id": "fake", "ok": True, "result": result}))
    sys.exit(0)


cmd = args[:2]
if cmd == ["environment", "list"]:
    sys.exit(0)
if cmd[:1] == ["status"]:
    ok({"runtime": {"runtimeId": "fake-rt-" + env}, "app": {"pid": 4242}})
if cmd == ["worktree", "ps"]:
    ok({"worktrees": host.get("worktrees") or []})
if cmd == ["terminal", "list"]:
    ok({"terminals": host.get("terminals") or []})
if cmd == ["worktree", "show"]:
    ok({"worktree": {}})
if cmd == ["terminal", "read"]:
    ok({"terminal": {"tail": ["fake screen of %s" % args[args.index("--terminal") + 1], "", "", "", "status"]}})
if cmd == ["terminal", "wait"]:
    print(json.dumps({"ok": False, "error": {"code": "timeout"}}))
    sys.exit(1)
if cmd == ["automations", "list"]:
    ok({"automations": []})
if cmd == ["automations", "runs"]:
    ok({"runs": []})
if cmd == ["automations", "show"]:
    ok({"precheck": {"timeoutSeconds": 300}})
if cmd == ["linear", "list-issues"]:
    ok({"issues": []})
if cmd[:1] == ["linear"]:
    ok({"issue": {}})
if cmd == ["repo", "list"]:
    ok({"repos": []})
print(json.dumps({"ok": False, "error": {"code": "unknown_command", "message": line}}))
sys.exit(1)
