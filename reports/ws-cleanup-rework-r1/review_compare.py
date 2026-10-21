# review_compare.py <REVIEW.md> <imac-run-dir> <mba-run-dir>: table of review section 4 vs this R1 dry-run, one row per item.
import csv, re, sys
rv, imac, mba = sys.argv[1:4]
text = open(rv).read()
sec = text[text.index("### 4a."):text.index("### 4b.")]
items = []
for line in sec.splitlines():
    m = re.match(r"\| (\d+) \| `([^`]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \|", line)
    if m: items.append(m.groups())
rows = list(csv.DictReader(open(imac + "/worktrees.tsv"), delimiter="\t"))
def find(p):
    p = p.replace("~/", "")
    hits = [r for r in rows if r["path"].endswith("/" + p) or r["path"].endswith(p)]
    return hits[0] if len(hits) == 1 else None
out = ["| # | 工作区 | 旧脚本 | 评审判断 | R1 结论 | R1 原因 |", "|---|---|---|---|---|---|"]
for n, p, old, st, judge in items:
    r = find(p)
    new = "%s %s" % (r["verdict"], r["rule"]) if r else "没找到"
    reason = (r["reason"] if r else "").replace("|", "/")
    if r and r["verdict"] == "BACKUP_RM": reason = "%s；备份 %s" % (reason, r["backup_size"])
    out.append("| %s | `%s` | %s | %s | %s | %s |" % (n, p, old.strip(), judge.strip(), new, reason[:120]))
print("\n".join(out))
print()
want = ["term_e7d55df8", "term_fda1fd63", "term_e34518f4", "term_053bc025", "term_759189b1", "term_4045de0c", "term_ee7c21a9"]
mt = list(csv.DictReader(open(mba + "/terminals.tsv"), delimiter="\t"))
it = list(csv.DictReader(open(imac + "/terminals.tsv"), delimiter="\t"))
out = ["| 终端 | 机器 | R1 结论 | R1 原因 |", "|---|---|---|---|"]
for h in want + ["term_16efda20", "term_bd5a15ec", "term_1de8accf", "term_5610c4cc"]:
    hits = [(m, t) for m, ts in (("iMac", it), ("MBA", mt)) for t in ts if t["handle"].startswith(h)]
    if not hits: out.append("| %s | — | 现在已不在 | 终端已关闭（不是本脚本关的，本轮没有关过任何终端） |" % h); continue
    m, t = hits[0]
    out.append("| %s | %s | %s %s | %s |" % (h, m, t["verdict"], t["rule"], t["reason"].replace("|", "/")[:110]))
print("\n".join(out))
