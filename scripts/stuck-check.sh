#!/bin/bash
# stuck-check.sh [--dry-run]: 卡住工作检查（Orca 自动化「卡住工作检查」每小时调用）。
# 查 iMac 和 box 两套 Orca 的任务工作区（非主目录、非归档的 git 工作区），找两类问题：
#   (a) 已收工但 PR 没跟上：工作区标 completed/in-review、Linear 卡片 completed 或有 *.done 标记，
#       超过 1 小时仍没有 PR（finished_no_pr）；或 PR 开了超过 1 小时没人 review/评论（pr_not_reviewed，Linear 等自动回链评论不算）。
#   (b) agent 中途停下：没有收工信号也没有 PR，agent 超过 1 小时不在工作（agent_idle），
#       或终端还在但里面已经没有 agent（agent_exited）。
# bot 归属按 ~/orca/workspaces/ops/orca-projects.md 映射。只有发现问题才逐条 POST
# {bot,task,worktree,issue,note} 到 ~/.config/grokbot/stuck-webhook.env 里的 URL（KEY 作为 Bearer）。
# 该文件不存在时只写日志并 exit 0。同一问题 24 小时内只发一次（STUCK_RENOTIFY_HOURS）。
# --dry-run：只打印，不 POST，不记已通知状态。
# 退出码：0 正常；2 iMac Orca 查询失败；3 webhook 发送失败。
set -u
PY=$(command -v python3 || echo /usr/bin/python3)
exec "$PY" - "$@" <<'PYEOF'
import datetime, json, os, re, shutil, subprocess, sys, time, urllib.request

HOME = os.path.expanduser("~")
DRY = "--dry-run" in sys.argv[1:]
THRESH_H = float(os.environ.get("STUCK_THRESHOLD_HOURS", "1"))
RENOTIFY_H = float(os.environ.get("STUCK_RENOTIFY_HOURS", "24"))
MAPPING = os.path.join(HOME, "orca/workspaces/ops/orca-projects.md")
ENV_FILE = os.path.join(HOME, ".config/grokbot/stuck-webhook.env")
STATE_DIR = os.path.join(HOME, ".orca-state/stuck-check")
LOG_FILE = os.path.join(STATE_DIR, "stuck-check.log")
SEEN_FILE = os.path.join(STATE_DIR, "notified.json")
SGT = datetime.timezone(datetime.timedelta(hours=8))
NOW = time.time()
os.makedirs(STATE_DIR, exist_ok=True)


def log(msg):
    line = "%s %s" % (datetime.datetime.now(SGT).strftime("%F %T SGT"), msg)
    print(line, flush=True)
    if not DRY:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


def run(cmd, timeout=90):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


ORCA = (shutil.which("orca-ide") or shutil.which("orca")
        or "/Applications/Orca.app/Contents/Resources/bin/orca")


def orca_json(args, env=None):
    cmd = [ORCA] + args + (["--environment", env] if env else []) + ["--json"]
    rc, out, err = run(cmd)
    if rc != 0:
        return None, err or out.strip()[:200]
    try:
        d = json.loads(out)
    except ValueError:
        return None, "非 JSON 输出"
    if not d.get("ok"):
        return None, json.dumps(d.get("error"), ensure_ascii=False)[:200]
    return d["result"], None


def hours(ms_or_s, ms=True):
    if not ms_or_s:
        return None
    return (NOW - (ms_or_s / 1000.0 if ms else ms_or_s)) / 3600.0


def iso_ts(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


# ---- bot 映射：orca-projects.md 的「Repo → 项目 ID」表和「Bot → 工作区」表 ----
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
SLUG = re.compile(r"[\w.-]+/[\w.-]+")
LINEAR_RUN = re.compile(r"\b([A-Z]{2,6})-(\d+(?:\s*/\s*\d+)*)")


def load_mapping():
    by_id, by_name, by_linear = {}, {}, {}
    try:
        lines = open(MAPPING, encoding="utf-8").read().splitlines()
    except OSError as e:
        log("映射文件读不到（%s），bot 一律记为「未映射」" % e)
        return by_id, by_name, by_linear
    for ln in lines:
        if not ln.startswith("|") or set(ln) <= set("|-: "):
            continue
        c = [x.strip() for x in ln.strip().strip("|").split("|")]
        if len(c) != 4:
            continue
        m = UUID.fullmatch(c[2])
        if m:  # Repo | Orca 项目 | 项目 ID | 路径
            s = SLUG.match(c[0])
            by_id[c[2]] = {"slug": s.group(0) if s else None, "name": c[1]}
            continue
        bot = c[0]
        if bot in ("Bot", "") or bot.startswith("（"):
            continue
        name = re.sub(r"\(.*?\)", "", c[2]).strip()
        if name and name != "—":
            by_name.setdefault(name, bot)
        for pre, nums in LINEAR_RUN.findall(c[1] + " " + c[3]):
            for n in re.split(r"\s*/\s*", nums):
                by_linear.setdefault("%s-%s" % (pre, n), bot)
    return by_id, by_name, by_linear


MAP_ID, MAP_NAME, MAP_LINEAR = load_mapping()


def bot_for(repo_id, repo_name, slug, linear):
    if linear and linear in MAP_LINEAR:
        return MAP_LINEAR[linear]
    info = MAP_ID.get(repo_id, {})
    slug = slug or info.get("slug")
    names = [info.get("name"), repo_name, slug.split("/")[-1] if slug else None]
    names += [v["name"] for v in MAP_ID.values() if slug and v["slug"] == slug]
    for n in names:
        if n and n in MAP_NAME:
            return MAP_NAME[n]
    return "未映射"


# ---- GitHub PR / Linear 查询（都在 iMac 上跑，带缓存） ----
_pr_cache, _linear_cache = {}, {}
GH_USER = None
PR_FIELDS = "number,state,headRefName,createdAt,reviewDecision,reviews,comments,url"
# 这些账号的评论是自动回链，不算有人看过 PR
AUTO_COMMENTERS = {"linear", "github-actions", "vercel", "cloudflare-workers-and-pages", "codecov", "dependabot"}


def gh_prs(slug, extra):
    """slug + 过滤条件 → PR 列表；查询失败返回 None。"""
    k = (slug,) + tuple(extra)
    if k not in _pr_cache:
        rc, out, err = run(["gh", "pr", "list", "-R", slug, "--state", "all", "--limit", "200",
                            "--json", PR_FIELDS] + list(extra))
        try:
            _pr_cache[k] = json.loads(out) if rc == 0 else None
        except ValueError:
            _pr_cache[k] = None
        if _pr_cache[k] is None and "Could not resolve to a Repository" not in err:
            log("gh pr list %s 失败：%s" % (slug, err[:120]))
    return _pr_cache[k]


def prs_for(slug, branch):
    """先用自己账号开的 PR（一次查完），没命中再按分支名单独查。"""
    mine = gh_prs(slug, ["--author", "@me"])
    if mine and any(p["headRefName"] == branch for p in mine):
        return mine
    return gh_prs(slug, ["--head", branch])


def reviewed(pr):
    human = [c for c in pr.get("comments") or []
             if (c.get("author") or {}).get("login") not in AUTO_COMMENTERS
             and not ((c.get("author") or {}).get("login") or "").endswith("[bot]")]
    return bool(pr.get("reviews") or pr.get("reviewDecision") or human)


def find_pr(slugs, branch, linked_number):
    """返回 (pr 或 None, 是否查询成功)。"""
    ok = False
    for slug in slugs:
        prs = prs_for(slug, branch)
        if prs is None:
            continue
        ok = True
        hits = [p for p in prs if p["headRefName"] == branch]
        if not hits and linked_number and slug == slugs[0]:
            hits = [p for p in gh_prs(slug, ["--author", "@me"]) or [] if p["number"] == linked_number]
        if hits:
            hits.sort(key=lambda p: (p["state"] != "OPEN", -p["number"]))
            return hits[0], True
    return None, ok


def linear_state(ident):
    if ident not in _linear_cache:
        res, _ = orca_json(["linear", "issue", ident])
        iss = (res or {}).get("issue") or {}
        _linear_cache[ident] = ((iss.get("state") or {}).get("type"), iso_ts(iss.get("updatedAt")))
    return _linear_cache[ident]


def done_marker(path):
    """本机工作区里最新的 *.done 标记（3 层以内，跳过 node_modules/.git）。"""
    best = None
    base = path.rstrip("/").count("/")
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in ("node_modules", ".git", ".wrangler", ".next", "dist")]
        if root.count("/") - base >= 2:
            dirs[:] = []
        for f in files:
            if f.endswith(".done"):
                try:
                    mt = os.path.getmtime(os.path.join(root, f))
                except OSError:
                    continue
                if best is None or mt > best[1]:
                    best = (os.path.relpath(os.path.join(root, f), path), mt)
    return best


# ---- 检查一台 Orca ----
def check_host(label, env):
    ps, err = orca_json(["worktree", "ps"], env)
    if ps is None:
        return None, err
    repos, _ = orca_json(["repo", "list"], env)
    repos = (repos or {}).get("repos") or []
    slug_of = {}
    for r in repos:
        key = (r.get("gitRemoteIdentity") or {}).get("canonicalKey") or ""
        if key.startswith("github.com/"):
            slugs = [key[len("github.com/"):]]
            up = r.get("upstream") or {}
            if up.get("owner") and "%s/%s" % (up["owner"], up["repo"]) not in slugs:
                slugs.append("%s/%s" % (up["owner"], up["repo"]))
            user = GH_USER or r.get("gitUsername")  # fork 上的 PR 也算
            if user and slugs[0].split("/")[0] != user:
                slugs.append("%s/%s" % (user, slugs[0].split("/")[1]))
            slug_of[r["id"]] = slugs
    found, scanned = [], 0
    for w in ps.get("worktrees", []):
        if w.get("workspaceKind") != "git" or w.get("isMainWorktree") or w.get("isArchived"):
            continue
        scanned += 1
        linear = w.get("linkedLinearIssue")
        lstate, lts = linear_state(linear) if linear else (None, None)
        if lstate == "canceled":
            continue
        branch = (w.get("branch") or "").replace("refs/heads/", "")
        slugs = slug_of.get(w.get("repoId")) or []
        if not slugs and MAP_ID.get(w.get("repoId"), {}).get("slug"):
            slugs = [MAP_ID[w["repoId"]]["slug"]]
        bot = bot_for(w.get("repoId"), w.get("repo"), slugs[0] if slugs else None, linear)
        task = ("%s %s" % (linear or "", w.get("displayName") or "")).strip()
        if linear and linear in (w.get("displayName") or ""):
            task = w["displayName"]
        where = "%s:%s" % (label, w["path"])

        def add(issue, note):
            found.append({"bot": bot, "task": task, "worktree": where, "issue": issue, "note": note})

        status = w.get("workspaceStatus")
        marker = done_marker(w["path"]) if env is None and os.path.isdir(w["path"]) else None
        signals, finished_at = [], []
        if status in ("completed", "in-review"):
            signals.append("工作区标为 %s" % status)
            finished_at.append((w.get("lastActivityAt") or 0) / 1000.0)
        if lstate == "completed":
            signals.append("Linear %s 已完成" % linear)
            finished_at.append(lts or 0)
        if marker:
            signals.append("有标记 %s" % marker[0])
            finished_at.append(marker[1])

        pr, pr_ok = (None, False)
        if slugs and branch:
            pr, pr_ok = find_pr(slugs, branch, (w.get("linkedPR") or {}).get("number"))

        if pr:
            age = hours(iso_ts(pr["createdAt"]), ms=False)
            if pr["state"] == "OPEN" and not reviewed(pr) and age is not None and age > THRESH_H:
                add("pr_not_reviewed", "PR 已开 %.1f 小时，没有 review，也没有人评论：%s" % (age, pr["url"]))
            continue  # 有 PR 就不再按 agent 状态报
        if slugs and not pr_ok:
            continue  # PR 查询失败，不误报
        if signals:
            age = hours(max(finished_at), ms=False) if max(finished_at) > 0 else None
            if age is None or age > THRESH_H:
                add("finished_no_pr", "%s，%s没有 PR（分支 %s%s）" % (
                    "；".join(signals), "已 %.1f 小时" % age if age is not None else "",
                    branch or "?", "" if slugs else "，仓库没有 GitHub 远端"))
            continue
        agents = w.get("agents") or []
        if any(a.get("state") == "working" for a in agents):
            continue
        if agents:
            last = max(agents, key=lambda a: a.get("updatedAt") or a.get("stateStartedAt") or 0)
            idle = hours(max(last.get("updatedAt") or 0, last.get("stateStartedAt") or 0))
            if idle is not None and idle > THRESH_H:
                add("agent_idle", "%s 处于 %s 状态已 %.1f 小时%s，没有收工标记，也没有 PR" % (
                    last.get("agentType") or "agent", last.get("state"), idle,
                    "（被中断）" if last.get("interrupted") else ""))
        elif (w.get("liveTerminalCount") or 0) > 0 and status in ("in-progress", "todo"):
            idle = hours(w.get("lastActivityAt"))
            if idle is None or idle > THRESH_H:
                add("agent_exited", "终端还开着（%d 个）但里面没有 agent 在跑，工作区状态 %s%s，没有收工标记，也没有 PR" % (
                    w["liveTerminalCount"], status, "，最近活动在 %.1f 小时前" % idle if idle is not None else ""))
    return (found, scanned), None


def main():
    global GH_USER
    rc, out, _ = run(["gh", "api", "user", "-q", ".login"], 30)
    GH_USER = out.strip() if rc == 0 and out.strip() else None
    log("开始%s（orca=%s，阈值 %.1f 小时）" % ("（dry-run）" if DRY else "", os.path.basename(ORCA), THRESH_H))
    problems = []
    res, err = check_host("iMac", None)
    if res is None:
        log("iMac Orca 查询失败：%s" % err)
        return 2
    problems += res[0]
    log("iMac：查了 %d 个任务工作区，%d 个问题" % (res[1], len(res[0])))

    box_env = os.environ.get("STUCK_BOX_ENV")
    if not box_env:
        rc, out, _ = run([ORCA, "environment", "list"], 30)
        names = [ln.split()[1] for ln in out.splitlines() if len(ln.split()) >= 2] if rc == 0 else []
        box_env = next((n for n in ("box", "grok-bot") if n in names), None)
    if not box_env:
        log("box：没有配好的 Orca environment，跳过")
    else:
        res, err = check_host("box", box_env)
        if res is None:
            log("box（--environment %s）查询失败，跳过：%s" % (box_env, err))
        else:
            problems += res[0]
            log("box（--environment %s）：查了 %d 个任务工作区，%d 个问题；box 上的 *.done 标记读不到，未检查" % (
                box_env, res[1], len(res[0])))

    for p in problems:
        log("问题 | %s | %s | %s | %s | %s" % (p["bot"], p["issue"], p["task"], p["worktree"], p["note"]))
    if not problems:
        log("没有发现问题，不发 webhook")
        return 0

    try:
        seen = json.load(open(SEEN_FILE))
    except (OSError, ValueError):
        seen = {}
    key = lambda p: "%s|%s" % (p["worktree"], p["issue"])
    seen = {k: v for k, v in seen.items() if k in {key(p) for p in problems}}  # 已消失的问题清掉
    due = [p for p in problems if NOW - seen.get(key(p), 0) >= RENOTIFY_H * 3600]
    log("共 %d 个问题，其中 %d 个需要通知（其余 %.0f 小时内已通知过）" % (len(problems), len(due), RENOTIFY_H))

    if not os.path.isfile(ENV_FILE):
        log("webhook 未配置（%s 不存在），只记日志，不发送" % ENV_FILE)
        return 0
    cfg = {}
    for ln in open(ENV_FILE):
        m = re.match(r"\s*(?:export\s+)?(URL|KEY)\s*=\s*(.*?)\s*$", ln)
        if m:
            cfg[m.group(1)] = m.group(2).strip("'\"")
    if not cfg.get("URL") or not cfg.get("KEY"):
        log("webhook 配置不完整（%s 缺 URL 或 KEY），只记日志，不发送" % ENV_FILE)
        return 0
    if DRY:
        for p in due:
            log("dry-run，将 POST：%s" % json.dumps(p, ensure_ascii=False))
        return 0
    failed = 0
    for p in due:
        req = urllib.request.Request(cfg["URL"], data=json.dumps(p, ensure_ascii=False).encode("utf-8"), method="POST",
                                     headers={"Content-Type": "application/json", "Authorization": "Bearer " + cfg["KEY"]})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                code = r.status
        except Exception as e:  # noqa: BLE001 — 任何发送失败都只记一行，继续发下一条
            code = getattr(e, "code", None) or type(e).__name__
        if isinstance(code, int) and 200 <= code < 300:
            seen[key(p)] = NOW
            log("已 POST（%s）：%s | %s" % (code, p["issue"], p["worktree"]))
        else:
            failed += 1
            log("POST 失败（%s）：%s | %s" % (code, p["issue"], p["worktree"]))
    with open(SEEN_FILE, "w") as f:
        json.dump(seen, f, ensure_ascii=False, indent=1)
    return 3 if failed else 0


sys.exit(main())
PYEOF
