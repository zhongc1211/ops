#!/usr/bin/env python3
# R3 dry-run vs the R2 dry-run (d1602db, 07:59), by worktree id; drill repo (ws-cleanup-drill) counted apart from real workspaces.
import csv, sys
from collections import Counter
DRILL = "aa123560-8996-445e-9798-58252049e7e5"
def load(p): return {(r["id"] or r["path"]): r for r in csv.DictReader(open(p), delimiter="\t")}
def drill(r): return r["id"].startswith(DRILL) or "/ops-drill/" in r["path"]
r1, r2 = load(sys.argv[1]), load(sys.argv[2])
for name, keep in (("真实工作区", lambda r: not drill(r)), ("演练仓库", drill)):
    a = {k: v for k, v in r1.items() if keep(v)}; b = {k: v for k, v in r2.items() if keep(v)}
    ca, cb = Counter(v["verdict"] for v in a.values()), Counter(v["verdict"] for v in b.values())
    print("## %s：R2 %d 行，R3 %d 行" % (name, len(a), len(b)))
    print("| 结论 | R2 | R3 | 差 |\n|---|---|---|---|")
    for k in ("RM", "BACKUP_RM", "SKIP", "LIST"): print("| %s | %d | %d | %+d |" % (k, ca[k], cb[k], cb[k] - ca[k]))
    print("\n逐行有变化的：")
    for k in sorted(set(a) | set(b)):
        x, y = a.get(k), b.get(k)
        if x and y and (x["verdict"], x["rule"]) == (y["verdict"], y["rule"]): continue
        row = y or x
        print("- %s %s：%s → %s" % (row["repo"], row["path"].rsplit("/", 1)[-1],
              "%s %s" % (x["verdict"], x["rule"]) if x else "（R2 没有）",
              "%s %s（%s）" % (y["verdict"], y["rule"], y["reason"]) if y else "（R3 没有，run1 已删或已不在 Orca）"))
    print()
