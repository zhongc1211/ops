#!/bin/bash
# ws-cleanup.sh [--execute] [--list-only] [--out DIR]
# Orca 工作区 / 终端夜间清理（纯脚本，不起模型）。规则：reports/ws-cleanup-dryrun-1021/RESULT.md 和 .orca-task/RULES-DRAFT.md
# （Zack 10-21 01:43 定）。**默认 dry-run**：只读，写出 worktrees.tsv、terminals.tsv、summary.md；只有加 --execute 才会备份、
# `orca worktree rm`（不加 --force）、`orca terminal close`。
#   工作区从上往下判，第一条命中的就是结论：W1 main/bare → W2 本任务所在 → W3 别的机器 → W5 agent 在跑 → W6 终端有活进程
#   → W4 目录已不在（rm 只删记录） → W7 未提交 → W8 未推送 → W9 open PR → W10 Linear 未关 → W11 没有做完的证据
#   → W12 近 IDLE_H 小时有活动 → W13 有要备份的 git 忽略文件（先备份再 rm） → W14 rm。W16：git 里有、Orca 里没有的 worktree，只列出。
#   终端：T3 本终端 → T1 agent → T6 有子进程 → T2 屏幕上有 resume id → T4 空 shell / T5 进程已不在 → 关。
#   任何查询失败都算跳过，不算通过。MBA 一律只列出（--list-only），box 不跑。
# 进程只用 `ps -A -o pid,ppid,comm`；git 忽略的文件只看名字和大小，不读内容；终端屏幕只用来找 resume id，不写进输出。
# 退出码：0 正常；2 用法错误；3 --execute 有没做成的；4 查不到 Orca 数据（不写结果文件）。
# 演练用：WS_ORCA、WS_GH（命令路径）、WS_PS_FILE（ps 输出文件）、WS_NOW（epoch 秒）、WS_HOST（iMac/MBA）、WS_SELF（本任务工作区）、
#   WS_SELF_TERM（本终端 handle）、WS_ARCHIVE（备份根目录，默认 ~/ops-archive/ws-cleanup）、WS_IDLE_H（默认 24）、WS_NO_DU=1（不算磁盘）。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" -I - "$@" <<'PYEOF'
import csv, datetime, fnmatch, hashlib, json, os, re, shutil, socket, stat, subprocess, sys, time

ENV = os.environ
HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
EXECUTE = LIST_ONLY = False
OUT = None
i = 0
while i < len(ARGS):
    a = ARGS[i]
    if a == "--execute": EXECUTE = True
    elif a == "--list-only": LIST_ONLY = True
    elif a == "--out" and i + 1 < len(ARGS): OUT = ARGS[i + 1]; i += 1
    else:
        print("用法：ws-cleanup.sh [--execute] [--list-only] [--out DIR]", file=sys.stderr); sys.exit(2)
    i += 1
if EXECUTE and LIST_ONLY:
    print("ws-cleanup: --execute 和 --list-only 不能一起用", file=sys.stderr); sys.exit(2)

def find_orca():
    for c in (ENV.get("WS_ORCA"), shutil.which("orca-ide"), shutil.which("orca"), os.path.join(HOME, ".local/bin/orca"),
              "/Applications/Orca.app/Contents/Resources/bin/orca"):
        if c and os.path.exists(c): return c
    return "orca"
ORCA = find_orca()
GH = ENV.get("WS_GH") or shutil.which("gh") or "/opt/homebrew/bin/gh"
NOW = float(ENV.get("WS_NOW") or time.time())
IDLE_H = float(ENV.get("WS_IDLE_H") or 24)
NO_DU = ENV.get("WS_NO_DU") == "1"
ARCHIVE = ENV.get("WS_ARCHIVE") or os.path.join(HOME, "ops-archive/ws-cleanup")
SGT = datetime.timezone(datetime.timedelta(hours=8))
def host_label():
    h = (ENV.get("WS_HOST") or socket.gethostname()).lower()
    return "iMac" if "imac" in h else "MBA" if "mba" in h or "macbook" in h else "box" if "box" in h else h
HOST = host_label()
if HOST == "box":
    print("ws-cleanup: box 不在本轮范围（随 box 下线一起处理）", file=sys.stderr); sys.exit(2)
if HOST == "MBA":
    if EXECUTE:
        print("ws-cleanup: MBA 只列出，不清理", file=sys.stderr); sys.exit(2)
    LIST_ONLY = True
def toplevel(p):
    r = subprocess.run(["git", "-C", p, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 else None
SELF = os.path.realpath(ENV["WS_SELF"]) if ENV.get("WS_SELF") else toplevel(os.getcwd())
SELF_TERM = ENV.get("WS_SELF_TERM") if "WS_SELF_TERM" in ENV else ENV.get("ORCA_TERMINAL_HANDLE")
STAMP = datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y%m%d-%H%M%S")
OUT = OUT or os.path.join(HOME, "orca/workspaces/ops/workspace-cleanup", "ws-cleanup-" + STAMP)

BACKUP_DIRS = {".orca-task", "briefs", "evidence", "artifacts", "analysis"}
BACKUP_FILES = {"TASK.md", ".dev.vars"}
CACHE = {"node_modules", ".next", ".wrangler", "dist"}
# 只为了让 other_ignored 一列好读：常见的可重建产物不列出来（它们照样会随 rm 删掉）
NOISE = CACHE | {".DS_Store", "__pycache__", ".turbo", ".cache", "cache", "build", ".venv", "venv", ".pytest_cache", "coverage",
                 ".vite", ".svelte-kit", "out", "target", ".mypy_cache", ".ruff_cache", "test-results", "playwright-report",
                 ".parcel-cache", ".claude"}
AGENTS = {"claude", "pi", "codex", "opencode", "gemini", "aider", "devin"}
SHELLS = {"zsh", "bash", "sh", "fish", "dash", "login"}
RESUME = re.compile(r"(--resume|--session|--continue-session)[ =]\S+|\bclaude -r \S+|\bcodex resume \S+")

class QueryFail(Exception): pass
def run(cmd, timeout=120, cwd=None):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd, env=dict(ENV, GIT_OPTIONAL_LOCKS="0"))
    except (OSError, subprocess.TimeoutExpired) as e:
        return subprocess.CompletedProcess(cmd, 255, "", str(e))
def orca_json(*args):
    r = run([ORCA, *args, "--json"], timeout=180)
    if r.returncode != 0: raise QueryFail(" ".join(args))
    try: return json.loads(r.stdout)["result"]
    except (ValueError, KeyError): raise QueryFail(" ".join(args) + "（JSON 读不出）")
def git(path, *args, timeout=120):
    r = run(["git", "-C", path, *args], timeout=timeout)
    if r.returncode != 0: raise QueryFail("git " + args[0])
    return r.stdout

# ---------- 收数据 ----------
def collect():
    d = {}
    try:
        d["wt"] = orca_json("worktree", "list")["worktrees"]
        d["term"] = orca_json("terminal", "list")["terminals"]
    except QueryFail as e:
        print("ws-cleanup: 查不到 Orca 数据：%s，不出结论" % e, file=sys.stderr); sys.exit(4)
    try: d["repos"] = {r["id"]: r for r in orca_json("repo", "list")["repos"]}
    except (QueryFail, KeyError): d["repos"] = {}
    try:
        d["pid"] = {s["sessionId"]: s["pid"] for w in orca_json("diagnostics", "memory")["worktrees"] for s in w.get("sessions") or []}
    except (QueryFail, KeyError, TypeError):
        d["pid"] = None                       # 查不到：所有终端都当「进程情况未知」
    if ENV.get("WS_PS_FILE"): pst = open(ENV["WS_PS_FILE"]).read()
    else:
        r = run(["ps", "-A", "-o", "pid,ppid,comm"])
        pst = r.stdout if r.returncode == 0 else None
    d["ps"] = None
    if pst is not None:
        procs = {}
        for line in pst.splitlines()[1:]:
            parts = line.split(None, 2)
            if len(parts) == 3 and parts[0].isdigit(): procs[int(parts[0])] = (int(parts[1]), os.path.basename(parts[2]).lstrip("-"))
        d["ps"] = procs
    return d

def kids_of(procs, pid):
    return [p for p, (pp, _) in procs.items() if pp == pid]
def descendants(procs, pid):
    out, todo = [], [pid]
    while todo:
        for k in kids_of(procs, todo.pop()): out.append(k); todo.append(k)
    return out

def term_proc(d, t):
    """(pid, 'agent'|'busy'|'idle'|'gone'|'unknown', 子进程名)。pid 是 login；shell 是它唯一的子进程。"""
    if d["pid"] is None or d["ps"] is None: return None, "unknown", ""
    pid = d["pid"].get(t.get("ptyId"))
    if not pid or pid not in d["ps"]:
        return None, ("gone" if (not t.get("connected") or t.get("orphaned")) else "unknown"), ""
    desc = descendants(d["ps"], pid)
    names = [d["ps"][p][1] for p in desc]
    if any(n in AGENTS for n in names): return pid, "agent", ",".join(names)
    direct = kids_of(d["ps"], pid)
    shell_only = len(direct) <= 1 and all(d["ps"][p][1] in SHELLS for p in direct)
    rest = [d["ps"][p][1] for p in desc if p not in direct]
    if d["ps"][pid][1] not in SHELLS or not shell_only or rest: return pid, "busy", ",".join(names)
    return pid, "idle", ",".join(names)

# ---------- GitHub / Linear（每个仓库、每个 team 只查一次） ----------
GH_CACHE, LIN_CACHE = {}, {}
def gh_repo_of(url):
    m = re.search(r"github\.com[:/]([^/\s]+)/([^/\s]+?)(\.git)?/?$", url or "")
    return f"{m.group(1)}/{m.group(2)}" if m else None
def pr_list(repo):
    if repo not in GH_CACHE:
        r = run([GH, "pr", "list", "-R", repo, "--state", "all", "--limit", "1000",
                 "--json", "number,state,headRefName,headRepositoryOwner"], timeout=180)
        try: GH_CACHE[repo] = json.loads(r.stdout) if r.returncode == 0 else None
        except ValueError: GH_CACHE[repo] = None
    return GH_CACHE[repo]
def linear_state(key):
    team = key.split("-")[0]
    if team not in LIN_CACHE:
        try: LIN_CACHE[team] = {i["identifier"]: i["state"]["type"] for i in orca_json("linear", "list-issues", "--team", team)["issues"]}
        except (QueryFail, KeyError, TypeError): LIN_CACHE[team] = None
    m = LIN_CACHE[team]
    if m is None or key not in m: raise QueryFail("Linear " + key)
    return m[key]

REMOTES = {}
def remotes(main_path):
    if main_path not in REMOTES:
        try: REMOTES[main_path] = sorted({gh_repo_of(l.split()[1]) for l in git(main_path, "remote", "-v").splitlines()
                                          if len(l.split()) > 1} - {None})
        except QueryFail: REMOTES[main_path] = None
    return REMOTES[main_path]

def prs_for(w, ctx):
    """返回 [(号, 状态)]；查不到抛 QueryFail。"""
    repos = list(ctx["remotes"] or [])
    pj = w.get("projectId") or ""
    if pj.startswith("github:"): repos = [pj[7:]] + [r for r in repos if r != pj[7:]]
    if not repos: return []                   # 没有 GitHub 仓库，就没有 PR 这回事
    owners = {r.split("/")[0] for r in repos}
    lists = {}
    for r in repos:
        l = pr_list(r)
        if l is None: raise QueryFail("gh pr list " + r)
        lists[r] = l
    found = {}
    br = ctx["branch"]
    if br and br not in ctx["main_branches"]:
        for r, l in lists.items():
            for p in l:
                if p.get("headRefName") == br and (p.get("headRepositoryOwner") or {}).get("login") in owners:
                    found[(r, p["number"])] = p["state"]
    n = w.get("linkedPR")
    if n:
        hit = [(r, p) for r, l in lists.items() for p in l if p.get("number") == n]
        if not hit: raise QueryFail("linkedPR #%s" % n)
        r, p = hit[0]; found[(r, n)] = p["state"]
    return sorted((num, st) for (_, num), st in found.items())

# ---------- git 忽略的文件 ----------
def is_backup(rel):
    parts = rel.rstrip("/").split("/")
    return any(x in BACKUP_DIRS for x in parts) or parts[-1] in BACKUP_FILES or fnmatch.fnmatch(parts[-1], "*.local.*")
def ignored(path):
    out = git(path, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", timeout=300)
    backup, other = [], []
    for rel in sorted(x for x in out.split("\0") if x):
        parts = rel.rstrip("/").split("/")
        if any(x in CACHE for x in parts): continue
        if is_backup(rel): backup.append(rel.rstrip("/")); continue
        if rel.endswith("/"):                 # 被整个忽略的目录：往里找要备份的（跳过缓存目录）
            hit = False
            for root, dirs, files in os.walk(os.path.join(path, rel)):
                dirs[:] = sorted(x for x in dirs if x not in CACHE)
                for name in sorted(dirs + files):
                    sub = os.path.relpath(os.path.join(root, name), path)
                    if is_backup(sub):
                        backup.append(sub); hit = True
                        if name in dirs: dirs.remove(name)
            if hit: continue
        if not any(x in NOISE for x in parts) and not parts[-1].endswith((".pyc", ".log", ".tsbuildinfo")):
            other.append(rel.rstrip("/"))
    return backup, other

def du_mb(path):
    if NO_DU or not os.path.exists(path): return ""
    r = run(["du", "-sk", path], timeout=600)
    try: return str(int(r.stdout.split()[0]) // 1024)
    except (IndexError, ValueError): return "?"

# ---------- 判定 ----------
def evaluate(w, d, ctx):
    """返回 (结论, 规则, 原因, 证据 dict)。"""
    ev = {"status": w.get("workspaceStatus") or "", "pr": "", "linear": w.get("linkedLinearIssue") or "", "dirty": "",
          "unpushed": "", "backup": "", "other_ignored": ""}
    path = w["path"]
    real = os.path.realpath(path)
    if w.get("isMainWorktree") or w.get("isBare"): return "SKIP", "W1", "main 工作区 / bare 仓库", ev
    if SELF and real == SELF: return "SKIP", "W2", "本任务所在的工作区", ev
    if (w.get("hostId") or "local") != "local": return "LIST", "W3", "别的机器的工作区（hostId=%s）" % w.get("hostId"), ev
    terms = ctx["terms"]
    states = [term_proc(d, t) for t in terms]
    if any(t.get("agentIdentity") for t in terms) or any(s[1] == "agent" for s in states):
        return "SKIP", "W5", "agent 在跑", ev
    if any(s[1] == "busy" for s in states): return "SKIP", "W6", "终端里有活进程", ev
    if any(s[1] == "unknown" for s in states): return "SKIP", "W6", "查不到终端进程（当作有）", ev
    if not os.path.exists(path): return "RM", "W4", "目录已不在，只删 Orca 记录", ev
    try:
        if toplevel(path) != real: raise QueryFail("not a worktree")
        st = git(path, "status", "--porcelain=v1", "--untracked-files=all")
        ev["dirty"] = str(len(st.splitlines()))
        if st.strip(): return "SKIP", "W7", "有未提交改动 %s 项" % ev["dirty"], ev
    except QueryFail: return "SKIP", "W7", "git status 查不到（当作有改动）", ev
    try:
        ev["unpushed"] = git(path, "rev-list", "--count", "HEAD", "--not", "--remotes").strip()
        if ev["unpushed"] != "0": return "SKIP", "W8", "有未推送提交 %s 个" % ev["unpushed"], ev
    except QueryFail: return "SKIP", "W8", "git rev-list 查不到（当作有未推送）", ev
    try:
        prs = prs_for(w, ctx)
        ev["pr"] = ",".join("#%s %s" % p for p in prs)
        if any(s == "OPEN" for _, s in prs): return "SKIP", "W9", "PR 还开着", ev
    except QueryFail as e: return "SKIP", "W9", "PR 查不到（%s）" % e, ev
    lin_closed = None
    if ev["linear"]:
        try:
            typ = linear_state(ev["linear"]); ev["linear"] += " " + typ
            lin_closed = typ in ("completed", "canceled", "duplicate")
            if not lin_closed: return "SKIP", "W10", "Linear 还没关", ev
        except QueryFail: return "SKIP", "W10", "Linear 查不到（当作没关）", ev
    done = ev["status"].lower() == "completed" or any(s in ("MERGED", "CLOSED") for _, s in prs) or lin_closed
    if not done: return "SKIP", "W11", "没有做完的证据（状态 %s，PR 没合并/关闭，Linear 没关）" % ev["status"], ev
    act = (w.get("lastActivityAt") or 0) / 1000
    if not act:
        try: act = float(git(path, "log", "-1", "--format=%ct").strip())
        except (QueryFail, ValueError): return "SKIP", "W12", "lastActivityAt=0 且查不到提交时间", ev
    ctx["idle_h"] = (NOW - act) / 3600
    if ctx["idle_h"] < IDLE_H: return "SKIP", "W12", "%.0f 小时内有活动" % ctx["idle_h"], ev
    try: backup, other = ignored(path)
    except QueryFail: return "SKIP", "W13", "git 忽略文件查不到", ev
    ev["backup"] = ";".join(backup)
    ev["other_ignored"] = (";".join(other[:5]) + (";…共 %d 项" % len(other) if len(other) > 5 else "")) if other else ""
    if backup: return "BACKUP_RM", "W13", "有要备份的 git 忽略文件", ev
    return "RM", "W14", "条件全部满足", ev

def index(d):
    d["by_wt"], d["mains"], d["main_branches"] = {}, {}, {}
    for t in d["term"]: d["by_wt"].setdefault(t.get("worktreeId"), []).append(t)
    for w in d["wt"]:
        if w.get("isMainWorktree") and not w.get("isBare"): d["mains"].setdefault(w["repoId"], w["path"])
        if w.get("isMainWorktree"): d["main_branches"].setdefault(w["repoId"], set()).add((w.get("branch") or "").replace("refs/heads/", ""))
def make_ctx(w, d):
    rp = d["repos"].get(w["repoId"]) or {}
    base = d["mains"].get(w["repoId"]) or rp.get("path") or w["path"]
    return {"terms": d["by_wt"].get(w["id"], []), "branch": (w.get("branch") or "").replace("refs/heads/", ""),
            "main_branches": d["main_branches"].get(w["repoId"], set()) | {"main", "master"},
            "remotes": remotes(base) if os.path.exists(base) else [], "idle_h": None}

def build(d):
    index(d)
    mains = d["mains"]
    rows = []
    for w in d["wt"]:
        rp = (d["repos"].get(w["repoId"]) or {})
        ctx = make_ctx(w, d)
        verdict, rule, why, ev = evaluate(w, d, ctx)
        if ctx["idle_h"] is None and w.get("lastActivityAt"): ctx["idle_h"] = (NOW - w["lastActivityAt"] / 1000) / 3600
        sel = "id:" + w["id"]
        planned = {"RM": "orca worktree rm --worktree '%s'" % sel,
                   "BACKUP_RM": "备份到 %s/<日期>/%s/%s/ + sha 核对，然后 orca worktree rm --worktree '%s'" % (
                       ARCHIVE, rp.get("displayName") or w["repoId"][:8], os.path.basename(w["path"]), sel)}.get(verdict, "")
        rows.append({"host": HOST, "repo": rp.get("displayName") or w.get("projectId") or w["repoId"][:8],
                     "name": w.get("displayName") or "", "path": w["path"], "action": "LIST" if LIST_ONLY else verdict,
                     "verdict": verdict, "rule": rule, "reason": why, **ev, "terms": str(len(ctx["terms"])),
                     "idle_h": "" if ctx["idle_h"] is None else "%.0f" % ctx["idle_h"],
                     "last_activity": datetime.datetime.fromtimestamp(w["lastActivityAt"] / 1000, SGT).strftime("%Y-%m-%d %H:%M")
                                      if w.get("lastActivityAt") else "0",
                     "mb": du_mb(w["path"]) if verdict in ("RM", "BACKUP_RM") or LIST_ONLY else "", "planned": planned,
                     "_w": w})
    # W16：git 里登记、Orca 里没有的 worktree
    known = {os.path.realpath(w["path"]) for w in d["wt"]}
    for repo_id, mp in sorted(mains.items()):
        if not os.path.exists(mp): continue
        try: porc = git(mp, "worktree", "list", "--porcelain")
        except QueryFail: continue
        for blk in porc.strip().split("\n\n"):
            p = next((l[9:] for l in blk.splitlines() if l.startswith("worktree ")), None)
            if not p or os.path.realpath(p) in known or "bare" in blk.splitlines(): continue
            dirty = unp = ""
            if os.path.exists(p):
                try: dirty = str(len(git(p, "status", "--porcelain=v1").splitlines())); unp = git(p, "rev-list", "--count", "HEAD", "--not", "--remotes").strip()
                except QueryFail: dirty = "?"
            rp = d["repos"].get(repo_id) or {}
            rows.append({"host": HOST, "repo": rp.get("displayName") or repo_id[:8], "name": "", "path": p, "action": "LIST",
                         "verdict": "LIST", "rule": "W16", "reason": "git 里有、Orca 里没有" + ("" if os.path.exists(p) else "（目录不在）"),
                         "status": "", "pr": "", "linear": "", "dirty": dirty, "unpushed": unp, "backup": "", "other_ignored": "",
                         "terms": "0", "idle_h": "", "last_activity": "", "mb": du_mb(p), "planned": "", "_w": None})
    rows.sort(key=lambda r: (r["repo"], r["path"]))
    # 终端
    wt_by_id = {w["id"]: w for w in d["wt"]}
    trows = []
    for t in d["term"]:
        pid, state, names = term_proc(d, t)
        verdict, rule, why = term_verdict(t, pid, state)
        trows.append({"host": HOST, "handle": t["handle"], "worktree": (wt_by_id.get(t.get("worktreeId")) or {}).get("displayName") or t.get("worktreePath") or "",
                      "tab": t.get("tabId") or "", "action": "LIST" if LIST_ONLY else verdict, "verdict": verdict, "rule": rule,
                      "reason": why, "agent": t.get("agentIdentity") or "", "connected": str(bool(t.get("connected"))).lower(),
                      "pid": str(pid or ""), "procs": names, "planned": "", "_t": t})
    for r in trows:
        if r["verdict"] != "CLOSE": continue
        sib = [x for x in trows if r["tab"] and x["tab"] == r["tab"]]
        whole = r["tab"] and all(x["verdict"] == "CLOSE" for x in sib)
        r["planned"] = "orca terminal close --terminal %s%s" % (r["handle"], " --tab" if whole else "")
    trows.sort(key=lambda r: (r["worktree"], r["handle"]))
    return rows, trows

def term_verdict(t, pid, state):
    if SELF_TERM and t["handle"] == SELF_TERM: return "SKIP", "T3", "本任务自己的终端"
    if t.get("agentIdentity") or state == "agent": return "SKIP", "T1", "属于 agent / bot，由它自己关"
    if state == "busy": return "SKIP", "T6", "还有活进程"
    if state == "unknown": return "SKIP", "T6", "查不到进程（当作有）"
    r = run([ORCA, "terminal", "read", "--terminal", t["handle"], "--screen", "--limit", "60", "--json"], timeout=60)
    try: tail = json.loads(r.stdout)["result"]["terminal"]["tail"] if r.returncode == 0 else None
    except (ValueError, KeyError, TypeError): tail = None
    if tail is None: return "SKIP", "T2", "读不到屏幕（当作有 resume id）"
    if any(RESUME.search(l if isinstance(l, str) else json.dumps(l)) for l in tail): return "SKIP", "T2", "屏幕上有 resume id"
    if state == "gone": return "CLOSE", "T5", "进程已经不在"
    return "CLOSE", "T4", "空 shell"

# ---------- --execute ----------
def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()
def backup_files(path, items):
    files = []
    for it in items:
        full = os.path.join(path, it)
        if os.path.isdir(full) and not os.path.islink(full):
            for root, dirs, fs in os.walk(full):
                dirs[:] = sorted(x for x in dirs if x not in CACHE)
                files += [os.path.relpath(os.path.join(root, f), path) for f in sorted(fs)]
        else: files.append(it)
    return files
def do_backup(row):
    w = row["_w"]; path = w["path"]
    dest = os.path.join(ARCHIVE, datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y-%m-%d"), row["repo"], os.path.basename(path))
    if os.path.exists(dest): return False, "备份目录已存在，不覆盖"
    files = backup_files(path, row["backup"].split(";"))
    src_sha = {f: sha256(os.path.join(path, f)) for f in files if not os.path.islink(os.path.join(path, f))}
    os.makedirs(dest, mode=0o700)
    os.chmod(dest, 0o700)
    for f, h in src_sha.items():
        dst = os.path.join(dest, f)
        os.makedirs(os.path.dirname(dst), mode=0o700, exist_ok=True)
        shutil.copy2(os.path.join(path, f), dst)
        if os.path.basename(f) == ".dev.vars": os.chmod(dst, 0o600)
    bad = [f for f, h in src_sha.items() if sha256(os.path.join(dest, f)) != h]
    with open(os.path.join(dest, "MANIFEST.sha256"), "w") as m:
        for f in sorted(src_sha): m.write("%s  %s\n" % (src_sha[f], f))
    if bad: return False, "sha 对不上：%s" % ";".join(bad[:5])
    for f in src_sha:                         # .dev.vars 是「移动」：核对一致后删掉原位置的明文
        if os.path.basename(f) == ".dev.vars": os.unlink(os.path.join(path, f))
    return True, dest

def execute(rows, trows):
    fails = 0
    fresh = collect()                         # 判定和动手之间可能有变化：动手前重新收数据，结论不变才做
    index(fresh)
    fresh_wt = {w["id"]: w for w in fresh["wt"]}
    for r in rows:
        if r["verdict"] not in ("RM", "BACKUP_RM") or not r["_w"]: continue
        w = fresh_wt.get(r["_w"]["id"])
        if not w: r["result"] = "跳过：Orca 里已经没有"; continue
        v2, rule2, why2, ev2 = evaluate(w, fresh, make_ctx(w, fresh))
        if v2 != r["verdict"] or ev2["backup"] != r["backup"]:
            r["result"] = "跳过：重新判定变成 %s %s（%s）" % (v2, rule2, why2); continue
        if v2 == "BACKUP_RM":
            ok, msg = do_backup(r)
            if not ok: r["result"] = "BACKUP_FAIL：" + msg; fails += 1; continue
            r["result"] = "已备份到 " + msg
        p = run([ORCA, "worktree", "rm", "--worktree", "id:" + w["id"], "--json"], timeout=300)
        msg = (p.stderr or p.stdout).strip().splitlines()
        done = "已 rm" if p.returncode == 0 else "rm 失败（不重试、不加 --force）：" + (msg[-1][:200] if msg else "")
        r["result"] = r["result"] + "；" + done if r.get("result") else done
        fails += p.returncode != 0
    for r in trows:
        if r["verdict"] != "CLOSE": continue
        p = run([ORCA, "terminal", "close", "--terminal", r["handle"]] + (["--tab"] if r["planned"].endswith("--tab") else []), timeout=60)
        r["result"] = "已关" if p.returncode == 0 else "关闭失败"
        fails += p.returncode != 0
    return fails

# ---------- 输出 ----------
WCOLS = ["host", "repo", "name", "path", "action", "verdict", "rule", "reason", "status", "pr", "linear", "dirty", "unpushed",
         "terms", "idle_h", "last_activity", "mb", "backup", "other_ignored", "planned"]
TCOLS = ["host", "handle", "worktree", "tab", "action", "verdict", "rule", "reason", "agent", "connected", "pid", "procs", "planned"]
def clean(v): return str(v).replace("\t", " ").replace("\n", " ")
def write_tsv(path, cols, rows):
    with open(path, "w", newline="") as f:
        wr = csv.writer(f, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_NONE, escapechar="\\")
        wr.writerow(cols)
        for r in rows: wr.writerow([clean(r.get(c, "")) for c in cols])

def expired_backups():
    out = []
    if not os.path.isdir(ARCHIVE): return out
    for n in sorted(os.listdir(ARCHIVE)):
        try: day = datetime.datetime.strptime(n, "%Y-%m-%d").replace(tzinfo=SGT)
        except ValueError: continue
        if (NOW - day.timestamp()) / 86400 > 30: out.append(n)
    return out

def summary(rows, trows, fails):
    from collections import Counter
    c = Counter(r["action"] for r in rows); v = Counter(r["verdict"] for r in rows); rc = Counter(r["rule"] for r in rows)
    mb = lambda k: sum(int(r["mb"]) for r in rows if r["verdict"] == k and r["mb"].isdigit())
    L = ["# ws-cleanup %s（%s，%s）" % ("执行" if EXECUTE else "list-only" if LIST_ONLY else "dry-run", HOST,
                                        datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y-%m-%d %H:%M:%S SGT")), "",
         "orca：`%s`；空闲门槛 %g 小时；备份根目录 `%s`。" % (ORCA, IDLE_H, ARCHIVE), "",
         "| 动作 | 工作区 |", "|---|---|"] + ["| %s | %d |" % (k, c[k]) for k in ("RM", "BACKUP_RM", "SKIP", "LIST") if c[k]]
    if LIST_ONLY:
        L += ["", "只列出；如果在这台机器上清理，结论会是：" + "，".join("%s %d" % (k, v[k]) for k in ("RM", "BACKUP_RM", "SKIP", "LIST") if v[k])]
    L += ["", "RM 合计约 %d MB，BACKUP_RM 合计约 %d MB（du）。" % (mb("RM"), mb("BACKUP_RM")), "",
          "| 规则 | 个数 |", "|---|---|"] + ["| %s | %d |" % (k, rc[k]) for k in sorted(rc, key=lambda x: int(x[1:]))]
    tc = Counter(r["action"] for r in trows); trc = Counter(r["rule"] for r in trows)
    L += ["", "终端：" + "，".join("%s %d" % kv for kv in sorted(tc.items())) + "（" + "，".join("%s %d" % kv for kv in sorted(trc.items())) + "）"]
    ex = expired_backups()
    L += ["", "超过 30 天的备份（只列出，删除另外批准）：" + ("、".join(ex) if ex else "无")]
    if EXECUTE: L += ["", "没做成的：%d 个（见 worktrees.tsv / terminals.tsv 的 result 列）" % fails]
    return "\n".join(L) + "\n"

def main():
    d = collect()
    rows, trows = build(d)
    fails = execute(rows, trows) if EXECUTE else 0
    os.makedirs(OUT, exist_ok=True)
    wc, tc = WCOLS + (["result"] if EXECUTE else []), TCOLS + (["result"] if EXECUTE else [])
    write_tsv(os.path.join(OUT, "worktrees.tsv"), wc, rows)
    write_tsv(os.path.join(OUT, "terminals.tsv"), tc, trows)
    s = summary(rows, trows, fails)
    open(os.path.join(OUT, "summary.md"), "w").write(s)
    print(s, end=""); print("输出：" + OUT)
    sys.exit(3 if fails else 0)
main()
PYEOF
