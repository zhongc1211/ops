#!/bin/bash
# ws-cleanup.sh [--dry-run] [--list-only] [--precheck] [--out DIR] [--repo REPO_ID]
#               [--execute --only-from DRYRUN/worktrees.tsv [--close-terminals]]
# Orca 工作区 / 终端夜间清理（纯脚本，不起模型）。规则：reports/ws-cleanup-dryrun-1021/RESULT.md、.orca-task/RULES-DRAFT.md
# （Zack 10-21 01:43 定），按独立评审 PER-139 返工（reports/ws-cleanup-rework-r1/）。**默认 dry-run**：只读，写出 worktrees.tsv、
# terminals.tsv、backup-files.tsv（会备份的被忽略文件逐个列出）、summary.md。只有 --execute 才会备份、`orca worktree rm`（不加 --force）；--execute 必须带 --only-from 一份 dry-run
# 名单，只处理名单里、重新判定后结论和备份清单都没变的工作区；终端默认不关，要再加 --close-terminals（也只关名单里的）。
#   工作区从上往下判，第一条命中的就是结论：W1 main/bare → W2 本任务所在 → W3 别的机器 → W5 agent 在跑 → W6 终端有活进程 / 还开着
#   → 目录已不在：W4 看 git 记录的 HEAD（不在远端、也没有别的 ref 包含 → SKIP） / 目录在：W7 未提交 → W8 未推送
#   → W9 open PR → W10 Linear 未关（Zack 03:37：真删前每次实时查，查不到、超时、找不到 issue 都不删）→ W11 Orca 状态不是 completed
#   → W12 近 IDLE_H 小时有活动 → W17 HEAD 不在已合并的 PR / 远端主分支或合并目标分支上
#   （Zack 10-21 03:33：Linear Done、状态 completed 都只是前提，安全核对一项不过就不删）
#   → W13 被忽略的文件：可重建的以外一律先备份（有嵌套 .git、非普通文件 → SKIP） → W14 rm（目录已不在的是 W4 rm）。
#   W16：git 里有、Orca 里没有的 worktree，只列出。
#   终端：T3 本终端 / 本任务所在工作区 → T8 不在清理范围（folder、main、别的机器、不在 worktree list）→ T1 agent 本身所在的终端
#   → T6 有子进程 → T7 最近 TERM_IDLE_H 小时有输出（同一工作区有 agent 的配套空 shell 用 AGENT_SIB_IDLE_H，Zack 10-21 03:29）/ 没有 lastOutputAt
#   → T2 屏幕上有 resume id、最后一行不是提示符 → T4 空 shell / T5 进程已不在 → 关。关之前先存档 scrollback、cwd、终端元数据到
#   ARCHIVE/terminals/<日期>/<handle>/（README.txt 写怎么找回），存档失败就不关。cwd 用 `lsof -a -d cwd -p <shell pid> -Fn`，只在真的要关时才查。
#   任何查询失败都算跳过，不算通过。--execute 只在 hostname 为 iMac 的机器上允许，其他机器一律只列出，box 不跑。
# 进程只用 `ps -A -o pid,ppid,comm`；git 忽略的文件只看名字、类型和大小，不读内容；终端屏幕只用来找 resume id 和提示符，不写进输出。
# 退出码：0 正常；1 --precheck（总是 1）；2 用法 / 主机 / 命令路径不对；3 --execute 有没做成的；4 查不到 Orca 数据（不写结果文件）；
#   5 环境不对（gh、diagnostics、ps、worktree ps 有查不到的，--execute 什么都不做）；6 另一个 --execute 正在跑。
# 演练用：WS_ORCA、WS_GH（命令路径，设了但不存在就退出 / 当作没有 gh）、WS_PS_FILE（ps 输出文件）、WS_NOW（epoch 秒）、
#   WS_HOST（只在设了 WS_ORCA 时认）、WS_SELF（本任务工作区）、WS_SELF_TERM（本终端 handle）、WS_ARCHIVE（备份根目录，默认 ~/ops-archive/ws-cleanup）、
#   WS_LOCK（锁目录）、WS_IDLE_H / WS_TERM_IDLE_H（默认 24）、WS_AGENT_SIB_IDLE_H（默认 12）、WS_LSOF（lsof 路径）、WS_NO_DU=1（不算磁盘）、WS_PAUSE_FILE（只在设了 WS_ORCA 时认：判定后、动手前等这个文件出现）。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" -I - "$@" <<'PYEOF'
import csv, datetime, hashlib, json, os, re, shutil, socket, stat, subprocess, sys, time

ENV = os.environ
HOME = os.path.expanduser("~")
ARGS = sys.argv[1:]
EXECUTE = LIST_ONLY = PRECHECK = CLOSE_TERMS = False
OUT = ONLY_FROM = REPO = None
USAGE = "用法：ws-cleanup.sh [--dry-run] [--list-only] [--precheck] [--out DIR] [--repo REPO_ID] [--execute --only-from TSV [--close-terminals]]"
def die(msg, code):
    print("ws-cleanup: " + msg, file=sys.stderr); sys.exit(1 if PRECHECK else code)
i = 0
while i < len(ARGS):
    a = ARGS[i]
    if a == "--execute": EXECUTE = True
    elif a == "--list-only": LIST_ONLY = True
    elif a == "--dry-run": pass                  # 默认就是 dry-run；文档里写了这个参数，照收
    elif a == "--precheck": PRECHECK = True
    elif a == "--close-terminals": CLOSE_TERMS = True
    elif a in ("--out", "--only-from", "--repo") and i + 1 < len(ARGS):
        if a == "--out": OUT = ARGS[i + 1]
        elif a == "--only-from": ONLY_FROM = ARGS[i + 1]
        else: REPO = ARGS[i + 1]
        i += 1
    else: die(USAGE, 2)
    i += 1
if EXECUTE and (LIST_ONLY or PRECHECK): die("--execute 不能和 --list-only / --precheck 一起用", 2)
if EXECUTE and not ONLY_FROM: die("--execute 必须带 --only-from <dry-run 的 worktrees.tsv>", 2)
if (ONLY_FROM or CLOSE_TERMS) and not EXECUTE: die("--only-from / --close-terminals 只和 --execute 一起用", 2)

TEST = bool(ENV.get("WS_ORCA"))
def find_orca():
    if TEST:
        if not os.access(ENV["WS_ORCA"], os.X_OK): die("WS_ORCA=%s 不存在或不能执行，不回落到别的 orca" % ENV["WS_ORCA"], 2)
        return ENV["WS_ORCA"]
    for c in (shutil.which("orca-ide"), shutil.which("orca"), os.path.join(HOME, ".local/bin/orca"),
              "/Applications/Orca.app/Contents/Resources/bin/orca"):
        if c and os.path.exists(c): return c
    return "orca"
ORCA = find_orca()
def find_gh():
    if "WS_GH" in ENV: return ENV["WS_GH"] if os.access(ENV["WS_GH"], os.X_OK) else None
    for c in (shutil.which("gh"), "/usr/local/bin/gh", "/opt/homebrew/bin/gh"):
        if c and os.access(c, os.X_OK): return c
    return None
GH = find_gh()
NOW = float(ENV.get("WS_NOW") or time.time())
IDLE_H = float(ENV.get("WS_IDLE_H") or 24)
TERM_IDLE_H = float(ENV.get("WS_TERM_IDLE_H") or 24)
AGENT_SIB_IDLE_H = float(ENV.get("WS_AGENT_SIB_IDLE_H") or 12)
NO_DU = ENV.get("WS_NO_DU") == "1"
ARCHIVE = ENV.get("WS_ARCHIVE") or os.path.join(HOME, "ops-archive/ws-cleanup")
LOCK = ENV.get("WS_LOCK") or os.path.join(ARCHIVE, ".lock")
SGT = datetime.timezone(datetime.timedelta(hours=8))
HOSTNAME = (ENV.get("WS_HOST") if TEST and ENV.get("WS_HOST") else socket.gethostname()).lower()
HOST = "iMac" if "imac" in HOSTNAME else "MBA" if "mba" in HOSTNAME or "macbook" in HOSTNAME else "box" if "box" in HOSTNAME else HOSTNAME
if HOST == "box": die("box 不在本轮范围（随 box 下线一起处理）", 2)
if HOSTNAME != "imac":                          # 只认明确列出的主机；别的机器（含 MBA、改过名的）一律只列出
    if EXECUTE: die("这台机器（%s）只列出，不清理" % HOSTNAME, 2)
    LIST_ONLY = True
def toplevel(p):
    r = subprocess.run(["git", "-C", p, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 else None
SELF = os.path.realpath(ENV["WS_SELF"]) if ENV.get("WS_SELF") else toplevel(os.getcwd())
SELF_TERM = ENV.get("WS_SELF_TERM") if "WS_SELF_TERM" in ENV else ENV.get("ORCA_TERMINAL_HANDLE")
STAMP = datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y%m%d-%H%M%S")
OUT = OUT or os.path.join(ARCHIVE, "reports", "ws-cleanup-" + STAMP)

# 可重建的被忽略文件（构建产物 / 缓存）：随 rm 删掉，不备份（报告里照样列出）。除此以外被忽略的一律先备份（Zack 10-21 03:26）。
# WS_REBUILD_DIRS / WS_REBUILD_FILES（逗号分隔的名字）整张替换下面的清单；名字匹配路径里的任意一级。
REBUILD_DIRS = {"node_modules", ".next", ".open-next", ".wrangler", ".cloudflare", "dist", "build", ".turbo", ".cache", "__pycache__",
                ".venv", ".mypy_cache", ".ruff_cache", ".pytest_cache", ".vite", ".svelte-kit", ".parcel-cache"}
REBUILD_FILES = {"next-env.d.ts", ".DS_Store"}
if ENV.get("WS_REBUILD_DIRS") is not None: REBUILD_DIRS = {x.strip() for x in ENV["WS_REBUILD_DIRS"].split(",") if x.strip()}
if ENV.get("WS_REBUILD_FILES") is not None: REBUILD_FILES = {x.strip() for x in ENV["WS_REBUILD_FILES"].split(",") if x.strip()}
REBUILD_SUFFIX = (".tsbuildinfo", ".pyc")
AGENTS = {"claude", "pi", "codex", "opencode", "gemini", "aider", "devin"}
SHELLS = {"zsh", "bash", "sh", "fish", "dash", "login"}
RESUME = re.compile(r"(--resume|--session|--continue-session)[ =]\S+|\bclaude -r \S+|\bcodex resume \S+")
PROMPT = re.compile(r"[$%#❯›>]\s*$")

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

# ---------- 收数据（每次调用都是实时的；Linear、git worktree 记录的缓存挂在这一份数据上，复查时一起作废） ----------
def collect():
    d = {"lin": {}, "gitwt": {}}
    try:
        d["wt"] = orca_json("worktree", "list")["worktrees"]
        d["term"] = orca_json("terminal", "list")["terminals"]
    except QueryFail as e:
        die("查不到 Orca 数据：%s，不出结论" % e, 4)
    try: d["repos"] = {r["id"]: r for r in orca_json("repo", "list")["repos"]}
    except (QueryFail, KeyError): d["repos"] = {}
    try:
        d["pid"] = {s["sessionId"]: s["pid"] for w in orca_json("diagnostics", "memory")["worktrees"] for s in w.get("sessions") or []}
    except (QueryFail, KeyError, TypeError):
        d["pid"] = None                       # 查不到：所有终端都当「进程情况未知」
    try:
        r = orca_json("worktree", "ps", "--limit", "100000")
        d["wps"] = None if r.get("truncated") else {w["worktreeId"]: w for w in r["worktrees"]}
    except (QueryFail, KeyError, TypeError, AttributeError):
        d["wps"] = None                       # 查不到：所有工作区都当「可能有 agent」
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
    index(d)
    return d

def index(d):
    d["by_wt"], d["mains"], d["main_branches"] = {}, {}, {}
    d["wt_by_id"] = {w["id"]: w for w in d["wt"]}
    for t in d["term"]: d["by_wt"].setdefault(t.get("worktreeId"), []).append(t)
    for w in d["wt"]:
        if w.get("isMainWorktree") and not w.get("isBare"): d["mains"].setdefault(w["repoId"], w["path"])
        if w.get("isMainWorktree"): d["main_branches"].setdefault(w["repoId"], set()).add((w.get("branch") or "").replace("refs/heads/", ""))

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

def agent_in(d, wid):
    """这个工作区有没有 agent：True / False / None（查不到）。终端里的 agent 和 orca worktree ps 记录的 agent 都算。"""
    terms = d["by_wt"].get(wid, [])
    if any(t.get("agentIdentity") for t in terms) or any(term_proc(d, t)[1] == "agent" for t in terms): return True
    if d["wps"] is None: return None
    return bool((d["wps"].get(wid) or {}).get("agents"))

# ---------- GitHub / Linear ----------
CANON = {}
def gh_repo_of(url):
    m = re.search(r"github\.com[:/]([^/\s]+)/([^/\s]+?)(\.git)?/?$", url or "")
    return f"{m.group(1)}/{m.group(2)}" if m else None
def canon(repo):
    """仓库现在的名字（转移、改名以后 GitHub 会跳转）；查不到抛 QueryFail。"""
    if repo not in CANON:
        r = run([GH, "repo", "view", repo, "--json", "nameWithOwner"], timeout=60) if GH else None
        try: CANON[repo] = json.loads(r.stdout)["nameWithOwner"] if r and r.returncode == 0 else None
        except (ValueError, KeyError, TypeError): CANON[repo] = None
    if CANON[repo] is None: raise QueryFail("gh repo view " + repo)
    return CANON[repo]
PR_FIELDS = "number,state,headRefName,headRefOid,headRepositoryOwner,baseRefName"
def gh_json(args, what):
    if not GH: raise QueryFail("找不到 gh")
    r = run([GH, *args], timeout=120)
    if r.returncode != 0: return None, r.stderr
    try: return json.loads(r.stdout), ""
    except ValueError: raise QueryFail(what + "（JSON 读不出）")

def linear_state(key, d):
    team = key.split("-")[0]
    if team not in d["lin"]:
        try: d["lin"][team] = {i["identifier"]: i["state"]["type"] for i in orca_json("linear", "list-issues", "--team", team)["issues"]}
        except (QueryFail, KeyError, TypeError): d["lin"][team] = None
    m = d["lin"][team]
    if m is None or key not in m: raise QueryFail("Linear " + key)
    return m[key]

REMOTES = {}
def remotes(main_path):
    if main_path not in REMOTES:
        try: REMOTES[main_path] = sorted({gh_repo_of(l.split()[1]) for l in git(main_path, "remote", "-v").splitlines()
                                          if len(l.split()) > 1} - {None})
        except QueryFail: REMOTES[main_path] = None
    return REMOTES[main_path]

def prs_for(w, ctx, head):
    """这个工作区的 PR：[pr dict]。按分支逐个仓库查（不受列表条数限制），owner 用新旧两个名字；查不到抛 QueryFail。"""
    if ctx["remotes"] is None: raise QueryFail("git remote")
    repos = list(ctx["remotes"])
    pj = w.get("projectId") or ""
    if pj.startswith("github:"): repos = [pj[7:]] + [r for r in repos if r != pj[7:]]
    if not repos: return []                   # 没有 GitHub 仓库，就没有 PR 这回事
    owners, names = set(), []
    for r in repos:
        c = canon(r)
        owners |= {r.split("/")[0].lower(), c.split("/")[0].lower()}
        if c not in names: names.append(c)
    found = {}
    br = ctx["branch"]
    if br and br not in ctx["main_branches"]:
        for c in names:
            l, err = gh_json(["pr", "list", "-R", c, "--head", br, "--state", "all", "--limit", "100", "--json", PR_FIELDS], "gh pr list " + c)
            if l is None: raise QueryFail("gh pr list %s --head %s" % (c, br))
            for p in l:
                if p.get("headRefName") == br and ((p.get("headRepositoryOwner") or {}).get("login") or "").lower() in owners:
                    found[(c, p["number"])] = p
    n = w.get("linkedPR")
    if n:
        hits = []
        for c in names:
            p, err = gh_json(["pr", "view", str(n), "-R", c, "--json", PR_FIELDS], "gh pr view")
            if p is not None: hits.append((c, p))
            elif not re.search(r"could not resolve|no pull requests? found|not found", err, re.I):
                raise QueryFail("gh pr view #%s -R %s" % (n, c))
        if len(hits) > 1:                     # fork 和上游同号：用分支名或 HEAD 对得上的那个
            hits = [(c, p) for c, p in hits if p.get("headRefName") == br or (head and p.get("headRefOid") == head)]
            if len(hits) != 1: raise QueryFail("linkedPR #%s 在两个仓库都有、对不上分支" % n)
        if not hits: raise QueryFail("linkedPR #%s" % n)
        found[(hits[0][0], n)] = hits[0][1]
    out = {}
    for (_, num), p in sorted(found.items(), key=lambda kv: kv[0][1]): out.setdefault((num, p["state"]), p)  # 同号同状态只算一次
    return list(out.values())

# ---------- git 忽略的文件 ----------
def rebuildable(rel):
    parts = rel.rstrip("/").split("/")
    return any(x in REBUILD_DIRS for x in parts) or parts[-1] in REBUILD_FILES or parts[-1].endswith(REBUILD_SUFFIX)
def ignored(path):
    """{"backup": [被忽略的条目], "n": 文件数, "bytes": 字节, "rebuild": [可重建的条目], "nested": [嵌套 .git], "odd": [非普通文件]}"""
    out = git(path, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory", "-z", timeout=300)
    res = {"backup": [], "n": 0, "bytes": 0, "rebuild": [], "nested": [], "odd": [], "files": []}
    def look(rel):
        st = os.lstat(os.path.join(path, rel))
        if os.path.basename(rel) == ".git": res["nested"].append(rel)
        elif stat.S_ISREG(st.st_mode): res["n"] += 1; res["bytes"] += st.st_size; res["files"].append((rel, st.st_size))
        elif stat.S_ISLNK(st.st_mode): res["files"].append((rel, "symlink"))
        elif not stat.S_ISDIR(st.st_mode): res["odd"].append(rel)
    for rel in sorted(x for x in out.split("\0") if x):
        if rebuildable(rel): res["rebuild"].append(rel.rstrip("/")); continue
        res["backup"].append(rel.rstrip("/"))
        full = os.path.join(path, rel)
        if not (os.path.isdir(full) and not os.path.islink(full)):
            look(rel.rstrip("/")); continue
        for root, dirs, files in os.walk(full):
            for x in sorted(dirs):
                sub = os.path.relpath(os.path.join(root, x), path)
                if x == ".git": res["nested"].append(sub); dirs.remove(x)
                elif rebuildable(sub): res["rebuild"].append(sub); dirs.remove(x)
                elif os.path.islink(os.path.join(root, x)): dirs.remove(x); look(sub)
            for f in sorted(files):
                sub = os.path.relpath(os.path.join(root, f), path)
                if rebuildable(sub): res["rebuild"].append(sub)
                else: look(sub)
    return res

def du_mb(path):
    if NO_DU or not os.path.exists(path): return ""
    r = run(["du", "-sk", path], timeout=600)
    try: return str(int(r.stdout.split()[0]) // 1024)
    except (IndexError, ValueError): return "?"

def git_record(d, main, path):
    """git 里这条 worktree 记录的 (HEAD, 分支)；没有这条记录返回 None；查不到抛 QueryFail。"""
    if main not in d["gitwt"]:
        recs = {}
        for blk in git(main, "worktree", "list", "--porcelain").strip().split("\n\n"):
            ls = blk.splitlines()
            p = next((l[9:] for l in ls if l.startswith("worktree ")), None)
            if p: recs[p] = (next((l[5:] for l in ls if l.startswith("HEAD ")), None),
                             next((l[7:].replace("refs/heads/", "") for l in ls if l.startswith("branch ")), None))
        d["gitwt"][main] = recs
    recs = d["gitwt"][main]
    return recs.get(path) or next((v for k, v in recs.items() if os.path.realpath(k) == os.path.realpath(path)), None)

# ---------- 判定 ----------
def evaluate(w, d, ctx):
    """返回 (结论, 规则, 原因, 证据 dict)。"""
    ev = {"status": w.get("workspaceStatus") or "", "pr": "", "head_vs_pr": "", "merged_via": "", "linear": w.get("linkedLinearIssue") or "",
          "dirty": "", "unpushed": "", "head": "", "backup": "", "backup_size": "", "rebuild": "", "_backup": [], "_files": []}
    path = w["path"]
    real = os.path.realpath(path)
    if w.get("isMainWorktree") or w.get("isBare"): return "SKIP", "W1", "main 工作区 / bare 仓库", ev
    if SELF and real == SELF: return "SKIP", "W2", "本任务所在的工作区", ev
    if (w.get("hostId") or "local") != "local": return "LIST", "W3", "别的机器的工作区（hostId=%s）" % w.get("hostId"), ev
    ag = agent_in(d, w["id"])
    if ag: return "SKIP", "W5", "agent 在跑（终端里或 Orca 记录里）", ev
    if ag is None: return "SKIP", "W5", "查不到 Orca 的 agent 记录（当作有）", ev
    states = [term_proc(d, t)[1] for t in ctx["terms"]]
    if "busy" in states: return "SKIP", "W6", "终端里有活进程", ev
    if "unknown" in states: return "SKIP", "W6", "查不到终端进程（当作有）", ev
    if "idle" in states: return "SKIP", "W6", "还有打开的终端（rm 会把它停掉）", ev
    gone = not os.path.exists(path)
    gitdir = path
    if gone:
        gitdir = ctx["main"]
        try: rec = git_record(d, gitdir, path) if gitdir and os.path.exists(gitdir) else None
        except QueryFail: rec = None
        if not rec or not rec[0]: return "SKIP", "W4", "目录已不在，git 里也读不到这条 worktree 的 HEAD", ev
        head, own = rec
        ev["head"] = head[:7]
        try:
            git(gitdir, "cat-file", "-e", head + "^{commit}")
            ev["unpushed"] = git(gitdir, "rev-list", "--count", head, "--not", "--remotes").strip()
            refs = [] if ev["unpushed"] == "0" else [x for x in git(gitdir, "for-each-ref", "--contains", head, "--format=%(refname)").split()
                                                      if not (own and x == "refs/heads/" + own)]
        except QueryFail: return "SKIP", "W4", "目录已不在，查不到记录的 HEAD %s 在不在远端" % head[:7], ev
        if ev["unpushed"] != "0" and not refs:
            return "SKIP", "W4", "目录已不在；记录的 HEAD %s 不在远端，也没有别的 ref 包含（先推到 backup/%s-%s）" % (
                head[:7], os.path.basename(path), head[:7]), ev
        ev["_refs"] = refs
    else:
        try:
            if toplevel(path) != real: raise QueryFail("not a worktree")
            st = git(path, "status", "--porcelain=v1", "--untracked-files=all")
            ev["dirty"] = str(len(st.splitlines()))
            if st.strip(): return "SKIP", "W7", "有未提交改动 %s 项" % ev["dirty"], ev
        except QueryFail: return "SKIP", "W7", "git status 查不到（当作有改动）", ev
        try:
            head = git(path, "rev-parse", "HEAD").strip(); ev["head"] = head[:7]
            ev["unpushed"] = git(path, "rev-list", "--count", "HEAD", "--not", "--remotes").strip()
            if ev["unpushed"] != "0": return "SKIP", "W8", "有未推送提交 %s 个" % ev["unpushed"], ev
        except QueryFail: return "SKIP", "W8", "git rev-list 查不到（当作有未推送）", ev
    try:
        prs = prs_for(w, ctx, head)
        ev["pr"] = ",".join("#%s %s" % (p["number"], p["state"]) for p in prs)
        ev["head_vs_pr"] = ",".join("#%s%s" % (p["number"], "=" if p.get("headRefOid") == head else "≠") for p in prs)
        if any(p["state"] == "OPEN" for p in prs): return "SKIP", "W9", "PR 还开着", ev
    except QueryFail as e: return "SKIP", "W9", "PR 查不到（%s）" % e, ev
    lin_closed = None
    if ev["linear"]:
        try:
            typ = linear_state(ev["linear"], d); ev["linear"] += " " + typ
            lin_closed = typ in ("completed", "canceled", "duplicate")
            if not lin_closed: return "SKIP", "W10", "Linear 还没关", ev
        except QueryFail: return "SKIP", "W10", "Linear 查不到（当作没关）", ev
    if ev["status"].lower() != "completed":   # 评审 M1：先保守，状态不是 completed 一律不删，等 Zack 定
        old = any(p["state"] in ("MERGED", "CLOSED") for p in prs) or lin_closed
        return "SKIP", "W11", "Orca 状态是 %s，不是 completed%s" % (ev["status"] or "空",
                                                                    "（状态冲突：旧规则会按 PR 已合并 / Linear 已关删掉，等 Zack 定）" if old else ""), ev
    act = (w.get("lastActivityAt") or 0) / 1000
    if not act:
        try: act = float(git(gitdir, "log", "-1", "--format=%ct", head).strip())
        except (QueryFail, ValueError): return "SKIP", "W12", "lastActivityAt=0 且查不到提交时间", ev
    ctx["idle_h"] = (NOW - act) / 3600
    if ctx["idle_h"] < IDLE_H: return "SKIP", "W12", "最近 %g 小时内有活动" % IDLE_H, ev
    how = head_merged(gitdir, head, prs, ctx)
    if not how: return "SKIP", "W17", "HEAD %s 不在已合并的 PR / 远端主分支上" % head[:7], ev
    ev["merged_via"] = how
    if gone:
        how = "HEAD %s 已在远端" % head[:7] if ev["unpushed"] == "0" else "HEAD %s 被 %s 包含" % (head[:7], ev["_refs"][0])
        return "RM", "W4", "目录已不在；rm 会删 Orca 记录和 git worktree 记录（%s）" % how, ev
    try: ig = ignored(path)
    except (QueryFail, OSError): return "SKIP", "W13", "git 忽略文件查不到", ev
    ev["_backup"], ev["_files"] = ig["backup"], ig["files"]
    ev["backup"] = ";".join(ig["backup"])
    ev["backup_size"] = "%d 个文件 %d KB" % (ig["n"], (ig["bytes"] + 1023) // 1024) if ig["backup"] else ""
    ev["rebuild"] = ("%d 项：" % len(ig["rebuild"]) + ";".join(ig["rebuild"][:5]) + ("…" if len(ig["rebuild"]) > 5 else "")) if ig["rebuild"] else ""
    if ig["nested"]: return "SKIP", "W13", "被忽略的东西里有嵌套 git 仓库：%s" % ";".join(ig["nested"][:3]), ev
    if ig["odd"]: return "SKIP", "W13", "被忽略的东西里有不是普通文件的：%s" % ";".join(ig["odd"][:3]), ev
    if ig["backup"]: return "BACKUP_RM", "W13", "有被忽略、不能重建的文件（先整份备份）", ev
    return "RM", "W14", "条件全部满足", ev

def head_merged(gitdir, head, prs, ctx):
    """HEAD 已经进了哪里：已合并 PR 的 head（或它的祖先），或者远端的主分支 / 已合并 PR 的目标分支。都不在返回 None。"""
    anc = lambda ref: run(["git", "-C", gitdir, "merge-base", "--is-ancestor", head, ref]).returncode == 0
    merged = [p for p in prs if p["state"] == "MERGED"]
    for p in merged:
        if p.get("headRefOid") == head: return "PR #%s 的 head" % p["number"]
        if p.get("headRefOid") and anc(p["headRefOid"]): return "PR #%s 的 head 包含" % p["number"]
    bases = ctx["main_branches"] | {p.get("baseRefName") for p in merged if p.get("baseRefName")}
    try: refs = git(gitdir, "for-each-ref", "refs/remotes", "--format=%(refname:short)").split()
    except QueryFail: return None
    for ref in sorted(refs):
        if "/" in ref and ref.split("/", 1)[1] in bases and anc("refs/remotes/" + ref): return "在 " + ref
    return None

def make_ctx(w, d):
    rp = d["repos"].get(w["repoId"]) or {}
    base = d["mains"].get(w["repoId"]) or rp.get("path")
    return {"terms": d["by_wt"].get(w["id"], []), "branch": (w.get("branch") or "").replace("refs/heads/", ""),
            "main_branches": d["main_branches"].get(w["repoId"], set()) | {"main", "master"}, "main": base,
            "remotes": remotes(base) if base and os.path.exists(base) else [], "idle_h": None}

def safe_eval(w, d):
    ctx = make_ctx(w, d)
    try: return evaluate(w, d, ctx) + (ctx,)
    except Exception as e:                    # 判定本身出错：这一行跳过，其余照常
        return ("SKIP", "ERR", "判定出错：%s" % type(e).__name__, {"_backup": []}, ctx)

def mask(s):
    s = re.sub(r"https?://\S+", "<url>", s or "")
    s = re.sub(r"[A-Za-z0-9_\-]{24,}", "<长串>", s)
    return s.replace("\n", " ")[:60]

def in_scope(w): return not REPO or w.get("repoId") == REPO
def build(d):
    rows = []
    for w in d["wt"]:
        if not in_scope(w): continue
        rp = (d["repos"].get(w["repoId"]) or {})
        verdict, rule, why, ev, ctx = safe_eval(w, d)
        if ctx["idle_h"] is None and w.get("lastActivityAt"): ctx["idle_h"] = (NOW - w["lastActivityAt"] / 1000) / 3600
        sel = "id:" + w["id"]
        planned = {"RM": "orca worktree rm --worktree '%s'" % sel,
                   "BACKUP_RM": "备份到 %s + sha 核对，然后 orca worktree rm --worktree '%s'" % (backup_dest(rp, w), sel)}.get(verdict, "")
        rows.append({"host": HOST, "id": w["id"], "repo": rp.get("displayName") or w.get("projectId") or w["repoId"][:8],
                     "name": w.get("displayName") or "", "path": w["path"], "action": "LIST" if LIST_ONLY else verdict,
                     "verdict": verdict, "rule": rule, "reason": why, **{k: v for k, v in ev.items() if not k.startswith("_")},
                     "terms": str(len(ctx["terms"])), "idle_h": "" if ctx["idle_h"] is None else "%.0f" % ctx["idle_h"],
                     "last_activity": fmt_ms(w.get("lastActivityAt")), "unread": str(bool(w.get("isUnread"))).lower(),
                     "comment": mask(w.get("comment")),
                     "mb": du_mb(w["path"]) if verdict in ("RM", "BACKUP_RM") or LIST_ONLY else "", "planned": planned,
                     "_w": w, "_backup": ev.get("_backup") or [], "_files": ev.get("_files") or []})
    # W16：git 里登记、Orca 里没有的 worktree
    known = {os.path.realpath(w["path"]) for w in d["wt"]}
    for repo_id, mp in sorted(d["mains"].items()):
        if REPO and repo_id != REPO: continue
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
            rows.append({"host": HOST, "id": "", "repo": rp.get("displayName") or repo_id[:8], "name": "", "path": p, "action": "LIST",
                         "verdict": "LIST", "rule": "W16", "reason": "git 里有、Orca 里没有" + ("" if os.path.exists(p) else "（目录不在）"),
                         "dirty": dirty, "unpushed": unp, "terms": "0", "mb": du_mb(p), "_w": None, "_backup": []})
    rows.sort(key=lambda r: (r["repo"], r["path"]))
    trows = []
    for t in d["term"]:
        w = d["wt_by_id"].get(t.get("worktreeId"))
        if REPO and not (w and in_scope(w)): continue
        pid, state, names = term_proc(d, t)
        verdict, rule, why = term_verdict(t, d)
        trows.append({"host": HOST, "handle": t["handle"], "worktree": (w or {}).get("displayName") or t.get("worktreePath") or "",
                      "tab": t.get("tabId") or "", "action": "LIST" if LIST_ONLY else verdict, "verdict": verdict, "rule": rule,
                      "reason": why, "agent": t.get("agentIdentity") or "", "connected": str(bool(t.get("connected"))).lower(),
                      "pid": str(pid or ""), "idle_h": "" if not t.get("lastOutputAt") else "%.0f" % ((NOW - t["lastOutputAt"] / 1000) / 3600),
                      "procs": names, "archive": term_archive_dir(t) if verdict == "CLOSE" else "",
                      "planned": "存档后 orca terminal close --terminal %s" % t["handle"] if verdict == "CLOSE" else ""})
    trows.sort(key=lambda r: (r["worktree"], r["handle"]))
    return rows, trows

def fmt_ms(ms):
    return datetime.datetime.fromtimestamp(ms / 1000, SGT).strftime("%Y-%m-%d %H:%M") if ms else "0"

def term_verdict(t, d):
    w = d["wt_by_id"].get(t.get("worktreeId"))
    if SELF_TERM and t["handle"] == SELF_TERM: return "SKIP", "T3", "本任务自己的终端"
    if w and SELF and os.path.realpath(w["path"]) == SELF: return "SKIP", "T3", "本任务所在工作区的终端"
    kind = ((d["wps"] or {}).get(t.get("worktreeId")) or {}).get("workspaceKind")
    if not w or w.get("isMainWorktree") or w.get("isBare") or (w.get("hostId") or "local") != "local" or kind not in (None, "git"):
        return "SKIP", "T8", "不在清理范围（folder / main / 别的机器 / 不在 worktree list）"
    pid, state, _ = term_proc(d, t)
    if t.get("agentIdentity") or state == "agent": return "SKIP", "T1", "agent 本身所在的终端，不关"
    ag = agent_in(d, w["id"])
    if ag is None: return "SKIP", "T1", "查不到 Orca 的 agent 记录（当作有）"
    if state == "busy": return "SKIP", "T6", "还有活进程"
    if state == "unknown": return "SKIP", "T6", "查不到进程（当作有）"
    limit = AGENT_SIB_IDLE_H if ag else TERM_IDLE_H
    sib = "同一工作区有 agent 的配套 shell，" if ag else ""
    if not t.get("lastOutputAt"): return "SKIP", "T7", "没有 lastOutputAt（当作刚有输出）"
    if NOW - t["lastOutputAt"] / 1000 < limit * 3600: return "SKIP", "T7", "%s最近 %g 小时内有输出" % (sib, limit)
    r = run([ORCA, "terminal", "read", "--terminal", t["handle"], "--screen", "--limit", "60", "--json"], timeout=60)
    try: tail = json.loads(r.stdout)["result"]["terminal"]["tail"] if r.returncode == 0 else None
    except (ValueError, KeyError, TypeError): tail = None
    if tail is None: return "SKIP", "T2", "读不到屏幕（当作有 resume id）"
    lines = [l if isinstance(l, str) else json.dumps(l) for l in tail]
    if any(RESUME.search(l) for l in lines): return "SKIP", "T2", "屏幕上有 resume id"
    if state == "gone": return "CLOSE", "T5", "进程已经不在"
    last = next((l for l in reversed(lines) if l.strip()), "")
    if not PROMPT.search(last): return "SKIP", "T2", "最后一行不是空提示符"
    return "CLOSE", "T4", "%s空 shell，空闲超过 %g 小时" % (sib, limit) if ag else "空 shell"

# ---------- --execute ----------
def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()
def safe_name(s): return re.sub(r"[^\w.\-]+", "_", s).strip("_") or "_"
def backup_dest(rp, w):
    return os.path.join(ARCHIVE, datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y-%m-%d"),
                        safe_name(rp.get("displayName") or w["repoId"]), safe_name(os.path.basename(w["path"])))
def backup_files(path, items):
    """要复制的 (相对路径, 'file'|'link')；遇到非普通文件抛 OSError。"""
    out = []
    def add(rel):
        m = os.lstat(os.path.join(path, rel)).st_mode
        if stat.S_ISLNK(m): out.append((rel, "link"))
        elif stat.S_ISREG(m): out.append((rel, "file"))
        elif not stat.S_ISDIR(m): raise OSError("不是普通文件：" + rel)
    for it in items:
        full = os.path.join(path, it)
        if os.path.isdir(full) and not os.path.islink(full):
            for root, dirs, fs in os.walk(full):
                for x in sorted(dirs):
                    sub = os.path.relpath(os.path.join(root, x), path)
                    if x == ".git": raise OSError("嵌套 git 仓库：" + sub)
                    if rebuildable(sub): dirs.remove(x)
                    elif os.path.islink(os.path.join(root, x)): dirs.remove(x); add(sub)
                for f in sorted(fs):
                    sub = os.path.relpath(os.path.join(root, f), path)
                    if not rebuildable(sub): add(sub)
        else: add(it)
    return out
def do_backup(r, rp):
    w = r["_w"]; path = w["path"]
    dest = backup_dest(rp, w)
    if os.path.exists(dest): return False, "备份目录已存在，不覆盖"
    files = backup_files(path, r["_backup"])
    os.makedirs(dest, mode=0o700)
    os.chmod(dest, 0o700)
    sums, bad = {}, []
    for f, kind in files:
        src, dst = os.path.join(path, f), os.path.join(dest, f)
        os.makedirs(os.path.dirname(dst), mode=0o700, exist_ok=True)
        if kind == "link": os.symlink(os.readlink(src), dst); sums[f] = "symlink -> " + os.readlink(src); continue
        before = sha256(src)
        shutil.copy2(src, dst)
        os.chmod(dst, 0o600)
        sums[f] = before
        if sha256(dst) != before or sha256(src) != before: bad.append(f)
    with open(os.path.join(dest, "MANIFEST.sha256"), "w") as m:
        for f in sorted(sums): m.write("%s  %s\n" % (sums[f], f))
    if bad: return False, "sha 对不上（文件在变）：%s" % ";".join(bad[:5])
    return True, dest                         # 原位置一个都不删：rm 成功时整个目录会一起删掉，rm 失败时工作区原样留着

def term_archive_dir(t):
    return os.path.join(ARCHIVE, "terminals", datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y-%m-%d"), safe_name(t["handle"]))
RESTORE = """找回这个终端（ws-cleanup 关之前存的档）：
- scrollback.txt：关之前的全部输出（orca terminal read，去掉了转义序列）。
- meta.json：Orca 的终端元数据（handle、tabId、ptyId、worktreeId、worktreePath、title、lastOutputAt）、shell pid、cwd。
- 重开：在 Orca 里打开 meta.json 的 worktreePath 对应的工作区，新建终端，cd 到 meta.json 的 cwd；
  如果 scrollback 里有 agent 的 resume 命令，照它恢复会话。
"""
def archive_term(t, d):
    """关终端前存档；任何一步失败抛异常（调用方据此不关）。"""
    dest = term_archive_dir(t)
    if os.path.exists(dest): raise OSError("存档目录已存在，不覆盖：" + dest)
    r = run([ORCA, "terminal", "read", "--terminal", t["handle"], "--limit", "100000", "--json"], timeout=120)
    if r.returncode != 0: raise OSError("orca terminal read 失败")
    tail = json.loads(r.stdout)["result"]["terminal"]["tail"]
    s = run([ORCA, "terminal", "show", "--terminal", t["handle"], "--json"], timeout=60)
    if s.returncode != 0: raise OSError("orca terminal show 失败")
    meta = json.loads(s.stdout)["result"]["terminal"]
    pid, state, _ = term_proc(d, t)
    cwd = None
    if state != "gone":                       # 进程已不在的终端没有 cwd 可查，其余查不到就算存档失败
        shell = (kids_of(d["ps"], pid) or [pid])[0]
        lsof = ENV.get("WS_LSOF") or shutil.which("lsof") or "/usr/sbin/lsof"
        c = run([lsof, "-a", "-d", "cwd", "-p", str(shell), "-Fn"], timeout=30)
        cwd = next((l[1:] for l in c.stdout.splitlines() if l.startswith("n")), None) if c.returncode == 0 else None
        if not cwd: raise OSError("查不到 shell 的 cwd")
    os.makedirs(dest, mode=0o700); os.chmod(dest, 0o700)
    for name, body in (("scrollback.txt", "\n".join(l if isinstance(l, str) else json.dumps(l) for l in tail) + "\n"),
                       ("meta.json", json.dumps(dict(meta, shellPid=pid, cwd=cwd or "（进程已不在）"), ensure_ascii=False, indent=1)),
                       ("README.txt", RESTORE)):
        fd = os.open(os.path.join(dest, name), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f: f.write(body)
    return dest

class Journal:
    """每次动手前后各写一行，立刻落盘，不靠最后统一写。"""
    def __init__(self, path): self.f = open(path, "a")
    def __call__(self, *cols):
        self.f.write("\t".join([datetime.datetime.now(SGT).strftime("%Y-%m-%d %H:%M:%S")] + [clean(c) for c in cols]) + "\n")
        self.f.flush(); os.fsync(self.f.fileno())

def load_list(tsv, key, verdicts):
    try: rows = list(csv.DictReader(open(tsv), delimiter="\t"))
    except OSError as e: die("读不到名单 %s：%s" % (tsv, e), 2)
    if rows and key not in rows[0]: die("名单 %s 里没有 %s 列（要用这一版脚本跑出来的 dry-run）" % (tsv, key), 2)
    if any(x.get("host") not in (HOST, None) for x in rows): die("名单 %s 不是这台机器（%s）的" % (tsv, HOST), 2)
    return {x[key]: x for x in rows if x.get("verdict") in verdicts}

def pause_point():
    p = ENV.get("WS_PAUSE_FILE") if TEST else None
    if not p: return
    open(p + ".ready", "w").close()
    for _ in range(1200):
        if os.path.exists(p): return
        time.sleep(0.1)
    raise RuntimeError("等 WS_PAUSE_FILE 超时")

def execute(rows, trows, journal):
    fails = 0
    listed = load_list(ONLY_FROM, "id", ("RM", "BACKUP_RM"))
    if REPO:                                  # 演练白名单（Zack 03:40）：名单里、要动的，有一个不在 --repo 下就整轮中止
        bad = [k for k in listed if not k.startswith(REPO + "::")] + [r["id"] for r in rows if r["_w"] and r["_w"].get("repoId") != REPO]
        if bad: die("--repo %s 白名单外有 %d 个候选（例如 %s），整轮中止，什么都没做" % (REPO, len(bad), bad[0]), 2)
    tlisted = load_list(os.path.join(os.path.dirname(ONLY_FROM) or ".", "terminals.tsv"), "handle", ("CLOSE",)) if CLOSE_TERMS else {}
    pause_point()
    for r in rows:
        if r["verdict"] not in ("RM", "BACKUP_RM") or not r["_w"]: continue
        old = listed.get(r["id"])
        if not old: r["result"] = "没动：不在 --only-from 名单里"; continue
        try:
            fresh = collect()                 # 每个工作区动手前都重新取实时数据：orca、终端、ps、git、gh、Linear 都不用缓存
            w = fresh["wt_by_id"].get(r["id"])
            if not w: r["result"] = "跳过：Orca 里已经没有"; continue
            if w.get("lastActivityAt") != r["_w"].get("lastActivityAt") or fmt_ms(w.get("lastActivityAt")) != old.get("last_activity"):
                r["result"] = "跳过：lastActivityAt 变了"; continue
            v2, rule2, why2, ev2, _ = safe_eval(w, fresh)
            if v2 != old["verdict"] or ev2.get("backup", "") != old.get("backup", ""):
                r["result"] = "跳过：重新判定变成 %s %s（%s）" % (v2, rule2, why2) if v2 != old["verdict"] else "跳过：备份清单和名单里的不一样"
                continue
            r["_w"], r["_backup"] = w, ev2["_backup"]
            if v2 == "BACKUP_RM":
                ok, msg = do_backup(r, fresh["repos"].get(w["repoId"]) or {})
                journal("backup", r["id"], "0" if ok else "1", msg)
                if not ok: r["result"] = "BACKUP_FAIL：" + msg; fails += 1; continue
                r["result"] = "已备份到 " + msg
            journal("rm-start", r["id"], "", "")
            p = run([ORCA, "worktree", "rm", "--worktree", "id:" + w["id"], "--json"], timeout=300)
            journal("rm-end", r["id"], str(p.returncode), (p.stdout or p.stderr).strip()[:300])
            msg = (p.stderr or p.stdout).strip().splitlines()
            done = "已 rm" if p.returncode == 0 else "rm 失败（不重试、不加 --force）：" + (msg[-1][:200] if msg else "")
            r["result"] = r["result"] + "；" + done if r.get("result") else done
            fails += p.returncode != 0
        except Exception as e:
            r["result"] = (r.get("result", "") + "；" if r.get("result") else "") + "ERROR：%s %s" % (type(e).__name__, str(e)[:120])
            journal("error", r["id"], "", r["result"]); fails += 1
    for r in trows:
        if r["verdict"] != "CLOSE": continue
        if not CLOSE_TERMS: r["result"] = "没关：没带 --close-terminals"; continue
        if r["handle"] not in tlisted: r["result"] = "没动：不在名单里"; continue
        try:
            fresh = collect()
            t = next((x for x in fresh["term"] if x["handle"] == r["handle"]), None)
            if not t: r["result"] = "跳过：终端已经没有了"; continue
            v2, rule2, why2 = term_verdict(t, fresh)
            if v2 != "CLOSE": r["result"] = "跳过：重新判定变成 %s %s（%s）" % (v2, rule2, why2); continue
            try: dest = archive_term(t, fresh)
            except Exception as e:
                r["result"] = "没关：存档失败（%s）" % str(e)[:120]; journal("archive", r["handle"], "1", r["result"]); fails += 1; continue
            journal("archive", r["handle"], "0", dest)
            journal("close-start", r["handle"], "", "")
            p = run([ORCA, "terminal", "close", "--terminal", r["handle"], "--json"], timeout=60)   # 只关这一个窗格，不带 --tab
            journal("close-end", r["handle"], str(p.returncode), (p.stdout or p.stderr).strip()[:300])
            r["result"] = ("已存档到 %s；已关" if p.returncode == 0 else "已存档到 %s；关闭失败") % dest
            fails += p.returncode != 0
        except Exception as e:
            r["result"] = "ERROR：%s" % type(e).__name__; journal("error", r["handle"], "", r["result"]); fails += 1
    return fails

def take_lock():
    os.makedirs(os.path.dirname(LOCK), exist_ok=True)
    for _ in range(2):
        try:
            os.mkdir(LOCK); open(os.path.join(LOCK, "pid"), "w").write(str(os.getpid())); return
        except FileExistsError:
            try: pid = int(open(os.path.join(LOCK, "pid")).read().strip())
            except (OSError, ValueError): pid = None
            alive = True
            if pid:
                try: os.kill(pid, 0)
                except ProcessLookupError: alive = False
                except PermissionError: pass
            if alive: die("另一个 --execute 正在跑（锁 %s，pid %s），这次什么都不做" % (LOCK, pid), 6)
            shutil.rmtree(LOCK)               # 锁里的 pid 已经不在：上次异常退出留下的
    die("拿不到锁 %s" % LOCK, 6)

# ---------- 输出 ----------
WCOLS = ["host", "id", "repo", "name", "path", "action", "verdict", "rule", "reason", "status", "pr", "head_vs_pr", "merged_via", "linear", "dirty",
         "unpushed", "head", "terms", "idle_h", "last_activity", "unread", "comment", "mb", "backup", "backup_size", "rebuild", "planned"]
TCOLS = ["host", "handle", "worktree", "tab", "action", "verdict", "rule", "reason", "agent", "connected", "pid", "idle_h", "procs", "archive", "planned"]
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

def preflight(d):
    probs = []
    if not GH: probs.append("找不到 gh")
    elif run([GH, "auth", "status"], timeout=60).returncode != 0: probs.append("gh 不可用（gh auth status 失败）")
    if d["pid"] is None: probs.append("orca diagnostics memory 查不到")
    if d["wps"] is None: probs.append("orca worktree ps 查不到")
    if d["ps"] is None: probs.append("ps 查不到")
    return probs

def summary(rows, trows, fails, probs, note):
    from collections import Counter
    c = Counter(r["action"] for r in rows); v = Counter(r["verdict"] for r in rows); rc = Counter(r["rule"] for r in rows)
    mb = lambda k: sum(int(r["mb"]) for r in rows if r["verdict"] == k and r.get("mb", "").isdigit())
    mode = "执行" if EXECUTE else "precheck" if PRECHECK else "list-only" if LIST_ONLY else "dry-run"
    L = []
    if probs: L += ["**环境不对：%s。%s**" % ("；".join(probs), "--execute 什么都没做" if EXECUTE else "结论不可靠"), ""]
    if note: L += ["**%s**" % note, ""]
    L += ["# ws-cleanup %s（%s，%s）" % (mode, HOST, datetime.datetime.fromtimestamp(NOW, SGT).strftime("%Y-%m-%d %H:%M:%S SGT")), "",
          "orca：`%s`；gh：`%s`；工作区空闲门槛 %g 小时，终端 %g 小时；备份根目录 `%s`%s。" % (
              ORCA, GH or "无", IDLE_H, TERM_IDLE_H, ARCHIVE, "；只看 repo %s" % REPO if REPO else ""), "",
          "| 动作 | 工作区 |", "|---|---|"] + ["| %s | %d |" % (k, c[k]) for k in ("RM", "BACKUP_RM", "SKIP", "LIST") if c[k]]
    if LIST_ONLY:
        L += ["", "只列出；如果在这台机器上清理，结论会是：" + "，".join("%s %d" % (k, v[k]) for k in ("RM", "BACKUP_RM", "SKIP", "LIST") if v[k])]
    L += ["", "RM 合计约 %d MB，BACKUP_RM 合计约 %d MB（du）。" % (mb("RM"), mb("BACKUP_RM")), "",
          "| 规则 | 个数 |", "|---|---|"] + ["| %s | %d |" % (k, rc[k]) for k in sorted(rc, key=lambda x: (x[0] != "W", int(x[1:]) if x[1:].isdigit() else 99))]
    conflict = [r for r in rows if r["rule"] == "W11" and "状态冲突" in r["reason"]]
    if conflict: L += ["", "状态冲突、这次不删、等 Zack 定的：%d 个（worktrees.tsv 里 W11 且原因写「状态冲突」）" % len(conflict)]
    lin_fail = [r for r in rows if r["rule"] == "W10" and "查不到" in r["reason"]]
    if lin_fail: L += ["", "Linear 查不到的：%d 个（都当作没关）" % len(lin_fail)]
    tc = Counter(r["action"] for r in trows); trc = Counter(r["rule"] for r in trows)
    L += ["", "终端：" + "，".join("%s %d" % kv for kv in sorted(tc.items())) + "（" + "，".join("%s %d" % kv for kv in sorted(trc.items())) + "）"]
    if any(r["verdict"] == "CLOSE" for r in trows):
        L += ["", "关终端之前先存档到 `%s/<handle>/`（terminals.tsv 的 archive 列）：scrollback.txt、meta.json（含 cwd）、README.txt（怎么找回）；"
              "存档失败就不关。只有带 --close-terminals 才会关。" % os.path.dirname(term_archive_dir({"handle": "x"}))]
    ex = expired_backups()
    L += ["", "超过 30 天的备份（只列出，删除另外批准）：" + ("、".join(ex) if ex else "无")]
    if EXECUTE: L += ["", "没做成的：%d 个（见 worktrees.tsv / terminals.tsv 的 result 列，逐条动作见 journal.tsv）" % fails]
    return "\n".join(L) + "\n"

def main():
    d = collect()
    probs = preflight(d)
    rows, trows = build(d)
    os.makedirs(OUT, exist_ok=True)
    fails, note, code, locked = 0, "", 0, False
    try:
        if EXECUTE and probs: code = 5
        elif EXECUTE:
            take_lock(); locked = True
            fails = execute(rows, trows, Journal(os.path.join(OUT, "journal.tsv")))
        elif probs: code = 5
    except SystemExit: raise
    except Exception as e:
        note = "中途出错：%s %s（已做的见 journal.tsv）" % (type(e).__name__, str(e)[:200]); fails += 1
    finally:
        if locked: shutil.rmtree(LOCK, ignore_errors=True)
        wc, tc = WCOLS + (["result"] if EXECUTE else []), TCOLS + (["result"] if EXECUTE else [])
        write_tsv(os.path.join(OUT, "worktrees.tsv"), wc, rows)
        write_tsv(os.path.join(OUT, "terminals.tsv"), tc, trows)
        write_tsv(os.path.join(OUT, "backup-files.tsv"), ["path", "verdict", "file", "bytes"],   # 每个工作区会备份的被忽略文件，逐个列出
                  [{"path": r["path"], "verdict": r["verdict"], "file": f, "bytes": b} for r in rows for f, b in r.get("_files") or []])
        s = summary(rows, trows, fails, probs, note)
        open(os.path.join(OUT, "summary.md"), "w").write(s)
        print(s, end=""); print("输出：" + OUT)
    sys.exit(1 if PRECHECK else code or (3 if fails else 0))
main()
PYEOF
