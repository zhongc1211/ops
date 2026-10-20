# drill_proof.py <drill-out-dir> <drill repo id>: before/after the drill, everything outside the drill repo is unchanged.
# Reads the snap.sh snapshots (before-*/after-*). Prints markdown; never prints terminal previews or agent text (only field names).
import json, os, sys
d, rid = sys.argv[1:3]
load = lambda n: json.load(open(os.path.join(d, n)))["result"]
out = []
for k, key, idf in (("wt.json", "worktrees", "id"), ("wps.json", "worktrees", "worktreeId"), ("term.json", "terminals", "handle")):
    a = {x[idf]: x for x in load("before-" + k)[key]}; b = {x[idf]: x for x in load("after-" + k)[key]}
    drill = lambda i, x: (x.get("repoId") == rid) or (x.get("worktreeId") or "").startswith(rid + "::") or i.startswith(rid + "::")
    na = {i for i in a if not drill(i, a[i])}; nb = {i for i in b if not drill(i, b[i])}
    da = {i for i in a if drill(i, a[i])}; db = {i for i in b if drill(i, b[i])}
    fields = {}
    for i in na & nb:
        for f in set(a[i]) | set(b[i]):
            if a[i].get(f) != b[i].get(f): fields[f] = fields.get(f, 0) + 1
    out.append("**%s %s**：演练仓库外 before %d / after %d，只在 before 里 %d，只在 after 里 %d；演练仓库 before %d / after %d。"
               % (k, key, len(na), len(nb), len(na - nb), len(nb - na), len(da), len(db)))
    for i in sorted(na - nb): out.append("- 只在 before：`%s`" % i)
    for i in sorted(nb - na): out.append("- 只在 after：`%s`（%s）" % (i, (b[i].get("worktreeId") or "")[-60:]))
    out.append("- 演练仓库外变过的字段（条数）：%s" % ("、".join("`%s` %d" % kv for kv in sorted(fields.items(), key=lambda kv: -kv[1])) or "无"))
    out.append("")
def sections(n):
    s, cur = {}, None
    for line in open(os.path.join(d, n)):
        if line.startswith("== "): cur = line[3:].strip(); s[cur] = []
        elif cur: s[cur].append(line)
    return s
ga, gb = sections("before-git.txt"), sections("after-git.txt")
same = [m for m in ga if m in gb and ga[m] == gb[m]]
diff = [m for m in set(ga) | set(gb) if ga.get(m) != gb.get(m)]
out.append("**git worktree list --porcelain**：%d 个主仓库，%d 个前后一样；不一样的：%s" % (len(set(ga) | set(gb)), len(same), "、".join("`%s`" % m for m in sorted(diff)) or "无"))
print("\n".join(out))
