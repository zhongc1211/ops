#!/usr/bin/env python3
"""只读：三台机器上的全部真实工作区（orca worktree list）过一遍卡住检查的 drill_reason，看哪些会被当成演练跳过。
另列一列「名字里带 drill/演练」，对照只按名字认会藏掉哪些。

  stuck-check-drill-table.py [stuck-check.sh] > route-skip-table.txt
退出码：判成演练的有 0 个 → 0，否则 1（逐个看是不是真演练）。"""
import json, os, re, subprocess, sys

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../scripts/stuck-check.sh")
body = open(src, encoding="utf-8").read().split("<<'PYEOF'\n", 1)[1].rsplit("\nPYEOF", 1)[0]
body = body.split("\n_lock = None\n", 1)[0]  # 只要定义，不跑 main
sys.argv = ["stuck-check", "--dry-run"]
g = {"__name__": "drill_table"}
exec(compile(body, src, "exec"), g)
NAME_RE = re.compile(r"drill|演练", re.I)

hosts = [("iMac", None), ("box", g["box_env_name"]()), ("MBA", g["mba_env_name"]())]
total = drills = 0
for label, env in hosts:
    cmd = ["orca", "worktree", "list", "--json"] + (["--environment", env] if env else [])
    if label != "iMac" and not env:
        print("%s\t没跑\t没有配好的 Orca environment" % label)
        continue
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        d = json.loads(r.stdout)
    except Exception as e:  # noqa: BLE001
        print("%s\t没跑\t%s 失败：%s" % (label, " ".join(cmd), str(e)[:160]))
        continue
    wts = (d.get("result") or d).get("worktrees") or []
    print("# %s（%s）：%d 个工作区" % (label, " ".join(cmd), len(wts)))
    for w in wts:
        why = g["drill_reason"](w, env is None)
        named = bool(NAME_RE.search("%s %s" % (w.get("path") or "", w.get("displayName") or "")))
        total += 1
        drills += bool(why)
        print("%s\t%s\t%s\t%s\t%s" % (label, "演练（%s）" % why if why else "照常检查", "名字带drill" if named else "-",
                                      w.get("path"), w.get("displayName") or ""))
print("# 合计 %d 个工作区，判成演练 %d 个" % (total, drills))
sys.exit(0 if drills == 0 else 1)
