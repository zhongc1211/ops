#!/usr/bin/env python3
"""verify-ops 的小工具（verify.sh 调用；单独用时见各子命令的说明）。不连任何真实外部系统。

  vo.py freeport                         打印一个本机空闲端口
  vo.py count <jsonl> [k=v ...]          数假 webhook 记录里满足全部条件的条数；k 是 body 字段，
                                         另认 path / answered / auth_ok 三个记录级字段
  vo.py mask <src> <dst>                 复制文本并掩码：真实 HOME、主机名（VO_MASK_WORDS，冒号分隔）、IPv4 地址
  vo.py guard <dir> <log>                真实 webhook 目录每个文件的 sha256 前 8 位和字节数（不读内容以外的东西，
                                         不打印内容）+ log 的行数和其中 bot=verify- 开头的行数，输出一行 JSON
  vo.py stuck-fixture <dir> <pid1> <pid2>  写卡住检查用的假 Orca 夹具 orca.json 和假 agent-probe 的 probe.json
  vo.py probe                            假 agent-probe：输出 VO_PROBE_JSON 里的进程表（和 scripts/agent-probe 同样的框）
  vo.py orca <args...>                   假 orca：terminal wait 对名字含 idle 的终端回「停在输入框」，
                                         其余交给 wake/tests/fake_orca.py（VO_FAKE_ORCA_PY）
  vo.py linear <args...>                 假 orca 的 Linear 子命令（只认 issue / due-date set / save-issue），
                                         调用记到 VO_LINEAR_LOG
  vo.py summary <run_dir>                由 cases.tsv、features.tsv、meta.json 写 summary.json 和 report.md，
                                         打印 total pass fail skipped
"""
import base64, gzip, hashlib, json, os, re, socket, sys, time


def freeport():
    s = socket.socket()
    s.bind(("localhost", 0))
    print(s.getsockname()[1])
    s.close()


def count(path, conds):
    want = dict(c.split("=", 1) for c in conds)
    n = 0
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        lines = []
    for ln in lines:
        if not ln.strip():
            continue
        r = json.loads(ln)
        body = r.get("body") if isinstance(r.get("body"), dict) else {}
        ok = True
        for k, v in want.items():
            got = r.get(k) if k in ("path", "answered", "auth_ok") else body.get(k)
            if isinstance(got, bool):
                got = "true" if got else "false"
            if str(got) != v:
                ok = False
                break
        n += ok
    print(n)


def mask(src, dst):
    text = open(src, encoding="utf-8", errors="replace").read()
    home = os.environ.get("VO_REAL_HOME") or ""
    words = [w for w in (os.environ.get("VO_MASK_WORDS") or "").split(":") if len(w) >= 3]
    if home:
        text = text.replace(home, "~")
    for w in sorted(words, key=len, reverse=True):
        text = text.replace(w, "<host>")
    text = re.sub(r"(?<![\d.])\d{1,3}(?:\.\d{1,3}){3}(?![\d.])", "<ip>", text)
    open(dst, "w", encoding="utf-8").write(text)


def guard(d, log):
    files = {}
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if os.path.isfile(p):
                h = hashlib.sha256()
                with open(p, "rb") as f:
                    h.update(f.read())
                files[name] = {"sha8": h.hexdigest()[:8], "bytes": os.path.getsize(p)}
    lines = ours = 0
    if os.path.isfile(log):
        with open(log, encoding="utf-8", errors="replace") as f:
            for ln in f:
                lines += 1
                ours += "\tbot=verify-" in ln
    print(json.dumps({"webhooks": files, "notify_run_log_lines": lines, "notify_run_log_verify_lines": ours}))


def stuck_fixture(d, pid_idle, pid_silent):
    old = int((time.time() - 7200) * 1000)
    ws, terms = [], []

    def add(name, agents):
        p = "/fake/ws/" + name
        ws.append({"path": p, "workspaceKind": "git", "workspaceStatus": "in-progress", "displayName": name,
                   "repo": "demo", "repoId": "r1", "branch": name, "lastActivityAt": old, "lastOutputAt": old,
                   "liveTerminalCount": 1, "agents": agents})
        terms.append({"handle": "term-" + name, "worktreePath": p, "connected": True, "lastOutputAt": old,
                      "tabId": "tab-" + name, "leafId": "l1"})

    add("verify-gone", [])
    add("verify-idle", [{"state": "done", "stateStartedAt": old, "updatedAt": old}])
    add("verify-silent", [{"state": "working", "stateStartedAt": old, "updatedAt": old}])
    json.dump({"iMac": {"worktrees": ws, "terminals": terms}, "box": {"worktrees": [], "terminals": []}},
              open(os.path.join(d, "orca.json"), "w"), indent=1)
    procs = [{"kind": "agent", "pid": int(pid_idle), "cwd": "/fake/ws/verify-idle", "stat": "S", "args_head": "claude"},
             {"kind": "agent", "pid": int(pid_silent), "cwd": "/fake/ws/verify-silent", "stat": "S", "args_head": "claude"}]
    json.dump({"procs": procs}, open(os.path.join(d, "probe.json"), "w"), indent=1)


def probe():
    procs = json.load(open(os.environ["VO_PROBE_JSON"], encoding="utf-8"))["procs"]
    doc = {"ts": time.time(), "procs": procs, "stops": [], "wake": {"sessions": [], "nr": []}}
    print("@@PROBE-BEGIN")
    print(base64.b64encode(gzip.compress(json.dumps(doc).encode())).decode())
    print("@@PROBE-END")


def orca(args):
    if args[:2] == ["terminal", "wait"] and "--terminal" in args and "idle" in args[args.index("--terminal") + 1]:
        print(json.dumps({"ok": True, "result": {"wait": {"satisfied": True}}}))
        return
    py = os.environ["VO_FAKE_ORCA_PY"]
    os.execv(sys.executable, [sys.executable, py] + args)


def linear(args):
    with open(os.environ["VO_LINEAR_LOG"], "a", encoding="utf-8") as f:
        f.write(json.dumps(args, ensure_ascii=False) + "\n")
    a = [x for x in args if x != "--json"]
    if a[:2] == ["linear", "issue"]:
        res = {"issue": {"identifier": a[2], "description": "verify-ops 假卡片"}}
    elif a[:3] == ["linear", "due-date", "set"] or a[:2] == ["linear", "save-issue"]:
        res = {}
    else:
        print(json.dumps({"ok": False, "error": {"code": "unknown_command", "message": " ".join(a)}}))
        sys.exit(1)
    print(json.dumps({"ok": True, "result": res}))


def summary(run):
    meta = json.load(open(os.path.join(run, "meta.json"), encoding="utf-8"))
    cases = []
    if os.path.exists(os.path.join(run, "cases.tsv")):
        for ln in open(os.path.join(run, "cases.tsv"), encoding="utf-8"):
            f = ln.rstrip("\n").split("\t")
            if len(f) == 4:
                cases.append({"feature": f[0], "status": f[1], "name": f[2], "detail": f[3]})
    feats = []
    if os.path.exists(os.path.join(run, "features.tsv")):
        for ln in open(os.path.join(run, "features.tsv"), encoding="utf-8"):
            f = ln.rstrip("\n").split("\t")
            if len(f) == 3:
                mine = [c for c in cases if c["feature"] == f[0]]
                feats.append({"name": f[0], "command": f[1], "exit_code": int(f[2]), "cases": len(mine),
                              "pass": sum(c["status"] == "pass" for c in mine),
                              "fail": sum(c["status"] == "fail" for c in mine),
                              "skipped": sum(c["status"] == "skipped" for c in mine), "log": "features/%s.log" % f[0]})
    tot = {k: sum(c["status"] == k for c in cases) for k in ("pass", "fail", "skipped")}
    total = len(cases)
    guard_ok = meta.get("guard_ok", True)
    status = "EMPTY" if tot["pass"] + tot["fail"] == 0 else ("FAIL" if tot["fail"] or not guard_ok else "PASS")
    out = dict(meta)
    out.update({"status": status, "cases_total": total, "cases_pass": tot["pass"], "cases_fail": tot["fail"],
                "cases_skipped": tot["skipped"], "features": feats, "cases": cases})
    json.dump(out, open(os.path.join(run, "summary.json"), "w"), indent=1, ensure_ascii=False)
    L = ["# verify-ops 运行报告", "",
         "- 结果：**%s**（用例 %d：通过 %d，失败 %d，skipped %d）" % (status, total, tot["pass"], tot["fail"], tot["skipped"]),
         "- commit：%s（dirty=%s）；被测目录：%s" % (meta.get("sha"), meta.get("dirty"), meta.get("sut_kind")),
         "- 机器：%s；bash：%s" % (meta.get("machine"), meta.get("bash")),
         "- 真实 HOME 守卫（webhook 目录 sha256/字节数、notify-run.log 里 verify- 行）：%s" % ("一致" if guard_ok else "**变了**"),
         "", "| feature | 命令 | 退出码 | 用例 | 通过 | 失败 | skipped |", "|---|---|---|---|---|---|---|"]
    for f in feats:
        L.append("| %s | `%s` | %d | %d | %d | %d | %d |" % (f["name"], f["command"], f["exit_code"], f["cases"],
                                                         f["pass"], f["fail"], f["skipped"]))
    L += ["", "## 用例", ""]
    for c in cases:
        L.append("- [%s] %s / %s%s" % (c["status"], c["feature"], c["name"], ("：" + c["detail"]) if c["detail"] else ""))
    L += ["", "## 按规矩不跑（skipped，不算通过）", ""]
    for s in meta.get("skipped_by_policy", []):
        L.append("- %s：%s" % (s["what"], s["why"]))
    L += ["", "## 替身（只替外部边界）", ""]
    for s in meta.get("stand_ins", []):
        L.append("- %s" % s)
    open(os.path.join(run, "report.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(total, tot["pass"], tot["fail"], tot["skipped"], status)


if __name__ == "__main__":
    cmd, rest = sys.argv[1], sys.argv[2:]
    if cmd == "freeport":
        freeport()
    elif cmd == "count":
        count(rest[0], rest[1:])
    elif cmd == "mask":
        mask(rest[0], rest[1])
    elif cmd == "guard":
        guard(rest[0], rest[1])
    elif cmd == "stuck-fixture":
        stuck_fixture(*rest[:3])
    elif cmd == "probe":
        probe()
    elif cmd == "orca":
        orca(rest)
    elif cmd == "linear":
        linear(rest)
    elif cmd == "summary":
        summary(rest[0])
    else:
        sys.exit("vo.py: 不认识的子命令 %s" % cmd)
