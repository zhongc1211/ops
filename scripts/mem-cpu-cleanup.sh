#!/bin/bash
# mem-cpu-cleanup.sh [--dry-run] [--trigger nightly|pressure|manual] | --pressure-check
# 清理闲置的 claude 进程，并报告异常的 Chrome helper（Orca 自动化「内存与 CPU 日常清理」调用）。
#
# 关闭条件（全部满足才关）：
#   进程启动超过 24 小时；闲置超过 24 小时（最后一条对话消息和最后一次状态变化都在 24 小时前）；
#   进程树 CPU 低于 1%；并且所在工作区已经没有在跑的任务：
#     工作区对应的 Linear issue 全部已关（completed/canceled），或者
#     工作区没有 issue 编号、同一工作区里还有更新的 claude（旧会话、重复会话，只留最新的那个）。
# 一律跳过：启动不到 24 小时的；最近 1 小时内有输出的；会话状态不是 idle 的；工作区名或 Orca 关联里带
#   PER/FDV 编号、对应 issue 还没关（或查不到状态）的，即使是重复会话也不关；运行本脚本的会话自身；
#   工作目录、闲置时间判断不了的。
# 关之前：对 cwd 跑 git status，有没提交的改动就把这些文件打包到 ~/archive/<工作区>/<日期>/，不删任何文件；
#   打包失败就不关。先发 SIGTERM，30 秒后还在就发 SIGKILL。只按确认过的 PID 操作。
# Chrome：只报告运行超过 24 小时、CPU 超过 50% 的 helper 进程，不杀。
# 报告：每次运行在 ~/orca/workspaces/ops/reports/cleanup-<日期>.md 追加一节。
# webhook：只有关不掉的进程或 Chrome 异常才 POST 到 ~/.config/grokbot/stuck-webhook.env，多条合并成一条
#   {bot,task,worktree,status,note}；同一个 Chrome 进程只报一次。URL 和 KEY 不会出现在输出和报告里。
# --pressure-check：给「负载触发」自动化做前置检查。5 分钟 load 超过 2×核数，或内存剩余低于 25%，
#   并且距上次运行超过 CLEANUP_PRESSURE_COOLDOWN_HOURS（默认 3）小时时 exit 0，否则 exit 1。
# --dry-run：只判断和写报告，不打包、不发信号、不 POST、不记状态。
# 退出码：0 正常；2 Orca 查询失败（不关任何进程）；3 有进程关不掉或 webhook 发送失败。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" - "$@" <<'PYEOF'
import datetime, json, os, re, shutil, signal, subprocess, sys, tempfile, time

HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
DRY = "--dry-run" in ARGS
TRIGGER = ARGS[ARGS.index("--trigger") + 1] if "--trigger" in ARGS and len(ARGS) > ARGS.index("--trigger") + 1 else "manual"
env_f = lambda k, d: float(os.environ.get(k, d))
MIN_AGE_H = env_f("CLEANUP_MIN_AGE_HOURS", "24")
IDLE_H = env_f("CLEANUP_IDLE_HOURS", "24")
RECENT_H = env_f("CLEANUP_RECENT_OUTPUT_HOURS", "1")
MAX_CPU = env_f("CLEANUP_MAX_CPU", "1")
TERM_WAIT = env_f("CLEANUP_TERM_WAIT_SECONDS", "30")
CHROME_AGE_H = env_f("CLEANUP_CHROME_AGE_HOURS", "24")
CHROME_CPU = env_f("CLEANUP_CHROME_CPU", "50")
LOAD_FACTOR = env_f("CLEANUP_LOAD_FACTOR", "2")
MEM_FREE_MIN = env_f("CLEANUP_MEM_FREE_MIN", "25")
COOLDOWN_H = env_f("CLEANUP_PRESSURE_COOLDOWN_HOURS", "3")
ENV_FILE = os.environ.get("CLEANUP_ENV_FILE") or os.path.join(HOME, ".config/grokbot/stuck-webhook.env")
STATE_DIR = os.environ.get("CLEANUP_STATE_DIR") or os.path.join(HOME, ".orca-state/mem-cpu-cleanup")  # 这几个覆盖项只给测试用
REPORT_DIR = os.environ.get("CLEANUP_REPORT_DIR") or os.path.join(HOME, "orca/workspaces/ops/reports")
ARCHIVE_ROOT = os.environ.get("CLEANUP_ARCHIVE_ROOT") or os.path.join(HOME, "archive")
CLAUDE_DIR = os.environ.get("CLEANUP_CLAUDE_DIR") or os.path.join(HOME, ".claude")
ONLY_PIDS = {int(x) for x in os.environ.get("CLEANUP_ONLY_PIDS", "").split(",") if x.strip().isdigit()}  # 测试时只处理这些 PID
LAST_RUN = os.path.join(STATE_DIR, "last-run")
CHROME_SEEN = os.path.join(STATE_DIR, "chrome-notified.json")
SGT = datetime.timezone(datetime.timedelta(hours=8))
NOW = time.time()
os.makedirs(STATE_DIR, exist_ok=True)
ISSUE_RUN = re.compile(r"\b(PER|FDV)-(\d+(?:\s*/\s*\d+)*)", re.I)


def run(cmd, timeout=60, **kw):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)
        return p.returncode, p.stdout, p.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def fmt_h(h):
    if h is None:
        return "未知"
    return "%.0f 分钟" % (h * 60) if h < 1 else ("%.1f 小时" % h if h < 48 else "%.1f 天" % (h / 24))


def clock(ts):
    return datetime.datetime.fromtimestamp(ts, SGT).strftime("%m-%d %H:%M") if ts else "未知"


# ---- 系统负载 ----
def pressure():
    ncpu = os.cpu_count() or 1
    load = os.getloadavg()
    _, out, _ = run(["memory_pressure"], 30)
    m = re.search(r"free percentage:\s*(\d+)%", out)
    free = int(m.group(1)) if m else None
    why = []
    if load[1] > LOAD_FACTOR * ncpu:
        why.append("5 分钟 load %.1f 超过 %g×%d 核" % (load[1], LOAD_FACTOR, ncpu))
    if free is not None and free < MEM_FREE_MIN:
        why.append("内存剩余 %d%% 低于 %g%%" % (free, MEM_FREE_MIN))
    return {"ncpu": ncpu, "load": load, "free": free, "why": why}


if "--pressure-check" in ARGS:
    pr = pressure()
    try:
        since = (NOW - float(open(LAST_RUN).read().strip())) / 3600.0
    except (OSError, ValueError):
        since = None
    desc = "load %.1f/%.1f/%.1f（%d 核），内存剩余 %s%%" % (pr["load"] + (pr["ncpu"], pr["free"] if pr["free"] is not None else "?"))
    if not pr["why"]:
        print("不触发：%s" % desc)
        sys.exit(1)
    if since is not None and since < COOLDOWN_H:
        print("不触发：%s，但上次运行在 %s 前，冷却 %g 小时" % ("；".join(pr["why"]), fmt_h(since), COOLDOWN_H))
        sys.exit(1)
    print("触发：%s" % "；".join(pr["why"]))
    sys.exit(0)


# ---- 进程表 ----
def etime_s(s):
    d, _, rest = s.rpartition("-")
    parts = [int(x) for x in rest.split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    return (int(d) if d else 0) * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]


def ps_table():
    rc, out, err = run(["ps", "-Ao", "pid=,ppid=,pcpu=,etime=,tty=,comm="], 30)
    procs = {}
    for ln in out.splitlines():
        f = ln.split(None, 5)
        if len(f) < 6:
            continue
        try:
            procs[int(f[0])] = {"pid": int(f[0]), "ppid": int(f[1]), "cpu": float(f[2]), "age": etime_s(f[3]),
                                "tty": f[4], "comm": f[5]}
        except ValueError:
            continue
    return procs


def descendants(procs, pid):
    kids, out, todo = {}, [], [pid]
    for p in procs.values():
        kids.setdefault(p["ppid"], []).append(p["pid"])
    while todo:
        for k in kids.get(todo.pop(), []):
            out.append(k)
            todo.append(k)
    return out


def is_claude(comm):
    if "Claude.app" in comm:
        return False  # 桌面版和它的 helper 不算
    return os.path.basename(comm) == "claude" or re.search(r"/claude/versions/[^/]+$", comm) is not None


def lstart(pid):
    return run(["ps", "-o", "lstart=", "-p", str(pid)], 10)[1].strip()


def cwd_of(pid):
    _, out, _ = run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], 20)
    for ln in out.splitlines():
        if ln.startswith("n"):
            return ln[1:]
    return None


# ---- claude 会话的最后活动时间 ----
def session_info(pid, cwd):
    """返回 {status, last_output, idle_since, source}。读 ~/.claude/sessions/<pid>.json 和对应的对话记录。"""
    info = {"status": None, "last_output": None, "idle_since": None, "source": ""}
    try:
        s = json.load(open(os.path.join(CLAUDE_DIR, "sessions/%d.json" % pid)))
    except (OSError, ValueError):
        s = None
    transcript = None
    if s:
        info["status"] = s.get("status")
        changed = max(float(s.get("statusUpdatedAt") or 0), float(s.get("updatedAt") or 0)) / 1000.0 or None
        info["idle_since"] = changed
        sid = s.get("sessionId")
        proj = os.path.join(CLAUDE_DIR, "projects")
        if sid and os.path.isdir(proj):
            for d in os.listdir(proj):
                cand = os.path.join(proj, d, sid + ".jsonl")
                if os.path.isfile(cand):
                    transcript = cand
                    break
    if transcript:
        last = None
        try:
            with open(transcript, "rb") as f:
                f.seek(max(0, os.path.getsize(transcript) - 400000))
                for ln in f.read().split(b"\n"):
                    try:
                        d = json.loads(ln)
                    except ValueError:
                        continue
                    if d.get("type") in ("assistant", "user", "system") and d.get("timestamp"):
                        try:
                            ts = datetime.datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp()
                        except ValueError:
                            continue
                        last = max(last or 0, ts)
        except OSError:
            pass
        if last:
            info["last_output"] = last
            info["idle_since"] = max(last, info["idle_since"] or 0)
            info["source"] = "对话记录"
    if info["idle_since"] and not info["source"]:
        info["source"] = "会话状态"
    return info


# ---- 工作区和 Linear ----
def orca_json(args):
    orca = shutil.which("orca-ide") or shutil.which("orca") or "/Applications/Orca.app/Contents/Resources/bin/orca"
    rc, out, err = run([orca] + args + ["--json"], 90)
    if rc != 0:
        return None
    try:
        d = json.loads(out)
    except ValueError:
        return None
    return d.get("result") if d.get("ok") else None


_issue_cache = {}


def issue_state(ident):
    """返回 (是否已关, 状态说明)。查不到按没关处理。"""
    if ident not in _issue_cache:
        res = orca_json(["linear", "issue", ident])
        st = ((res or {}).get("issue") or {}).get("state") or {}
        if not st.get("type"):
            _issue_cache[ident] = (False, "状态查不到")
        else:
            _issue_cache[ident] = (st["type"] in ("completed", "canceled"), st.get("name") or st["type"])
    return _issue_cache[ident]


def issue_ids(*texts):
    ids = []
    for t in texts:
        for pre, nums in ISSUE_RUN.findall(t or ""):
            for n in re.split(r"\s*/\s*", nums):
                i = "%s-%s" % (pre.upper(), n)
                if i not in ids:
                    ids.append(i)
    return ids


def workspace_of(cwd, worktrees):
    """cwd → {path, name, ids}。先按 Orca 工作区最长前缀匹配，匹配不到用 git 顶层目录。"""
    best = None
    for w in worktrees:
        p = (w.get("path") or "").rstrip("/")
        if p and (cwd == p or cwd.startswith(p + "/")) and (best is None or len(p) > len(best["path"])):
            best = {"path": p, "name": w.get("displayName") or os.path.basename(p), "orca": True,
                    "ids": issue_ids(w.get("linkedLinearIssue"), os.path.basename(p), w.get("displayName"))}
    if best:
        return best
    rc, out, _ = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], 20)
    top = out.strip() if rc == 0 and out.strip() else cwd
    return {"path": top, "name": os.path.basename(top), "orca": False, "ids": issue_ids(os.path.basename(top))}


# ---- 关之前打包没提交的改动 ----
def uncommitted(cwd):
    """返回 (git 顶层目录, 文件列表, git status 文本)；不是 git 仓库返回 (None, [], 说明)。"""
    rc, out, err = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], 20)
    if rc != 0 or not out.strip():
        return None, [], "不是 git 仓库"
    top = out.strip()
    _, status, _ = run(["git", "-C", top, "status", "--short"], 60)
    files = []
    for cmd in (["diff", "--name-only", "-z", "HEAD"], ["ls-files", "-z", "--others", "--exclude-standard"]):
        _, o, _ = run(["git", "-C", top] + cmd, 60)
        files += [f for f in o.split("\0") if f]
    files = [f for f in dict.fromkeys(files) if os.path.lexists(os.path.join(top, f))]
    return top, files, status


def archive(ws_name, top, files, status):
    """把没提交的文件打包（只复制，不删）。返回 (包路径或 None, 错误说明)。"""
    day = datetime.datetime.now(SGT).strftime("%Y-%m-%d")
    dest = os.path.join(ARCHIVE_ROOT, re.sub(r"[/\0]", "_", ws_name), day)
    try:
        os.makedirs(dest, exist_ok=True)
        stamp = datetime.datetime.now(SGT).strftime("%H%M%S")
        tarball = os.path.join(dest, "uncommitted-%s.tar.gz" % stamp)
        with open(os.path.join(dest, "git-status-%s.txt" % stamp), "w") as f:
            f.write("仓库：%s\n\n%s" % (top, status))
        p = subprocess.run(["tar", "-czf", tarball, "-C", top, "--null", "-T", "-"],
                           input="\0".join(files).encode("utf-8"), capture_output=True, timeout=600)
        if p.returncode != 0:
            return None, "tar 退出码 %d" % p.returncode
        return tarball, None
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, type(e).__name__


# ---- webhook ----
def post(cfg, payload):
    """用 curl 发；URL 和 KEY 经 stdin 传给 curl，不出现在进程参数里。返回 HTTP 状态码，或失败说明。"""
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as body:
        json.dump(payload, body, ensure_ascii=False)
        body.flush()
        esc = lambda v: v.replace("\\", "\\\\").replace('"', '\\"')
        conf = 'url = "%s"\nheader = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' % (
            esc(cfg["URL"]), esc(cfg["KEY"]))
        try:
            p = subprocess.run(["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", "-X", "POST",
                                "--data-binary", "@" + body.name, "-K", "-"],
                               input=conf, capture_output=True, text=True, timeout=40)
        except (OSError, subprocess.TimeoutExpired) as e:
            return type(e).__name__
    if p.returncode != 0:
        return "curl 退出码 %d" % p.returncode
    return int(p.stdout) if p.stdout.strip().isdigit() else "无状态码"


def alive(pid, started):
    return bool(started) and lstart(pid) == started


def main():
    before = pressure()
    procs = ps_table()
    me = set()
    p = os.getpid()
    while p in procs and p > 1:
        me.add(p)
        p = procs[p]["ppid"]

    wl = orca_json(["worktree", "list", "--limit", "500"])
    worktrees = (wl or {}).get("worktrees") if isinstance(wl, dict) else wl
    orca_ok = worktrees is not None
    worktrees = worktrees or []

    # 1) 所有 claude 进程：cwd、运行时长、CPU
    rows = []
    for pr in procs.values():
        if not is_claude(pr["comm"]):
            continue
        tree = [pr["pid"]] + descendants(procs, pr["pid"])
        r = dict(pr, started=lstart(pr["pid"]), cwd=cwd_of(pr["pid"]), kids=len(tree) - 1,
                 tree_cpu=sum(procs[x]["cpu"] for x in tree if x in procs))
        r["ws"] = workspace_of(r["cwd"], worktrees) if r["cwd"] else None
        r.update(session_info(r["pid"], r["cwd"]))
        rows.append(r)
    time.sleep(3)  # CPU 取两次里较高的一次，避免刚好采到空档
    again = ps_table()
    for r in rows:
        tree = [r["pid"]] + descendants(again, r["pid"])
        r["tree_cpu"] = max(r["tree_cpu"], sum(again[x]["cpu"] for x in tree if x in again))
    rows.sort(key=lambda r: (r["ws"]["path"] if r["ws"] else "", r["age"]))

    by_ws = {}
    for r in rows:
        if r["ws"]:
            by_ws.setdefault(r["ws"]["path"], []).append(r)
    newest = {path: min(rs, key=lambda r: r["age"])["pid"] for path, rs in by_ws.items()}

    # 2) 3) 5) 逐个判断
    for r in rows:
        age_h = r["age"] / 3600.0
        out_h = max(0.0, NOW - r["last_output"]) / 3600.0 if r["last_output"] else None
        idle_h = max(0.0, NOW - r["idle_since"]) / 3600.0 if r["idle_since"] else None
        r["idle_h"], r["out_h"] = idle_h, out_h
        ws = r["ws"]
        skip = lambda why: r.update(action="skip", reason=why)
        if r["pid"] in me:
            skip("运行本脚本的会话自身")
        elif ONLY_PIDS and r["pid"] not in ONLY_PIDS:
            skip("测试模式，不在 CLEANUP_ONLY_PIDS 里")
        elif not orca_ok:
            skip("Orca 工作区查询失败，本次不关任何进程")
        elif not r["cwd"] or not ws:
            skip("查不到工作目录")
        elif age_h < MIN_AGE_H:
            skip("启动才 %s，不到 %g 小时" % (fmt_h(age_h), MIN_AGE_H))
        elif out_h is not None and out_h < RECENT_H:
            skip("%s 前还有输出" % fmt_h(out_h))
        elif r["status"] not in (None, "idle"):
            skip("会话状态是 %s，不是 idle" % r["status"])
        elif idle_h is None:
            skip("判断不了闲置时间（找不到会话记录）")
        elif idle_h < IDLE_H:
            skip("闲置 %s，不到 %g 小时" % (fmt_h(idle_h), IDLE_H))
        elif r["tree_cpu"] >= MAX_CPU:
            skip("进程树 CPU %.1f%%，不低于 %g%%" % (r["tree_cpu"], MAX_CPU))
        else:
            states = [(i,) + issue_state(i) for i in ws["ids"]]
            still = ["%s（%s）" % (i, name) for i, closed, name in states if not closed]
            dup = len(by_ws[ws["path"]]) > 1 and newest[ws["path"]] != r["pid"]
            if still:
                skip("工作区的 issue 还没关：%s%s" % ("、".join(still), "；是重复会话，但按规则不关" if dup else ""))
            elif states:
                r.update(action="close", reason="工作区的 issue 已关：%s" % "、".join("%s（%s）" % (i, n) for i, _, n in states))
            elif dup:
                r.update(action="close", reason="同一工作区有 %d 个 claude，这个是旧会话，保留最新的 PID %d" % (
                    len(by_ws[ws["path"]]), newest[ws["path"]]))
            else:
                skip("工作区没有 issue 编号，这是里面%s的会话，判断不了任务是否结束" % (
                    "最新" if len(by_ws[ws["path"]]) > 1 else "唯一"))

    # 4) 关：先打包没提交的改动，再 SIGTERM，30 秒后还在就 SIGKILL
    archived = {}  # git 顶层目录 → 结果说明
    for r in rows:
        if r["action"] != "close":
            continue
        top, files, status = uncommitted(r["cwd"])
        if top is None:
            r["git"] = "cwd 不是 git 仓库，没有可打包的改动"
        elif not files:
            r["git"] = "git status 干净"
        elif DRY:
            r["git"] = "有 %d 个没提交的文件，正式运行时会打包到 %s/" % (
                len(files), os.path.join(ARCHIVE_ROOT, r["ws"]["name"].replace("/", "_"), datetime.datetime.now(SGT).strftime("%Y-%m-%d")))
        else:
            if top not in archived:
                tarball, err = archive(r["ws"]["name"], top, files, status)
                archived[top] = (tarball, err, len(files))
            tarball, err, n = archived[top]
            if err:
                r.update(action="skip", reason="没提交的改动打包失败（%s），不关。原判断：%s" % (err, r["reason"]), git="打包失败")
                continue
            r["git"] = "有 %d 个没提交的文件，已打包到 %s" % (n, tarball)
        if DRY:
            r["result"] = "dry-run，未发信号"
            continue
        if not alive(r["pid"], r["started"]):
            r["result"] = "发信号前进程已经不在"
            continue
        try:
            os.kill(r["pid"], signal.SIGTERM)
        except OSError as e:
            r.update(result="SIGTERM 发送失败（%s）" % type(e).__name__, failed=True)
            continue
        deadline = time.time() + TERM_WAIT
        while time.time() < deadline and alive(r["pid"], r["started"]):
            time.sleep(1)
        if not alive(r["pid"], r["started"]):
            r["result"] = "SIGTERM 后退出"
            continue
        try:
            os.kill(r["pid"], signal.SIGKILL)
        except OSError:
            pass
        time.sleep(3)
        if alive(r["pid"], r["started"]):
            r.update(result="SIGTERM 等 %g 秒后发了 SIGKILL，进程仍在" % TERM_WAIT, failed=True)
        else:
            r["result"] = "SIGTERM 等 %g 秒没退出，SIGKILL 后退出" % TERM_WAIT

    # 7) Chrome helper：只报告
    chrome = []
    for pr in procs.values():
        if "Chrome Helper" not in pr["comm"] or pr["age"] / 3600.0 <= CHROME_AGE_H:
            continue
        cpu2 = again.get(pr["pid"], {}).get("cpu", 0.0)
        if min(pr["cpu"], cpu2) <= CHROME_CPU:
            continue
        _, args, _ = run(["ps", "-o", "args=", "-p", str(pr["pid"])], 10)
        m = re.search(r"--type=([\w-]+)", args)
        kind = m.group(1) if m else "browser"
        m = re.search(r"--utility-sub-type=([\w.]+)", args)
        if m:
            kind += "（%s）" % m.group(1)
        parent = procs.get(pr["ppid"], {}).get("comm", "?")
        chrome.append({"pid": pr["pid"], "kind": kind, "age": pr["age"], "cpu": (pr["cpu"], cpu2), "started": lstart(pr["pid"]),
                       "headless": "--headless" in args, "parent": "%d %s" % (pr["ppid"], os.path.basename(parent))})

    # 8) webhook：关不掉的进程 + 还没报过的 Chrome 异常，合并成一条
    failed = [r for r in rows if r.get("failed")]
    try:
        seen = json.load(open(CHROME_SEEN))
    except (OSError, ValueError):
        seen = {}
    ckey = lambda c: "%d|%s" % (c["pid"], c["started"])
    seen = {k: v for k, v in seen.items() if k in {ckey(c) for c in chrome}}
    chrome_new = [c for c in chrome if ckey(c) not in seen]
    items = ["关不掉：claude PID %d（%s）%s" % (r["pid"], r["ws"]["name"], r["result"]) for r in failed]
    items += ["Chrome 异常：helper PID %d，类型 %s，已运行 %s，CPU %.0f%%/%.0f%%，未自动处理" % (
        c["pid"], c["kind"], fmt_h(c["age"] / 3600.0), c["cpu"][0], c["cpu"][1]) for c in chrome_new]
    hook, rc = "没有关不掉的进程，也没有新的 Chrome 异常，不发 webhook", 0
    if items:
        kinds = (["kill_failed"] if failed else []) + (["chrome_abnormal"] if chrome_new else [])
        payload = {"bot": "ops", "task": "cleanup", "worktree": "MBA",
                   "status": kinds[0] if len(kinds) == 1 else "mixed",
                   "note": items[0] if len(items) == 1 else "共 %d 条：\n" % len(items) + "\n".join(
                       "%d. %s" % (i, t) for i, t in enumerate(items, 1))}
        cfg = {}
        if os.path.isfile(ENV_FILE):
            for ln in open(ENV_FILE):
                m = re.match(r"\s*(?:export\s+)?(URL|KEY)\s*=\s*(.*?)\s*$", ln)
                if m:
                    cfg[m.group(1)] = m.group(2).strip("'\"")
        if DRY:
            hook = "dry-run，正式运行时会 POST 1 条（含 %d 项）：`%s`" % (len(items), json.dumps(payload, ensure_ascii=False))
        elif not cfg.get("URL") or not cfg.get("KEY"):
            hook = "有 %d 项要报，但 webhook 没配好（%s 缺失或不完整），没有发送" % (len(items), ENV_FILE)
        else:
            code = post(cfg, payload)
            if isinstance(code, int) and 200 <= code < 300:
                hook = "已 POST 1 条（HTTP %d），含 %d 项" % (code, len(items))
                for c in chrome_new:
                    seen[ckey(c)] = NOW
            else:
                hook, rc = "POST 失败（%s），含 %d 项，下次运行重发" % (code, len(items)), 3
    elif chrome:
        hook = "Chrome 异常进程之前已经报过，不重复发 webhook"
    if not DRY:
        with open(CHROME_SEEN, "w") as f:
            json.dump(seen, f)
        with open(LAST_RUN, "w") as f:
            f.write("%d\n" % NOW)
    if failed:
        rc = 3
    if not orca_ok:
        rc = 2

    # ---- 报告 ----
    after = pressure()
    now = datetime.datetime.now(SGT)
    label = {"nightly": "夜间定时", "pressure": "负载触发", "manual": "手动"}.get(TRIGGER, TRIGGER)
    closed = [r for r in rows if r["action"] == "close"]
    skipped = [r for r in rows if r["action"] == "skip"]
    cell = lambda s: str(s).replace("|", "\\|").replace("\n", " ")
    sysline = lambda p: "load %.1f / %.1f / %.1f（%d 核，阈值 %g），内存剩余 %s%%（阈值 %g%%）" % (
        p["load"] + (p["ncpu"], LOAD_FACTOR * p["ncpu"], p["free"] if p["free"] is not None else "?", MEM_FREE_MIN))
    L = ["## %s %s%s" % (now.strftime("%H:%M"), label, "（dry-run）" if DRY else ""), ""]
    L.append("执行者：`scripts/mem-cpu-cleanup.sh%s`。%s" % (
        " --dry-run" if DRY else "", "dry-run 只判断，不打包、不发信号、不发 webhook。" if DRY else ""))
    L += ["", "- 运行前：%s%s" % (sysline(before), "。超过阈值：%s" % "；".join(before["why"]) if before["why"] else "。没有超过阈值"),
          "- 运行后：%s" % sysline(after),
          "- claude 进程 %d 个：%s %d 个，跳过 %d 个。" % (len(rows), "将关闭" if DRY else "关闭", len(closed), len(skipped)),
          "- Chrome 异常 helper %d 个。" % len(chrome),
          "- webhook：%s" % hook]
    if not orca_ok:
        L.append("- Orca 工作区查询失败，本次没有关任何进程。")
    L += ["", "### %s的 claude 进程" % ("将关闭" if DRY else "关闭"), ""]
    if closed:
        L += ["| PID | 工作区 | cwd | 已运行 | CPU | 闲置 | 原因 | 没提交的改动 | 结果 |", "|---|---|---|---|---|---|---|---|---|"]
        L += ["| %d | %s | %s | %s | %.1f%% | %s | %s | %s | %s |" % (
            r["pid"], cell(r["ws"]["name"]), cell(r["cwd"]), fmt_h(r["age"] / 3600.0), r["tree_cpu"], fmt_h(r["idle_h"]),
            cell(r["reason"]), cell(r.get("git", "")), cell(r.get("result", ""))) for r in closed]
    else:
        L.append("没有。")
    L += ["", "### 跳过的 claude 进程", ""]
    if skipped:
        L += ["| PID | 工作区 | cwd | 已运行 | CPU | 最后输出 | 闲置 | 跳过原因 |", "|---|---|---|---|---|---|---|---|"]
        L += ["| %d | %s | %s | %s | %.1f%% | %s | %s | %s |" % (
            r["pid"], cell(r["ws"]["name"] if r["ws"] else "?"), cell(r["cwd"] or "?"), fmt_h(r["age"] / 3600.0), r["tree_cpu"],
            clock(r["last_output"]), fmt_h(r["idle_h"]), cell(r["reason"])) for r in skipped]
    else:
        L.append("没有。")
    L += ["", "CPU 是进程和它的子进程合计，取间隔 3 秒两次采样里较高的一次。闲置从最后一条对话消息和最后一次会话状态变化里较晚的那个算起。",
          "", "### Chrome helper（只报告，不处理）", ""]
    if chrome:
        L += ["| PID | 类型 | 父进程 | 已运行 | CPU（两次采样） | 说明 |", "|---|---|---|---|---|---|"]
        L += ["| %d | %s | %s | %s | %.0f%% / %.0f%% | %s |" % (
            c["pid"], c["kind"], cell(c["parent"]), fmt_h(c["age"] / 3600.0), c["cpu"][0], c["cpu"][1],
            ("无头 Chrome；" if c["headless"] else "") + ("首次发现" if c in chrome_new else "之前已报过")) for c in chrome]
    else:
        L.append("没有运行超过 %g 小时且 CPU 超过 %g%% 的 helper 进程。" % (CHROME_AGE_H, CHROME_CPU))
    L.append("")
    path = os.path.join(REPORT_DIR, "cleanup-%s.md" % now.strftime("%Y-%m-%d"))
    os.makedirs(REPORT_DIR, exist_ok=True)
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8") as f:
        if new:
            f.write("# 内存与 CPU 清理报告（%s）\n\n每次运行追加一节，时间是新加坡时间。\n\n" % now.strftime("%Y-%m-%d"))
        f.write("\n".join(L) + "\n")
    print("\n".join(L))
    print("报告：%s（退出码 %d）" % (path, rc))
    return rc


sys.exit(main())
PYEOF
