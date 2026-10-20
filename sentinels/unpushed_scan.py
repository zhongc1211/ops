#!/usr/bin/env python3
"""unpushed_scan.py — ops · 24 未推送扫描（box 和 iMac 各跑一份，每小时，各扫本机的 Orca 工作区）。

对本机 `orca worktree list` 里的每个工作区（只读，GIT_OPTIONAL_LOCKS=0，不 fetch、不提交、不推、不 stash、不 reset）：
  unpushed — HEAD 上有不在任何远程分支里的提交（git rev-list HEAD --not --remotes），最早的一个超过 2 小时
  dirty    — 有未提交的改动（含未跟踪文件，不含未跟踪的 node_modules 软链接），其中最早的一处改动超过 2 小时
发现了就用 notify-run 叫醒该项目的 bot（按 git remote 认项目），同一个 bot 一次运行只叫一次，消息里列出全部发现。
限流（状态在 ~/.orca-state/unpushed-scan/state.json）：
  - 同一个工作区 4 小时内只叫一次（项目 bot 和 coding-assistant 都算），不管是哪种发现、内容变没变；
  - 新发现：这个工作区 4 小时内没叫过就马上叫项目 bot，计数从 1 开始；
  - 内容变了（最早没推送的提交 / HEAD 加改动列表不同）：叫醒次数重新数（最多记 1 次），但不重置计时
    （10-19 ops 主目录改动数 26→28，00:29、02:29 各叫一次）；
  - 没变：距上次叫醒满 4 小时才再叫项目 bot；已经叫过 2 次还没变，第 3 次改叫 coding-assistant，之后每 24 小时最多再叫它一次；
  - 发现消失了就删掉它的记录。
日志一行一条打印到 stdout，并追加到 --log（box 上就是 /workspace/ops/reports/unpushed-scan-YYYYMMDD.log；
iMac 上是本机镜像，由 unpushed-scan.sh 再经 ssh 追加到 box 的同一个文件）。
忽略名单 IGNORE：按 --machine 和路径跳过的工作区（如 MBA 的 ~/orca/projects/local 占位仓库）。
演练：--only <路径前缀> 只扫这些工作区，--state 用单独的状态文件，--drill 让叫醒标题带「【演练】」，
  环境变量 UNPUSHED_FORCE_BOT=<bot> 让所有叫醒改发给这个 bot（演练用 ops-system，task 带「[演练 叫醒通路]」前缀，不叫醒业务 bot）。
退出码：0 = 扫完（不管有没有发现）；2 = 拿不到工作区列表。
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import time

SGT = dt.timezone(dt.timedelta(hours=8))
DIRTY_AGE = 2 * 3600
REWAKE = 4 * 3600
ESCALATE_EVERY = 24 * 3600
BOTS = [  # (git remote 里的关键字, bot)
    ("deepvision-site", "deepvision-ops"),
    ("deepvision-ads", "deepvision-ads"),
    ("xinyue", "xinyue"),
    ("vllm-omni", "vllm-omni"),
]
IGNORE = [  # (机器, 路径)：这些工作区不扫，也不算进「扫了 N 个工作区」
    ("mba", "~/orca/projects/local"),  # Orca 自动生成的占位仓库，只有一个 Initial commit，没有远程
    ("imac", "~/claude/worker"),  # 停用的 Lark 秘书 worker，没有远程；2026-10-19 已归档到 ~/ops-archive/20261019/claude-worker.tar.zst，原目录保留
]
FORCE_BOT = os.environ.get("UNPUSHED_FORCE_BOT")
NOTIFY_RUN = shutil.which("notify-run") or os.path.expanduser("~/.local/bin/notify-run")
GIT_ENV = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0", LC_ALL="C")


def now_s():
    return dt.datetime.now(SGT).strftime("%Y-%m-%d %H:%M:%S")


class Log:
    def __init__(self, path, machine):
        self.path, self.machine = path, machine

    def __call__(self, msg):
        line = "%s [%s] %s" % (now_s(), self.machine, msg)
        print(line, flush=True)
        if self.path:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(line + "\n")


def orca_cli():
    for c in [os.environ.get("ORCA"), "orca-ide", os.path.expanduser("~/.local/bin/orca-ide"), "orca",
              "/Applications/Orca.app/Contents/Resources/bin/orca"]:
        if c and (shutil.which(c) or os.path.exists(c)):
            return shutil.which(c) or c
    return None


def list_worktrees():
    cli = orca_cli()
    if not cli:
        return None, "找不到 orca CLI"
    try:
        p = subprocess.run([cli, "worktree", "list", "--json", "--limit", "1000"],
                           capture_output=True, text=True, timeout=60)
        r = json.loads(p.stdout)["result"]
    except Exception as e:
        return None, "orca worktree list 失败: %s" % type(e).__name__
    return [w for w in r["worktrees"] if w.get("hostId") == "local" and not w.get("isBare")], None


def git(path, *args):
    p = subprocess.run(["git", "-C", path] + list(args), capture_output=True, text=True, env=GIT_ENV, timeout=60)
    return p.returncode, p.stdout


def bot_for(path):
    rc, url = git(path, "remote", "get-url", "origin")
    url = url.strip() if rc == 0 else ""
    for key, bot in BOTS:
        if key in url:
            return bot, url
    return "coding-assistant", url or "(没有 origin)"


def scan_one(path):
    """返回这个工作区的发现列表 [(kind, 指纹, 说明)]。"""
    found = []
    rc, head = git(path, "rev-parse", "HEAD")
    if rc != 0:
        return found  # 还没有提交的空仓库
    head = head.strip()
    _, branch = git(path, "rev-parse", "--abbrev-ref", "HEAD")
    branch = branch.strip()
    rc, out = git(path, "rev-list", "--format=%H %ct", "--no-commit-header", "HEAD", "--not", "--remotes")
    commits = [l.split() for l in out.splitlines() if l.strip()] if rc == 0 else []
    if commits:
        first_sha, first_ct = commits[-1][0], int(commits[-1][1])  # 最早一个没推送的提交
        age = time.time() - first_ct
        if age >= DIRTY_AGE:  # 2 小时内的新提交不报，正在干活的 agent 常常过一会儿才推
            _, up = git(path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
            up = up.strip() or "没有上游分支"
            _, subj = git(path, "log", "-1", "--format=%h %s", "HEAD")
            # 指纹用最早那个没推送的提交：接着往上加提交不算「变了」，推上去一部分才算
            found.append(("unpushed", first_sha, "分支 %s 有 %d 个提交不在任何远程分支里，最早一个 %.1f 小时前（上游：%s；HEAD %s）" % (
                branch, len(commits), age / 3600, up, subj.strip()[:80])))
    rc, out = git(path, "status", "--porcelain=v1", "-z", "--untracked-files=normal")
    if rc == 0 and out:
        entries, oldest, now = [], None, time.time()
        parts = out.split("\0")
        i = 0
        while i < len(parts):
            e = parts[i]
            i += 1
            if not e:
                continue
            st, name = e[:2], e[3:]
            if st[0] in "RC":
                i += 1  # 改名的原路径
            if st == "??" and name.rstrip("/").split("/")[-1] == "node_modules":
                continue  # 指向共享依赖的 node_modules 软链接：gitignore 的 node_modules/ 匹配不到软链接，不算改动
            entries.append(st + " " + name)
            try:
                m = os.lstat(os.path.join(path, name)).st_mtime
                oldest = m if oldest is None else min(oldest, m)
            except OSError:
                pass  # 删掉的文件没有 mtime
        if oldest is not None and now - oldest >= DIRTY_AGE:
            fp = hashlib.sha1((head + "\n" + "\n".join(sorted(entries))).encode()).hexdigest()
            found.append(("dirty", fp, "%d 处未提交的改动，最早一处 %.1f 小时前（例：%s）" % (
                len(entries), (now - oldest) / 3600, "；".join(entries[:3])[:160])))
    return found


def wake(bot, title, body, log):
    try:
        p = subprocess.run([NOTIFY_RUN, "--bot", bot, "--no-tty", "--task", title, "--",
                            "sh", "-c", 'printf "%s\\n" "$1"', "sh", body],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=180)
        res = ((p.stderr or "").strip().splitlines() or ["rc=%s" % p.returncode])[-1]
    except Exception as e:
        res = "notify-run 调用失败: %s" % type(e).__name__
    log("叫醒 %s：%s" % (bot, res))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--machine", default=os.environ.get("UNPUSHED_MACHINE") or socket.gethostname().split(".")[0])
    ap.add_argument("--log", default=None)
    ap.add_argument("--state", default=os.path.expanduser("~/.orca-state/unpushed-scan/state.json"))
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--drill", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="只列发现，不叫醒、不改状态")
    args = ap.parse_args()
    log = Log(args.log, args.machine)

    wts, err = list_worktrees()
    if wts is None:
        log("拿不到工作区列表：%s，这次没扫" % err)
        return 2
    ignored = {os.path.expanduser(p) for m, p in IGNORE if m == args.machine}
    wts = [w for w in wts if w["path"].rstrip("/") not in ignored]
    if args.only:
        wts = [w for w in wts if any(w["path"].startswith(p) for p in args.only)]
    try:
        state = json.load(open(args.state))
    except Exception:
        state = {}
    now = int(time.time())
    seen, per_bot, n_found, skipped = set(), {}, 0, 0
    # 每个工作区上次叫醒（含改叫 coding-assistant）的时间，取这次运行之前的值：同一次运行里两种发现一起叫
    # 另记在 state["_paths"]：发现消失后又冒出来，4 小时内也不再叫
    paths = {p: t for p, t in (state.pop("_paths", None) or {}).items() if now - t < REWAKE}
    path_last = dict(paths)
    for k, v in state.items():
        pth = k.rsplit("::", 1)[0]
        path_last[pth] = max(path_last.get(pth, 0), v.get("last", 0), v.get("esc", 0))
    for w in wts:
        path = w["path"]
        if not os.path.isdir(path):
            skipped += 1
            continue
        try:
            found = scan_one(path)
        except Exception as e:
            log("%s 扫描出错：%s" % (path, type(e).__name__))
            continue
        if not found:
            continue
        bot, url = bot_for(path)
        for kind, fp, desc in found:
            n_found += 1
            key = path + "::" + kind
            seen.add(key)
            st = state.get(key)
            if not st:
                st = {"fp": fp, "wakes": 0, "last": 0, "esc": 0, "first": now}
            elif st.get("fp") != fp:
                st = dict(st, fp=fp, wakes=min(st.get("wakes", 0), 1))  # 内容变了：重新数，计时不变
            target = None
            quiet = now - path_last.get(path, 0) >= REWAKE  # 这个工作区 4 小时内没叫过
            if quiet and st["wakes"] < 2:
                target = bot
            elif quiet and st["wakes"] >= 2 and now - st["esc"] >= ESCALATE_EVERY:
                target = "coding-assistant"
            line = "%s %s [%s → %s] %s" % (kind, path, w.get("displayName") or "", bot, desc)
            if target:
                note = "" if target == bot else "（已叫 %s %d 次没变，改叫 coding-assistant）" % (bot, st["wakes"])
                per_bot.setdefault(target, []).append(line + note)
                if target == bot:
                    st["wakes"] += 1
                    st["last"] = now
                else:
                    st["esc"] = now
                paths[path] = now
                log("发现 %s；本次叫 %s" % (line, target))
            else:
                log("发现 %s；已叫 %d 次，这个工作区上次叫醒在 %.1f 小时前，还没到再叫的时间，这次不叫" % (
                    line, st["wakes"], (now - path_last.get(path, 0)) / 3600))
            state[key] = st
    for key in list(state):
        if key not in seen and (not args.only or any(key.startswith(p) for p in args.only)):
            log("已解决：%s" % key)
            del state[key]
    for bot, lines in sorted(per_bot.items()):
        title = "%sops · 24 未推送扫描（%s）：%d 个工作区有没推送的提交或放了 2 小时以上的改动" % (
            "【演练】" if args.drill else "", args.machine, len(lines))
        body = "\n".join(lines[:25]) + ("\n……另有 %d 条，见日志" % (len(lines) - 25) if len(lines) > 25 else "") + \
            "\n只读扫描，没碰仓库。日志 /workspace/ops/reports/unpushed-scan-YYYYMMDD.log"
        if args.dry_run:
            log("（dry-run）会叫 %s：%d 条" % (bot, len(lines)))
        elif FORCE_BOT:
            wake(FORCE_BOT, title, "（演练：原本叫 %s）\n" % bot + body, log)
        else:
            wake(bot, title, body, log)
    state["_paths"] = paths
    if not args.dry_run:
        os.makedirs(os.path.dirname(args.state), exist_ok=True)
        json.dump(state, open(args.state + ".tmp", "w"), ensure_ascii=False, indent=1)
        os.replace(args.state + ".tmp", args.state)
    log("完成：扫了 %d 个工作区（%d 个路径不存在跳过），%d 条发现，叫醒 %s" % (
        len(wts), skipped, n_found, ", ".join("%s×%d" % (b, len(l)) for b, l in sorted(per_bot.items())) or "无"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
