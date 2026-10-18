#!/bin/bash
# automation-reaper.sh [--dry-run] [--precheck]
# 关掉做完不退出的 Orca 自动任务 agent（PER-66 第 6 项）。Orca 自动任务起的 claude 回合结束后停在输入框，不会自己退出，
# 10-19 box 上挂着 16 个以上，最老的 38 小时，各占几百 MB。作为本机 Orca 自动任务的 precheck 定时跑（只跑脚本，不启动 agent）。
# 关哪些（全部满足）：
#   - claude / pi / codex 顶层进程，跑在 Orca 终端里，外面没包 notify-run（包了的是派活起的，不归这里管）；
#   - 终端 paneKey 在本机 `orca automations runs` 的运行记录里（= 自动任务起的）；
#   - 已写结果：Orca 记的这个终端的主 agent 状态是 done，且有最后一条回复（lastAssistantMessage 非空）；
#   - 空闲：状态最后一次变化超过 REAPER_IDLE_H（默认 2）小时。
#   没写结果的（状态不是 done，或 done 但没有回复，比如出错退出的回合）一律不动，只记日志。
# 怎么关：先用 agent-stop --mark-only 写「主动停止」标记（卡住检查看到就不报 agent_gone），再 `orca terminal close` 关掉它的终端
#   （进程收到 HUP 退出）；终端找不到时用 agent-stop 发 SIGTERM。每关一个记一行日志：pid、自动任务、运行开始时间、空闲多久、回复开头。
# 日志：REAPER_STATE_DIR（默认 ~/.orca-state/automation-reaper）/reaper.log。演练用 REAPER_ONLY（正则，只看 paneKey 匹配的）、
#   REAPER_PROBE（agent-probe 路径）、REAPER_AGENT_STOP（agent-stop 路径）、REAPER_ORCA（orca CLI 路径）。
# 退出码：0 正常；1 正常（--precheck，给 Orca 自动任务当 precheck，不启动 agent）；2 用法错误；3 有要关的没关掉；
#   4 脚本自己出错（含查不到 Orca 数据）。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" - "$@" <<'PYEOF'
import datetime, json, os, re, shutil, subprocess, sys, time

HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
if any(a not in ("--dry-run", "--precheck") for a in ARGS):
    print("用法：automation-reaper.sh [--dry-run] [--precheck]", file=sys.stderr)
    sys.exit(2)
DRY = "--dry-run" in ARGS
PRECHECK = "--precheck" in ARGS
IDLE_H = float(os.environ.get("REAPER_IDLE_H", "2"))
ONLY = re.compile(os.environ["REAPER_ONLY"]) if os.environ.get("REAPER_ONLY") else None
STATE_DIR = os.environ.get("REAPER_STATE_DIR") or os.path.join(HOME, ".orca-state/automation-reaper")
PROBE = os.environ.get("REAPER_PROBE") or os.path.join(HOME, ".local/bin/agent-probe")
AGENT_STOP = os.environ.get("REAPER_AGENT_STOP") or os.path.join(HOME, ".local/bin/agent-stop")
ORCA = (os.environ.get("REAPER_ORCA") or shutil.which("orca-ide") or shutil.which("orca")
        or (os.path.join(HOME, ".local/bin/orca") if os.path.exists(os.path.join(HOME, ".local/bin/orca")) else None)
        or "/Applications/Orca.app/Contents/Resources/bin/orca")
SGT = datetime.timezone(datetime.timedelta(hours=8))
NOW = time.time()
WATCH = {"claude", "pi", "codex"}
os.makedirs(STATE_DIR, exist_ok=True)
LOG_FILE = os.path.join(STATE_DIR, "reaper.log")


def log(msg):
    line = "%s %s%s" % (datetime.datetime.now(SGT).strftime("%F %T SGT"), "（dry-run）" if DRY else "", msg)
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def orca(*args, timeout=120):
    p = subprocess.run([ORCA] + list(args) + ["--json"], capture_output=True, text=True, timeout=timeout)
    d = json.loads(p.stdout)
    if not d.get("ok"):
        raise RuntimeError("orca %s 失败：%s" % (" ".join(args[:2]), json.dumps(d.get("error"), ensure_ascii=False)[:200]))
    return d["result"]


def fmt(t):
    return datetime.datetime.fromtimestamp(t, SGT).strftime("%m-%d %H:%M") if t else "?"


def main():
    runs = orca("automations", "runs")["runs"]
    by_pane = {}
    for r in runs:
        if r.get("terminalPaneKey"):
            by_pane[r["terminalPaneKey"]] = r
    terms = {}
    for t in orca("terminal", "list", "--limit", "1000")["terminals"]:
        if t.get("tabId") and t.get("connected") is not False:
            terms["%s:%s" % (t["tabId"], t.get("leafId"))] = t
    recs = {}
    for w in orca("worktree", "ps", "--limit", "1000")["worktrees"]:
        for a in w.get("agents") or []:
            if a.get("paneKey") and not a.get("parentPaneKey"):
                recs.setdefault(a["paneKey"], []).append(a)
    p = subprocess.run([sys.executable, PROBE, "--plain"], capture_output=True, text=True, timeout=60)
    procs = json.loads(p.stdout)["procs"]
    n_seen = n_close = n_keep = failed = 0
    for pr in procs:
        pane = pr.get("pane")
        if pr["kind"] != "agent" or pr.get("name") not in WATCH or pr.get("agent_anc_cwds") or pr.get("notify_anc") \
                or not pane or pane not in by_pane or (ONLY and not ONLY.search(pane)):
            continue
        n_seen += 1
        run = by_pane[pane]
        a = max(recs.get(pane) or [{}], key=lambda x: max(x.get("updatedAt") or 0, x.get("stateStartedAt") or 0))
        last = max(a.get("updatedAt") or 0, a.get("stateStartedAt") or 0) / 1000.0
        idle_h = (NOW - last) / 3600.0 if last else None
        msg = " ".join((a.get("lastAssistantMessage") or "").split())
        what = "pid %d（%s，自动任务「%s」，运行开始 %s，pane %s）" % (
            pr["pid"], pr["name"], run.get("title") or "?", fmt((run.get("startedAt") or 0) / 1000.0), pane[:8])
        if a.get("state") != "done" or not msg:
            if idle_h is not None and idle_h >= IDLE_H:
                log("不动 | %s | 没写结果（Orca 状态 %s%s），已 %.1f 小时没变化" % (
                    what, a.get("state") or "没有记录", "，没有回复" if a.get("state") == "done" else "", idle_h))
            n_keep += 1
            continue
        if idle_h is None or idle_h < IDLE_H:
            n_keep += 1
            continue
        t = terms.get(pane)
        log("关 | %s | 已写结果，空闲 %.1f 小时 | 回复开头：%s" % (what, idle_h, msg[:80]))
        if DRY:
            n_close += 1
            continue
        reason = "automation-reaper：自动任务「%s」已写结果，空闲 %.1f 小时" % (run.get("title") or "?", idle_h)
        sp = subprocess.run([AGENT_STOP, "--by", "automation-reaper", "--reason", reason]
                            + (["--mark-only"] if t else []) + [str(pr["pid"])], capture_output=True, text=True, timeout=60)
        if sp.returncode != 0:
            log("  失败：agent-stop 退出码 %d：%s" % (sp.returncode, (sp.stderr or sp.stdout).strip()[:200]))
            failed += 1
            continue
        if t:
            try:
                orca("terminal", "close", "--terminal", t["handle"], timeout=60)
            except (RuntimeError, ValueError, subprocess.TimeoutExpired) as e:
                log("  失败：关终端 %s 出错（%s），改发 SIGTERM" % (t["handle"], e))
                try:
                    os.kill(pr["pid"], 15)
                except OSError as e2:
                    log("  失败：SIGTERM 也没发出去：%s" % e2)
                    failed += 1
                    continue
        for _ in range(20):
            time.sleep(0.5)
            try:
                os.kill(pr["pid"], 0)
            except OSError:
                break
        else:
            log("  失败：10 秒后 pid %d 还在" % pr["pid"])
            failed += 1
            continue
        log("  已关（%s）" % ("关了终端 %s" % t["handle"] if t else "终端找不到，发了 SIGTERM"))
        n_close += 1
    log("完成：自动任务起的 agent %d 个，关 %d 个，留着 %d 个，失败 %d 个（空闲阈值 %g 小时）" % (
        n_seen, n_close, n_keep, failed, IDLE_H))
    return 3 if failed else 0


try:
    rc = main()
except Exception as e:
    import traceback
    log("脚本出错：%s" % traceback.format_exc()[-1200:])
    rc = 4
sys.exit(1 if (PRECHECK and rc == 0) else rc)
PYEOF
