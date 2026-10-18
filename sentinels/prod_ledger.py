#!/usr/bin/env python3
"""prod_ledger.py — 生产台账（ops · 23 生产版本哨兵的 box 这一半）。

  prod_ledger.py apply [--fetch-rc N] [--ledger PATH] [--drill] < prod_fetch.py 的 JSON
      iMac 的预检脚本 prod-watch.sh 通过 ssh 调用。拿每个 Worker 在线的 deployment 和台账里该 Worker 最后一行比：
      不同就追加一行（状态「未报」），并用 notify-run --bot coding-assistant 叫醒 Coding助手（Worker、旧→新版本、时间）。
      每次运行在 /workspace/ops/reports/prod-watch-YYYYMMDD.log 记一行；同一行也打印到 stdout，iMac 存一份镜像。
      --drill：叫醒的标题加「【演练】」，日志写到 reports/drills/，用来对着一份故意过期的台账副本演练。
  prod_ledger.py latest [--ledger PATH]
      打印每个 Worker 最后一行（看台账用）。

台账：/workspace/ops/reports/prod-ledger.md（box 上这份为准）。每个生产变更一行。Coding助手 报完生产状态后
把「未报」改成「已报」并填上 Linear；哨兵只认 deployment id 列，不看状态列。
抓取失败（fetch-rc 非 0、Worker 缺失）只记日志；同一种失败连续 4 次（约 1 小时）才叫醒一次，之后 6 小时内不再叫。
不碰 Cloudflare，不读任何令牌。退出码：0 = 已处理（有没有变化都是 0）；2 = 输入不是合法 JSON。
"""
import argparse
import datetime as dt
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys

REPORTS = "/workspace/ops/reports"
LEDGER = os.path.join(REPORTS, "prod-ledger.md")
STATE = os.path.expanduser("~/.orca-state/prod-watch")
# ssh 进来的非交互 shell 的 PATH 里没有 ~/.local/bin
NOTIFY_RUN = shutil.which("notify-run") or os.path.expanduser("~/.local/bin/notify-run")
SGT = dt.timezone(dt.timedelta(hours=8))
COLS = ["时间 SGT", "Worker", "版本", "version id", "deployment id", "commit", "报告人", "Linear", "状态", "备注"]
HEADER = """# 生产台账

每个生产 Worker 的每一次生产变更一行。由 ops · 23 生产版本哨兵（iMac，每 15 分钟）维护，Coding助手 报生产状态以这份为准。
- 「时间 SGT」是 Cloudflare 上 deployment 的创建时间。
- 哨兵发现在线 deployment 和该 Worker 最后一行不同，就追加一行，状态「未报」，并叫醒 Coding助手。
- Coding助手 报完后把「未报」改成「已报」，补上 Linear 和 commit。哨兵只比 deployment id 列，改其他列不会触发。
- 脚本：ops 仓库 `sentinels/`；运行日志：`reports/prod-watch-YYYYMMDD.log`。

"""


def now_sgt():
    return dt.datetime.now(SGT)


def to_sgt(iso):
    if not iso:
        return "?"
    t = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return t.astimezone(SGT).strftime("%Y-%m-%d %H:%M")


def table_line(cells):
    return "| " + " | ".join(str(c).replace("|", "/").replace("\n", " ") for c in cells) + " |"


def read_rows(path):
    rows = []
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return rows
    for ln in lines:
        if not ln.startswith("| ") or ln.startswith("| 时间") or set(ln) <= set("|- "):
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) >= len(COLS):
            rows.append(dict(zip(COLS, cells)))
    return rows


def latest(rows):
    last = {}
    for r in rows:
        last[r["Worker"]] = r
    return last


def ensure_ledger(path):
    if not os.path.exists(path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(HEADER + table_line(COLS) + "\n" + table_line(["---"] * len(COLS)) + "\n")


def version_cells(w):
    vs = w.get("versions") or []
    nums = "+".join("v%s%s" % (v.get("number", "?"), "" if v.get("percentage") in (100, 100.0, None) else "(%s%%)" % v["percentage"]) for v in vs)
    ids = "+".join(v["id"] for v in vs)
    return nums or "?", ids or "?"


def guess_commit(w):
    for text in [w.get("message")] + [v.get("message") for v in w.get("versions") or []]:
        m = re.search(r"\b[0-9a-f]{7,40}\b", text or "")
        if m:
            return m.group(0)
    return "未知"


def wake(task, body, drill):
    title = ("【演练】" if drill else "") + task
    try:
        p = subprocess.run([NOTIFY_RUN, "--bot", "coding-assistant", "--no-tty", "--task", title, "--",
                            "sh", "-c", 'printf "%s\\n" "$1"', "sh", body],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=180)
        return (p.stderr or "").strip().splitlines()[-1:] or ["notify-run rc=%s" % p.returncode]
    except Exception as e:
        return ["notify-run 调用失败: %s" % type(e).__name__]


def alert_failure(kind, detail, drill, logf):
    """同一种失败连续 4 次才叫醒，叫过之后 6 小时内不再叫。成功时由 clear_failures 清零。"""
    os.makedirs(STATE, exist_ok=True)
    f = os.path.join(STATE, "fail.json")
    try:
        st = json.load(open(f))
    except Exception:
        st = {}
    e = st.setdefault(kind, {"count": 0, "alerted": 0})
    e["count"] += 1
    now = int(now_sgt().timestamp())
    if e["count"] >= 4 and now - e["alerted"] >= 6 * 3600:
        res = wake("ops · 23 生产版本哨兵连续 %d 次查询失败（%s）" % (e["count"], kind),
                   "生产版本哨兵查不到生产版本：%s。日志 %s" % (detail, logf), drill)
        e["alerted"] = now
        log_line(logf, "叫醒 coding-assistant（查询失败）：%s" % " ".join(res))
    json.dump(st, open(f, "w"))


def clear_failures(kinds_seen):
    f = os.path.join(STATE, "fail.json")
    try:
        st = json.load(open(f))
    except Exception:
        return
    for k in list(st):
        if k not in kinds_seen:
            del st[k]
    json.dump(st, open(f, "w"))


def log_line(logf, msg):
    line = "%s %s" % (now_sgt().strftime("%Y-%m-%d %H:%M:%S"), msg)
    with open(logf, "a", encoding="utf-8") as f:
        f.write(line + "\n")
    print(line)


def apply(args):
    raw = sys.stdin.read()
    logdir = os.path.join(REPORTS, "drills") if args.drill else REPORTS
    os.makedirs(logdir, exist_ok=True)
    logf = os.path.join(logdir, "prod-watch-%s%s.log" % (now_sgt().strftime("%Y%m%d"), "-drill" if args.drill else ""))
    try:
        data = json.loads(raw)
    except ValueError:
        log_line(logf, "输入不是 JSON（fetch rc=%s，%d 字节），这次不比对" % (args.fetch_rc, len(raw)))
        alert_failure("bad-json", "prod_fetch.py 输出不是 JSON（rc=%s）" % args.fetch_rc, args.drill, logf)
        return 2
    ensure_ledger(args.ledger)
    lock = open(args.ledger + ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    last = latest(read_rows(args.ledger))
    changes, same = [], []
    for w in data.get("workers", []):
        prev = last.get(w["worker"])
        if prev and prev["deployment id"] == w["deployment_id"]:
            same.append("%s=%s" % (w["worker"], prev["版本"]))
            continue
        nums, ids = version_cells(w)
        row = [to_sgt(w.get("created_on")), w["worker"], nums, ids, w["deployment_id"], guess_commit(w),
               "ops · 23 哨兵", "—", "未报",
               "%s 发现；来源 %s%s" % (now_sgt().strftime("%m-%d %H:%M"), w.get("source") or "?",
                                    "；上一行 %s" % prev["版本"] if prev else "；台账里原来没有这个 Worker")]
        with open(args.ledger, "a", encoding="utf-8") as f:
            f.write(table_line(row) + "\n")
        changes.append((w, prev, nums, row[0]))
    fcntl.flock(lock, fcntl.LOCK_UN)
    errors = data.get("errors") or []
    if args.fetch_rc not in (0, None) or errors:
        kind = "fetch-rc-%s" % args.fetch_rc
        log_line(logf, "查询有错（rc=%s）：%s" % (args.fetch_rc, "；".join(errors)[:600]))
        alert_failure(kind, "；".join(errors)[:300], args.drill, logf)
        clear_failures({kind})
    else:
        clear_failures(set())
    for w, prev, nums, when in changes:
        old = prev["版本"] if prev else "（台账里没有）"
        task = "生产变更未报：%s %s→%s（%s SGT）" % (w["worker"], old, nums, when)
        body = ("%s 生产版本变了：%s → %s，deployment %s，%s SGT，commit %s。已在台账追加一行（状态「未报」）：%s"
                % (w["worker"], old, nums, w["deployment_id"], when, guess_commit(w), args.ledger))
        res = wake(task, body, args.drill)
        log_line(logf, "变化 %s %s→%s deployment %s；叫醒 coding-assistant：%s" % (
            w["worker"], old, nums, w["deployment_id"], " ".join(res)))
    log_line(logf, "完成：%d 个 Worker 未变（%s），%d 个变化，%d 个查询错误；台账 %s" % (
        len(same), ", ".join(same), len(changes), len(errors), args.ledger))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["apply", "latest"])
    ap.add_argument("--ledger", default=LEDGER)
    ap.add_argument("--fetch-rc", type=int, default=None)
    ap.add_argument("--drill", action="store_true")
    args = ap.parse_args()
    if args.cmd == "latest":
        for k, r in latest(read_rows(args.ledger)).items():
            print("%-28s %-8s %s  %s  %s" % (k, r["版本"], r["deployment id"], r["时间 SGT"], r["状态"]))
        return 0
    return apply(args)


if __name__ == "__main__":
    sys.exit(main())
