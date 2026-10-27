# compare_audit.py <audit-raw-dir> <host>=<worktrees.tsv> ...: match the dry-run rows with the 10-21 audit, row by row (by path).
# Audit = box /workspace/ops/reports/worktree-cleanup-audit-1021/raw/ (worktrees-classified.json, ignored-<host>.json,
# safe-summary.json, git-worktrees-not-in-orca.json), taken 10-21 01:07 SGT.
# Expected result from the audit, translated to the new rules:
#   directory gone -> RM (D6); main / bare -> SKIP; audit "safe" -> BACKUP_RM if it had any non-cache ignored file, else RM;
#   audit HOLD (4b-3) -> SKIP; ops-project worktree whose only blocker was "resident" -> RM / BACKUP_RM (4c); everything else -> SKIP.
# A row whose result differs from that goes into one of three groups:
#   2 state changed since the audit (status / dirty / unpushed / lastActivityAt / terminals differ, or the row is only on one side);
#   1 expected from the new rules (Linear now checked, every PR on the branch checked, backup list = D4 instead of "any ignored");
#   3 anything else (needs a look).
import csv, datetime, json, os, sys

raw = sys.argv[1]
audit = json.load(open(os.path.join(raw, "worktrees-classified.json")))
hold = {(h, n) for h, n, _ in json.load(open(os.path.join(raw, "safe-summary.json")))["HOLD"]}
gitonly = json.load(open(os.path.join(raw, "git-worktrees-not-in-orca.json")))
AUDIT_AT = datetime.datetime(2026, 10, 21, 1, 7, tzinfo=datetime.timezone(datetime.timedelta(hours=8)))
RES = "规则不覆盖：常驻（ops 项目/主工作区）"

def expected(a, ign):
    if not a["exists"]: return "RM", "目录已删（D6 改成直接 rm）"
    if a["main"] or a["archived"]: return "SKIP", a["primary"]
    if (a["host"], a["name"]) in hold: return "SKIP", "4b-3 先别动"
    nc = (ign.get(a["path"]) or {}).get("noncache_ignored") or []
    others = [b for b in a["blockers"] if b != RES]
    if a["safe"] or (RES in a["blockers"] and not others):
        return ("BACKUP_RM" if nc else "RM"), ("4c " if RES in a["blockers"] else "") + ("4b-2" if nc else "4b-1")
    return "SKIP", "；".join(a["blockers"])

def to_ms(s):
    if not s or s == "0": return 0
    return datetime.datetime.strptime(s, "%Y-%m-%d %H:%M").replace(tzinfo=datetime.timezone(datetime.timedelta(hours=8))).timestamp()

out, totals = [], {}
for arg in sys.argv[2:]:
    host, tsv = arg.split("=", 1)
    ours = {r["path"]: r for r in csv.DictReader(open(tsv), delimiter="\t")}
    ign = json.load(open(os.path.join(raw, "ignored-%s.json" % host)))
    aud = {a["path"]: a for a in audit if a["host"] == host}
    groups = {1: [], 2: [], 3: []}
    same = 0
    for p in sorted(set(ours) | set(aud)):
        o, a = ours.get(p), aud.get(p)
        if o and o["rule"] == "W16":
            known = any(g["host"] == host and g["path"] == p for g in gitonly)
            if known: same += 1
            else: groups[2].append((p, "W16 新出现的 git-only worktree（审计里没有）", o["verdict"], "-"))
            continue
        if not o: groups[2].append((p, "审计里有，现在 Orca 里没有了（已删）", "-", expected(a, ign)[0])); continue
        if not a: groups[2].append((p, "审计（01:07）之后新建的工作区", o["verdict"], "-")); continue
        exp, why = expected(a, ign)
        if o["verdict"] == exp: same += 1; continue
        drift = []
        if (o["status"] or "") != (a["status"] or ""): drift.append("状态 %s → %s" % (a["status"], o["status"]))
        if o["dirty"] not in ("", str(a["dirty"])): drift.append("未提交 %s → %s" % (a["dirty"], o["dirty"]))
        if o["unpushed"] not in ("", str(a["unpushed"])): drift.append("未推送 %s → %s" % (a["unpushed"], o["unpushed"]))
        la = (a["last_activity"] or 0) / 1000
        if la and abs(to_ms(o["last_activity"]) - la) > 120: drift.append("最后活动 %s → %s" % (
            datetime.datetime.fromtimestamp(la, AUDIT_AT.tzinfo).strftime("%m-%d %H:%M"), o["last_activity"][5:]))
        if o["rule"] in ("W5", "W6") and not a["terms"] and not a["agents"]: drift.append("审计时没有终端，现在有")
        label = "%s %s（%s）" % (o["verdict"], o["rule"], o["reason"])
        if drift:
            groups[2].append((p, "；".join(drift), label, "%s（%s）" % (exp, why))); continue
        rule_change = {"W10": "Linear 现在会查（审计没查）",
                       "W9": "现在查分支上的所有 PR + linkedPR（审计只取了一个 PR）",
                       "W4": "目录已删的记录直接 rm（D6）"}.get(o["rule"])
        if o["verdict"] == "RM" and exp == "BACKUP_RM":
            nc = [f for f, _ in (ign.get(p) or {}).get("noncache_ignored") or []]
            rule_change = "备份清单按 D4，不是「任何非缓存的忽略文件」；rm 会删掉：" + "、".join(nc[:6])
        if o["verdict"] in ("RM", "BACKUP_RM") and exp == "SKIP" and o["linear"].endswith((" completed", " canceled", " duplicate")) \
           and (o["status"] or "").lower() != "completed" and "MERGED" not in o["pr"] and "CLOSED" not in o["pr"]:
            rule_change = "做完的证据只有 Linear 已关（%s），审计没查 Linear" % o["linear"]
        if o["verdict"] == "BACKUP_RM" and exp == "RM": rule_change = "D4 的清单比审计的缓存口径多认出了要备份的：" + o["backup"]
        if rule_change: groups[1].append((p, rule_change, label, "%s（%s）" % (exp, why)))
        else: groups[3].append((p, "", label, "%s（%s）" % (exp, why)))
    totals[host] = (same, {k: len(v) for k, v in groups.items()})
    out.append("### %s：一致 %d 条；不一致 %d 条（新规则带来的 %d，审计后状态变了 %d，要查的 %d）" % (
        host, same, sum(len(v) for v in groups.values()), len(groups[1]), len(groups[2]), len(groups[3])))
    for k, title in ((1, "新规则带来的预期变化"), (2, "审计（01:07）之后状态变了"), (3, "真不一致，要查原因")):
        out += ["", "**%s（%d）**" % (title, len(groups[k])), ""]
        if not groups[k]: out.append("无"); continue
        out += ["| 路径 | 说明 | dry-run | 按审计推出的 |", "|---|---|---|---|"]
        for p, why, mine, exp in groups[k]:
            out.append("| `%s` | %s | %s | %s |" % (p.replace(os.path.expanduser("~"), "~"), why, mine, exp))
    out.append("")
# 审计里 git-only、现在已经没有的
for g in gitonly:
    h = {"iMac": "iMac", "MBA": "MBA"}.get(g["host"])
    if h and any(a.split("=")[0] == h for a in sys.argv[2:]):
        tsv = dict(a.split("=", 1) for a in sys.argv[2:])[h]
        if not any(r["path"] == g["path"] for r in csv.DictReader(open(tsv), delimiter="\t")):
            out.append("- %s：审计里的 git-only worktree `%s` 现在已经不在了（归到「状态变了」，不在上面的条数里）" % (h, g["path"]))
print("\n".join(out))
