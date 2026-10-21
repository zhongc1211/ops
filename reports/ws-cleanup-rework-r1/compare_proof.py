# compare_proof.py (R1: adds orca worktree ps) <snap-dir> <run1-dir> <run2-dir>: read-only proof for one machine.
# 1) before/after snapshots (orca worktree list, orca terminal list, git worktree list): raw byte equality, then every field
#    that changed, per entity, so each change can be attributed (Orca's own sortOrder re-ranking, other agents' sessions).
# 2) run1 vs run2 TSVs with the time-derived columns (idle_h, procs) dropped.
# Prints markdown; never prints terminal previews (only the names of changed fields).
import csv, json, os, sys

snap, r1, r2 = sys.argv[1:4]
out = []
def raw_same(a, b): return open(a, "rb").read() == open(b, "rb").read()
def load(n): return json.load(open(os.path.join(snap, n)))["result"]
out.append("| 快照 | 字节完全一样 |")
out.append("|---|---|")
for k in ("wt.json", "term.json", "wps.json", "git.txt"):
    out.append("| %s | %s |" % (k, "是" if raw_same(os.path.join(snap, "before-" + k), os.path.join(snap, "after-" + k)) else "否"))
out.append("")
for k in ("wt.json", "term.json", "wps.json"):
    a, b = (json.load(open(os.path.join(snap, p + k))) for p in ("before-", "after-"))
    top = sorted(f for f in set(a) | set(b) if f != "result" and a.get(f) != b.get(f))
    out.append("%s 在 result 之外不同的字段：%s" % (k, "、".join("`%s`" % f for f in top) or "无"))
self_term = os.environ.get("ORCA_TERMINAL_HANDLE")
if self_term: out.append("本任务自己的终端：`%s`" % self_term)
out.append("")
for k, key, idf, namef in (("wt.json", "worktrees", "id", "displayName"), ("wps.json", "worktrees", "worktreeId", "displayName"), ("term.json", "terminals", "handle", "title")):
    a = {x[idf]: x for x in load("before-" + k)[key]}
    b = {x[idf]: x for x in load("after-" + k)[key]}
    gone, new = sorted(set(a) - set(b)), sorted(set(b) - set(a))
    fields = {}
    for i in sorted(set(a) & set(b)):
        ch = tuple(sorted(f for f in set(a[i]) | set(b[i]) if a[i].get(f) != b[i].get(f)))
        if ch: fields.setdefault(ch, []).append(i)
    out.append("**%s %s**：before %d 条、after %d 条；只在 before 里 %d 条，只在 after 里 %d 条。" % (k, key, len(a), len(b), len(gone), len(new)))
    for ch, ids in sorted(fields.items(), key=lambda kv: -len(kv[1])):
        names = [(a[i].get(namef) or i)[:40] + ("（`%s`）" % i if key == "terminals" else "") for i in ids]
        shown = "、".join(names) if len(names) <= 6 else "%d 条（全部只变了这些字段）" % len(names)
        out.append("- 变了 `%s`：%s" % (", ".join(ch), shown))
    out.append("")
ga, gb = open(os.path.join(snap, "before-git.txt")).read().splitlines(), open(os.path.join(snap, "after-git.txt")).read().splitlines()
diff = [(x, y) for x, y in zip(ga, gb) if x != y]
out.append("**git worktree list**：%d 行 / %d 行，不同的行：" % (len(ga), len(gb)))
for x, y in diff: out.append("- `%s` → `%s`" % (" ".join(x.split()[:2]), " ".join(y.split()[:2])))
out.append("")

def rows(d, f, drop):
    r = list(csv.reader(open(os.path.join(d, f)), delimiter="\t"))
    keep = [i for i, c in enumerate(r[0]) if c not in drop]
    return [[x[i] for i in keep] for x in r], [r[0][i] for i in keep]
for f, key in (("worktrees.tsv", 1), ("terminals.tsv", 1)):
    drop = ("idle_h", "procs")
    a, h = rows(r1, f, drop); b, _ = rows(r2, f, drop)
    am, bm = {x[key]: x for x in a[1:]}, {x[key]: x for x in b[1:]}
    ch = [k for k in sorted(set(am) | set(bm)) if am.get(k) != bm.get(k)]
    out.append("**%s**（去掉 %s 两列）：run1 %d 行、run2 %d 行，%s。" % (f, "、".join(drop), len(a) - 1, len(b) - 1,
               "完全一样" if not ch else "%d 行不同" % len(ch)))
    for k in ch:
        x, y = am.get(k), bm.get(k)
        if not x or not y: out.append("- `%s`：只在 %s 里" % (k, "run1" if x else "run2")); continue
        out.append("- `%s`：" % k + "；".join("%s `%s` → `%s`" % (h[i], x[i], y[i]) for i in range(len(h)) if x[i] != y[i]))
    out.append("")
print("\n".join(out))
