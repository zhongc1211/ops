#!/usr/bin/env python3
"""unpushed_scan.py — ops · 24 未推送扫描（box 和 iMac 各跑一份，每小时，各扫本机的 Orca 工作区）。

对本机 `orca worktree list` 里的每个工作区（只读，GIT_OPTIONAL_LOCKS=0，不 fetch、不提交、不推、不 stash、不 reset）：
  unpushed — HEAD 上有不在任何远程分支里的提交（git rev-list HEAD --not --remotes），最早的一个超过 2 小时
  dirty    — 有未提交的改动（含未跟踪文件，不含未跟踪的 node_modules 软链接），其中最早的一处改动超过 2 小时
发现了就用 notify-run 叫醒该项目的 bot（按 git remote 认项目），同一个 bot 一次运行只叫一次，消息里列出全部发现。
限流（状态在 ~/.orca-state/unpushed-scan/state.json）：
  - 新发现、或内容变了（最早没推送的提交 / HEAD 加改动列表不同）：马上叫项目 bot，计数从 1 开始；
  - 没变：距上次叫醒满 4 小时才再叫项目 bot；已经叫过 2 次还没变，第 3 次改叫 coding-assistant，之后每 24 小时最多再叫它一次；
  - 发现消失了就删掉它的记录。
日志一行一条打印到 stdout，并追加到 --log（box 上就是 /workspace/ops/reports/unpushed-scan-YYYYMMDD.log；
iMac 上是本机镜像，由 unpushed-scan.sh 再经 ssh 追加到 box 的同一个文件）。
演练：--only <路径前缀> 只扫这些工作区，--state 用单独的状态文件，--drill 让叫醒标题带「【演练】」。
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
    if args.only:
        wts = [w for w in wts if any(w["path"].startswith(p) for p in args.only)]
    try:
        state = json.load(open(args.state))
    except Exception:
        state = {}
    now = int(time.time())
    seen, per_bot, n_found, skipped = set(), {}, 0, 0
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
            if not st or st.get("fp") != fp:
                st = {"fp": fp, "wakes": 0, "last": 0, "esc": 0, "first": now}
            target = None
            if st["wakes"] == 0 or (st["wakes"] < 2 and now - st["last"] >= REWAKE):
                target = bot
            elif st["wakes"] >= 2 and now - st["last"] >= REWAKE and now - st["esc"] >= ESCALATE_EVERY:
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
                log("发现 %s；本次叫 %s" % (line, target))
            else:
                log("发现 %s；已叫 %d 次，还没到再叫的时间，这次不叫" % (line, st["wakes"]))
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
        else:
            wake(bot, title, body, log)
    if not args.dry_run:
        os.makedirs(os.path.dirname(args.state), exist_ok=True)
        json.dump(state, open(args.state + ".tmp", "w"), ensure_ascii=False, indent=1)
        os.replace(args.state + ".tmp", args.state)
    log("完成：扫了 %d 个工作区（%d 个路径不存在跳过），%d 条发现，叫醒 %s" % (
        len(wts), skipped, n_found, ", ".join("%s×%d" % (b, len(l)) for b, l in sorted(per_bot.items())) or "无"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
