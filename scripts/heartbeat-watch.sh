#!/bin/bash
# heartbeat-watch.sh --target "名字|environment|自动任务 id|N 分钟" [--target ...] [--precheck] [--dry-run]
# 盯另一台机器上的检查任务有没有在跑（PER-65 第 3 项）。卡住检查 stuck-check.sh 每次跑完在 stdout 打一行
# 「@@HB {"ts","mode","rc","last_scan"}」，Orca 自动任务的运行记录会存 precheck 的 stdout；这里用
# `orca automations runs --id <id> --environment <env>` 读最新的心跳：
#   - 超过 N 分钟（默认 20）没有新心跳（Orca 调度器停了、脚本没在跑），或者心跳里的 last_scan（上次跑完的扫描）超过
#     N + STUCK_INTERVAL_MIN（默认 15）分钟没变（扫描每次超时被杀或每次出错），报警给 coding-assistant（kind heartbeat_stale）。
#     同一次中断只报一次。
#   - 恢复后报一次「已恢复」（kind heartbeat_recovered）。
#   - 运行记录查不到（连不上那台 Orca）连续 HB_UNREACH_MIN（默认 45）分钟，也按中断报一次（隧道常断几分钟，所以阈值放宽）。
#   - 目标自动任务建好不到 N 分钟、还没见过它的心跳时不判断（10-19 02:50 上线时两边同时建，iMac 先跑、误报过一次）；
#     建好时间取 `orca automations list` 的 createdAt。过了 N 分钟还没有心跳（一次都没跑、或跑了没打 @@HB）照报。
# 部署：box 上的自动任务盯 iMac 的「ops · 01 卡住工作检查」；iMac 上的自动任务盯 box 上这个脚本自己（它每次也打 @@HB）。
#   environment 写空串 = 本机 Orca。
# 自己的心跳也一样：main() 出错（rc 4）时 last_scan 不前进，盯它的另一个 heartbeat-watch 照样能报（PER-67 F8 同类）。
# 状态：HB_STATE_DIR（默认 ~/.orca-state/heartbeat-watch）/state.json、watch.log、heartbeat.json。
# webhook：~/.config/grokbot/webhooks/<bot>.env（URL、KEY）。演练用 STUCK_FORCE_BOT=ops-system（所有消息改发 ops-system；只换收件 bot，task 不加「[演练 叫醒通路]」，那是手动 notify-run 演练的前缀），
#   STUCK_WEBHOOK_DIR 可改目录。URL 和 KEY 只经 stdin 交给 curl，不进日志和输出。
# 退出码：0 正常；1 正常（--precheck：给 Orca 自动任务当 precheck 用，返回 1 不启动 agent）；2 用法错误；
#   3 有报警没发出去（下次再发）；4 脚本自己出错。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" - "$@" <<'PYEOF'
import datetime, json, os, re, shutil, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
DRY = "--dry-run" in ARGS
PRECHECK = "--precheck" in ARGS
STATE_DIR = os.environ.get("HB_STATE_DIR") or os.path.join(HOME, ".orca-state/heartbeat-watch")
WEBHOOK_DIR = os.environ.get("STUCK_WEBHOOK_DIR") or os.path.join(HOME, ".config/grokbot/webhooks")
FORCE_BOT = os.environ.get("STUCK_FORCE_BOT")
BOT = "coding-assistant"
UNREACH_MIN = float(os.environ.get("HB_UNREACH_MIN", "45"))
INTERVAL_MIN = float(os.environ.get("STUCK_INTERVAL_MIN", "15"))
SGT = datetime.timezone(datetime.timedelta(hours=8))
NOW = time.time()
SECRETS = []
ORCA = (os.environ.get("HB_ORCA") or shutil.which("orca-ide") or shutil.which("orca")
        or "/Applications/Orca.app/Contents/Resources/bin/orca")


def usage():
    print('用法：heartbeat-watch.sh --target "名字|environment|自动任务 id|N 分钟" [--target ...] [--precheck] [--dry-run]',
          file=sys.stderr)
    sys.exit(2)


TARGETS = []
for i, a in enumerate(ARGS):
    if a == "--target":
        if i + 1 >= len(ARGS):
            usage()
        f = ARGS[i + 1].split("|")
        if len(f) != 4 or not f[0] or not re.fullmatch(r"[0-9a-f-]{8,}", f[2]):
            usage()
        try:
            TARGETS.append({"name": f[0], "env": f[1] or None, "id": f[2], "max": float(f[3] or 20)})
        except ValueError:
            usage()
if not TARGETS:
    usage()
os.makedirs(STATE_DIR, exist_ok=True)
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOG_FILE = os.path.join(STATE_DIR, "watch.log")


def log(msg):
    for s in SECRETS:
        msg = msg.replace(s, "<已隐藏>")
    line = "%s %s" % (datetime.datetime.now(SGT).strftime("%F %T SGT"), msg)
    print(line, flush=True)
    if not DRY:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


def fmt(t):
    return datetime.datetime.fromtimestamp(t, SGT).strftime("%m-%d %H:%M") if t else "从没有"


def load_json(path, default):
    try:
        d = json.load(open(path, encoding="utf-8"))
        return d if isinstance(d, type(default)) else default
    except (OSError, ValueError):
        return default


def save_json(path, data):
    if DRY:
        return
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def runs_of(t):
    """最新的心跳（dict）或 None，和查询错误。3 次，间隔 8 秒。"""
    cmd = [ORCA, "automations", "runs", "--id", t["id"]] + (["--environment", t["env"]] if t["env"] else []) + ["--json"]
    err = None
    for n in range(3):
        if n:
            time.sleep(8)
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
            d = json.loads(p.stdout)
        except (OSError, subprocess.TimeoutExpired, ValueError) as e:
            err = type(e).__name__
            continue
        if not d.get("ok"):
            err = json.dumps(d.get("error"), ensure_ascii=False)[:200]
            continue
        runs = (d.get("result") or {}).get("runs") or []
        best = None
        for r in runs:
            out = (r.get("precheckResult") or {}).get("stdout") or ""
            for m in re.finditer(r"^@@HB (\{.*\})\s*$", out, re.M):
                try:
                    hb = json.loads(m.group(1))
                except ValueError:
                    continue
                if isinstance(hb.get("ts"), (int, float)) and (best is None or hb["ts"] > best["ts"]):
                    best = hb
        return {"hb": best, "runs": len(runs), "newest_run": max([r.get("createdAt") or 0 for r in runs] or [0]) / 1000.0}, None
    return None, err


def created_at(t):
    """目标自动任务的建好时间（秒）；查不到返回 None。"""
    cmd = [ORCA, "automations", "list"] + (["--environment", t["env"]] if t["env"] else []) + ["--json"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
        d = json.loads(p.stdout)
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    for a in ((d.get("result") or {}).get("automations") or []) if d.get("ok") else []:
        if a.get("id") == t["id"] and a.get("createdAt"):
            return a["createdAt"] / 1000.0
    return None


def read_env(path):
    cfg = {}
    try:
        for ln in open(path):
            m = re.match(r"\s*(?:export\s+)?(URL|KEY)\s*=\s*(.*?)\s*$", ln)
            if m:
                cfg[m.group(1)] = m.group(2).strip("'\"")
    except OSError:
        return None
    SECRETS.extend(v for v in cfg.values() if v and v not in SECRETS)
    return cfg if cfg.get("URL") and cfg.get("KEY") else None


def post(payload):
    to = FORCE_BOT or BOT
    cfg = read_env(os.path.join(WEBHOOK_DIR, to + ".env")) if re.fullmatch(r"[A-Za-z0-9._-]+", to) else None
    if cfg is None:
        log("没有 %s 的 webhook 配置，没发：%s" % (to, payload["task"]))
        return False
    payload = dict(payload, bot=to)
    if DRY:
        log("dry-run，将 POST 给 %s：%s" % (to, json.dumps(payload, ensure_ascii=False)))
        return True
    esc = lambda v: v.replace("\\", "\\\\").replace('"', '\\"')
    conf = 'url = "%s"\nheader = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' % (
        esc(cfg["URL"]), esc(cfg["KEY"]))
    for n, wait in enumerate([0, 5, 15, 45]):
        time.sleep(wait)
        with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as body:
            json.dump(payload, body, ensure_ascii=False)
            body.flush()
            try:
                p = subprocess.run(["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", "-X", "POST",
                                    "--data-binary", "@" + body.name, "-K", "-"], input=conf, capture_output=True,
                                   text=True, timeout=40)
                code = p.stdout.strip()
            except (OSError, subprocess.TimeoutExpired) as e:
                code = type(e).__name__
        log("POST %s → %s → %s（第 %d 次）" % (payload["kind"], to, code or "无响应", n + 1))
        if re.fullmatch(r"2\d\d", code or ""):
            return True
    return False


def main():
    state = load_json(STATE_FILE, {})
    failed = 0
    for t in TARGETS:
        st = state.setdefault(t["id"], {})
        res, err = runs_of(t)
        down, why = False, None
        if res is None:
            st["fail_since"] = st.get("fail_since") or NOW
            mins = (NOW - st["fail_since"]) / 60.0
            log("%s：运行记录查不到（%s），已连续 %.0f 分钟" % (t["name"], err, mins))
            if mins >= UNREACH_MIN:
                down, why = True, "连不上 %s 的 Orca，%.0f 分钟查不到「%s」的运行记录（%s），心跳没法确认" % (
                    t["env"] or "本机", mins, t["name"], (err or "")[:120])
            else:
                continue  # 还在宽限里先不判断；已经报过中断的维持原状，等查到再判断恢复
        else:
            st.pop("fail_since", None)
            hb = res["hb"]
            if not st.get("last_hb") and (hb is None or (NOW - hb["ts"]) / 60.0 > t["max"]):
                # 还没见过它的心跳：建好不到 N 分钟的不判断（10-19 02:50 上线时 iMac 先跑、误报过一次）。
                # 见过心跳之后、或建好超过 N 分钟还没有，照报。建好时间查不到时退回旧办法：一次运行记录都没有就不判断。
                made = created_at(t)
                if made is not None and (NOW - made) / 60.0 < t["max"]:
                    log("%s：自动任务建好 %.0f 分钟（不到 %g 分钟），还没有心跳，这次不判断" % (t["name"], (NOW - made) / 60.0, t["max"]))
                    continue
                if made is None and res["runs"] == 0:
                    log("%s：还没有运行记录，建好时间也没查到，这次不判断" % t["name"])
                    continue
            if hb is None:
                down, why = True, "最近 %d 次运行记录里没有心跳行（@@HB），最新一次运行在 %s" % (res["runs"], fmt(res["newest_run"]))
            else:
                age = (NOW - hb["ts"]) / 60.0
                scan_age = (NOW - hb["last_scan"]) / 60.0 if hb.get("last_scan") else None
                st["last_hb"] = hb["ts"]
                if age > t["max"]:
                    down, why = True, "最新心跳在 %s，已 %.0f 分钟没有新的（阈值 %g 分钟）：Orca 调度器停了或脚本没在跑" % (
                        fmt(hb["ts"]), age, t["max"])
                elif scan_age is not None and scan_age > t["max"] + INTERVAL_MIN:
                    down, why = True, "心跳还在（%s），但上次跑完的扫描在 %s，已 %.0f 分钟没跑完：扫描每次超时被杀或每次出错" % (
                        fmt(hb["ts"]), fmt(hb["last_scan"]), scan_age)
                else:
                    log("%s：正常（最新心跳 %s，%.1f 分钟前，rc %s%s）" % (
                        t["name"], fmt(hb["ts"]), age, hb.get("rc"),
                        "，上次扫描 %.0f 分钟前" % scan_age if scan_age is not None else ""))
        if down:
            if st.get("alerted"):
                log("%s：还在中断（%s 起已报过，不重复报）：%s" % (t["name"], fmt(st["alerted"]), why))
                continue
            log("%s：中断：%s" % (t["name"], why))
            ok = post({"task": "检查任务没在跑：%s" % t["name"], "worktree": t["env"] or "本机", "status": "stuck",
                       "kind": "heartbeat_stale", "machine": t["env"] or "本机", "source": "heartbeat-watch",
                       "note": "%s。自动任务 id %s。去那台机器看 Orca 是否开着、自动任务是否启用、`orca automations runs --id %s` "
                               "最近几次的结果。" % (why, t["id"], t["id"])})
            if ok:
                st["alerted"], st["why"] = NOW, why
            else:
                failed += 1
        elif st.get("alerted"):
            ok = post({"task": "检查任务已恢复：%s" % t["name"], "worktree": t["env"] or "本机", "status": "recovered",
                       "kind": "heartbeat_recovered", "machine": t["env"] or "本机", "source": "heartbeat-watch",
                       "note": "%s 的心跳恢复了（最新 %s）。中断从约 %s 起（%s 报的：%s）。" % (
                           t["name"], fmt(st.get("last_hb")), fmt(st["alerted"]), fmt(st["alerted"]), st.get("why"))})
            if ok:
                log("%s：已恢复，报过一次" % t["name"])
                st.pop("alerted", None), st.pop("why", None)
            else:
                failed += 1
    save_json(STATE_FILE, state)
    return 3 if failed else 0


try:
    rc = main()
except Exception:
    import traceback
    log("脚本出错：%s" % traceback.format_exc()[-1500:])
    rc = 4
hb = {"ts": int(time.time()), "mode": "heartbeat-watch", "rc": rc, "last_scan": int(time.time())}
if rc == 4:  # 没跑完：last_scan 沿用上次的（第一次出错时记下的这次时间会一直留着）
    hb["last_scan"] = int(load_json(os.path.join(STATE_DIR, "heartbeat.json"), {}).get("last_scan") or hb["last_scan"])
if not DRY:
    save_json(os.path.join(STATE_DIR, "heartbeat.json"), hb)
    print("@@HB " + json.dumps(hb), flush=True)
sys.exit(1 if (PRECHECK and rc == 0) else rc)
PYEOF
