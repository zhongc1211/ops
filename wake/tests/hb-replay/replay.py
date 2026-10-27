"""heartbeat-watch 演练用的假 orca（HB_ORCA 指到同目录的 orca）：回放 fixtures/ 里从 iMac 录的 ops · 01 运行记录和
自动任务列表，不连任何 Orca。只认 `automations runs --id <id> [--environment <env>] --json` 和
`automations list [--environment <env>] --json`，别的退出 2。录数据：wake/tests/heartbeat-watch-ssh.sh --record。

时间：现在 = HB_FAKE_NOW（和 clock/sitecustomize.py 用同一个值），没设就用真时间。所有 @@HB 的 ts、last_scan 和运行的
createdAt 整体平移，让最新一条心跳正好是 HB_REPLAY_AGE_S 秒前（默认 120）。
HB_REPLAY_MODE（可以按目标 id 前 8 位单独设：HB_REPLAY_MODE_<id 前 8 位>；HB_REPLAY_AGE_S_<id 前 8 位> 同理）：
  runs         照录的回放（默认）
  nohb         运行记录还在，stdout 里的 @@HB 行去掉
  scan-stale   心跳照常，last_scan 改成 HB_REPLAY_SCAN_AGE_S 秒前
  new          一条运行记录都没有；list 里它的 createdAt 是 HB_REPLAY_CREATED_AGE_S 秒前（默认 300）
  unreachable  stdout 空、stderr 一行 ssh 的报错、退出 255（像 ssh 连不上）
  garbage      stdout 不是 JSON、退出 0
  error        {"ok": false, "error": ...}、退出 1（像 orca 找不到自动任务）
unreachable / garbage / error 对 list 也生效（按不分 id 的 HB_REPLAY_MODE）。每次调用往 HB_REPLAY_LOG（设了的话）追加一行参数。
"""
import json
import os
import re
import sys
import time

FIX = os.environ.get("HB_REPLAY_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
args = sys.argv[1:]
if os.environ.get("HB_REPLAY_LOG"):
    with open(os.environ["HB_REPLAY_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps(args, ensure_ascii=False) + "\n")


def opt(name):
    i = args.index(name) if name in args else -1
    return args[i + 1] if 0 <= i < len(args) - 1 else None


def per_id(name, aid, default):
    return os.environ.get("%s_%s" % (name, aid[:8])) or os.environ.get(name) or default


if args[:2] not in (["automations", "runs"], ["automations", "list"]) or "--json" not in args:
    print("hb-replay orca：只回放 automations runs|list --json，拒绝：%s" % " ".join(args), file=sys.stderr)
    sys.exit(2)
cmd, aid = args[1], opt("--id") or ""
if cmd == "runs" and not aid:
    print("hb-replay orca：runs 要 --id", file=sys.stderr)
    sys.exit(2)
NOW = float(os.environ.get("HB_FAKE_NOW") or time.time())
mode = per_id("HB_REPLAY_MODE", aid, "runs") if cmd == "runs" else os.environ.get("HB_REPLAY_MODE") or "runs"
if mode == "unreachable":
    print("ssh: Could not resolve hostname hb-replay.invalid: nodename nor servname provided, or not known", file=sys.stderr)
    sys.exit(255)
if mode == "garbage":
    print("<html><body>502 Bad Gateway</body></html>")
    sys.exit(0)
if mode == "error":
    print(json.dumps({"id": "hb-replay", "ok": False,
                      "error": {"code": "automation_not_found", "message": "Automation not found: %s" % aid}}))
    sys.exit(1)

runs_fx = json.load(open(os.path.join(FIX, "runs-439cd438.json"), encoding="utf-8"))
HB = re.compile(r"^@@HB (\{.*\})\s*$", re.M)
newest = max(json.loads(m.group(1))["ts"] for r in runs_fx["result"]["runs"]
             for m in HB.finditer((r.get("precheckResult") or {}).get("stdout") or ""))


def shift_of(i):
    return (NOW - float(per_id("HB_REPLAY_AGE_S", i, "120"))) - newest


if cmd == "list":
    autos = []
    for a in json.load(open(os.path.join(FIX, "list-imac.json"), encoding="utf-8"))["result"]["automations"]:
        a = dict(a)
        if per_id("HB_REPLAY_MODE", a["id"], "runs") == "new":
            a["createdAt"] = int((NOW - float(os.environ.get("HB_REPLAY_CREATED_AGE_S") or 300)) * 1000)
        else:
            a["createdAt"] = int(a["createdAt"] + shift_of(a["id"]) * 1000)
        autos.append(a)
    print(json.dumps({"id": "hb-replay", "ok": True, "result": {"automations": autos}}, ensure_ascii=False))
    sys.exit(0)

shift = shift_of(aid)
scan_age = os.environ.get("HB_REPLAY_SCAN_AGE_S")


def fix_hb(m):
    hb = json.loads(m.group(1))
    hb["ts"] = int(round(hb["ts"] + shift))
    if mode == "scan-stale" and scan_age:
        hb["last_scan"] = int(NOW - float(scan_age))
    elif hb.get("last_scan"):
        hb["last_scan"] = int(round(hb["last_scan"] + shift))
    return "@@HB " + json.dumps(hb)


runs = []
if mode != "new":
    for r in runs_fx["result"]["runs"]:
        r = json.loads(json.dumps(r))
        r["automationId"] = aid
        r["createdAt"] = int(r["createdAt"] + shift * 1000)
        pr = r.get("precheckResult")
        if pr and pr.get("stdout"):
            pr["stdout"] = HB.sub("", pr["stdout"]) if mode == "nohb" else HB.sub(fix_hb, pr["stdout"])
        runs.append(r)
print(json.dumps({"id": "hb-replay", "ok": True, "result": {"runs": runs}}, ensure_ascii=False))
