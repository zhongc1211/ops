#!/bin/bash
# B1 的回退测试：把本 PR 的代码换回 base，用本分支的演练整轮跑一次 wake/tests/heartbeat-watch-ssh.sh，看本 PR 会改变结果的
# 场景是不是真的挂了、本 PR 不改变结果的场景是不是照样过。期望先写在 automations/heartbeat-1021/FAILURE-MODES.md
# 「回退测试的期望」各节，下面的表照抄它们。在 iMac 的仓库根目录跑：
#   wake/tests/heartbeat-watch-ssh-rollback.sh [<base commit>]   默认 f828d452；产物写到 reports/heartbeat-mba-imac-1021-rollback-<base 前 7 位>/
#   HB_ROLLBACK_OUT=<目录>                                       产物换个目录（目录里有 .hb-drill 标记才清空重写）
# 旧代码怎么放回去：临时目录里 git clone --shared 本仓库，检出 base（没有 scripts/orca-via-ssh、scripts/lock-held-alert 和 register.sh，
# heartbeat-watch.sh 是 base 那份），放进 HEAD 的演练脚本、回放数据和一份现网版 defs.json：MBA 那条的 precheck 用现网 box 94e4b0bc 的原文
# （environment iMac，不经 ssh），5c2d0575 各阶段都用它的现网原文，都没有 lockf 和 lock-held-alert。演练的安全措施照旧：
# heartbeat-watch 都用临时状态目录，除 S12、S13 外都带 --dry-run、用假 webhook；S12、S13 不带 --dry-run，webhook 目录是空的。
# 锁文件都在临时目录。orca 只读。
# 第五轮新加的 7 项和第五轮补充新加的 6 项该挂的，还要在演练的「实际」一栏里对上挂的原因（WHY_RE），对不上算不一致。
# 退出码：0 每项都和期望一致；1 有不一致的；2 跑不起来。
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
if ! base=$(git -C "$root" rev-parse --verify -q "${1:-f828d452345f16898d6c9d133984e170d98d9f83}^{commit}"); then
    echo "heartbeat-watch-ssh-rollback.sh：找不到 commit ${1:-}" >&2
    exit 2
fi
head=$(git -C "$root" rev-parse HEAD)
OUT=${HB_ROLLBACK_OUT:-$root/reports/heartbeat-mba-imac-1021-rollback-${base:0:7}}
T=$(mktemp -d -t hb-rollback)
trap 'rm -rf "$T"' EXIT
tree=$T/tree

# 旧代码：base 的干净检出。git clone --shared 只读本仓库的对象，不改本仓库。
common=$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd)
git clone -q --no-checkout --shared "$common" "$tree" || exit 2
git -C "$tree" -c advice.detachedHead=false checkout -q --detach "$base" || exit 2
git -C "$tree" update-ref refs/remotes/origin/main "$base"  # 演练用 merge-base HEAD origin/main 找 base
# 本分支的测试：HEAD 里的演练脚本和回放数据（不取工作区里没提交的改动）
git -C "$root" archive "$head" wake/tests/heartbeat-watch-ssh.sh wake/tests/hb-replay | tar -x -C "$tree" || exit 2
git -C "$root" show "$head:automations/heartbeat-1021/defs.json" >"$T/defs-head.json" || exit 2
mkdir -p "$tree/automations/heartbeat-1021"
python3 -I - "$T/defs-head.json" "$tree/automations/heartbeat-1021/defs.json" <<'PY' || exit 2
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
box = d["box"]
for c in d["create"]:  # MBA 那条：现网 box 94e4b0bc 盯 iMac ops · 01 的原文（environment iMac，不经 ssh）
    c["precheck"], c["precheckTimeout"] = box["precheck"], box["precheckTimeout"]
live = next(e for e in d["edit"] if e["stage"] == "parallel")["before"]  # 5c2d0575 的现网原文
for e in d["edit"]:
    keys = ("precheck", "precheckTimeout") if e["stage"] == "parallel" else ("name", "precheck", "precheckTimeout")
    e["set"] = {k: live[k] for k in keys}
d["_doc"] = ("回退测试用的现网版 defs（wake/tests/heartbeat-watch-ssh-rollback.sh 生成）：create 的 precheck 是现网 box 94e4b0bc "
             "的原文，5c2d0575 各阶段的 set 都是它的现网原文。")
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, indent=1)
PY
{
    echo "旧代码：${base}（git clone --shared 后 checkout --detach）"
    echo "测试取自：${head}"
    for f in scripts/orca-via-ssh scripts/lock-held-alert automations/heartbeat-1021/register.sh scripts/heartbeat-watch.sh; do
        if [ -e "$tree/$f" ]; then echo "有 ${f}（sha256 $(shasum -a 256 "$tree/$f" | cut -c1-16)）"; else echo "没有 ${f}"; fi
    done
    echo "base 之外放进去的（git status --porcelain --untracked-files=all）："
    git -C "$tree" status --porcelain --untracked-files=all
} >"$T/tree.txt"
cat "$T/tree.txt"

HB_DRILL_OUT=$OUT HB_DRILL_NOTE="这是回退测试：代码是 base ${base:0:7}，演练脚本和回放数据取自 ${head:0:7}，defs 是现网版。和期望的对照见 ROLLBACK.md。" \
    /bin/bash "$tree/wake/tests/heartbeat-watch-ssh.sh" >"$T/drill.log" 2>&1
drc=$?
if [ $drc -gt 1 ] || [ ! -s "$OUT/results.tsv" ]; then
    echo "heartbeat-watch-ssh-rollback.sh：演练没跑起来（退出 ${drc}）：" >&2
    tail -20 "$T/drill.log" >&2
    exit 2
fi
mkdir -p "$OUT/rollback"
cp "$T/tree.txt" "$T/drill.log" "$OUT/rollback/"
cp "$tree/automations/heartbeat-1021/defs.json" "$OUT/rollback/defs-live.json"

python3 -I - "$OUT" "$base" "$head" <<'PY'
import json, os, re, sys
out, base, head = sys.argv[1:4]
# 照抄 automations/heartbeat-1021/FAILURE-MODES.md「回退测试的期望」「回退测试的期望（第二轮）」「回退测试的期望（第五轮）」
# 「回退测试的期望（第五轮补）」「回退测试的期望（第五轮补充）」：第六轮本 PR 会改变结果的 40 项该挂，其余 31 项照样过
FAIL = {}
for ids, why in (("S0.diff", "base 和「本分支」是同一份，没有第 7、13、33 行的改动"),
                 ("S2.sh S2.zsh", "现网版 precheck 在 MBA 上读不到 iMac ops · 01：MBA 的 Orca 没有 environment iMac"),
                 ("S4 S4b", "没有包装，heartbeat-watch 报的是 FileNotFoundError，不是 ssh 连不上的 JSONDecodeError"),
                 ("S4.wrapper S5.iMac S5.MBA S5b S7", "没有 scripts/orca-via-ssh"),
                 ("S6b.parallel S6b.final", "现网 5c2d0575 只有 box 目标，没有 MBA 目标"),
                 ("S8.mba S8.imac-noid S8.parallel S8.final S8.rollback S8.refuse", "没有 register.sh"),
                 ("S11", "orca-via-ssh、register.sh 不存在"),
                 ("S12", "现网版 precheck 不经 ssh：MBA 的 Orca 没有 environment iMac，几秒内就查不到（invalid_argument），ssh 替身一次都没起"),
                 ("S13", "现网版 precheck 没套 lockf：B 在 A 跑的期间照常跑完一轮（没超时、退出 1、调了 orca），B 前后状态目录不一样"),
                 ("S14.MBA.held S14.iMac.held", "现网版 precheck 没套 lockf：heartbeat-watch 照常起来，建出了那个不存在的目录，退出不是 75"),
                 ("S14.MBA.nodir S14.iMac.nodir", "现网版 precheck 没有锁文件这一步，照常跑，建出了那个不存在的目录，退出不是 73"),
                 ("S14.MBA.timeout S14.iMac.timeout",
                  "现网版 precheck 没套 lockf：第一轮还在跑的时候探锁，退出 0；替身起了至少 1 次；第一轮到 12 秒被杀"),
                 ("S15.MBA S15.iMac",
                  "现网版 precheck 没套 lockf 和 lock-held-alert：外部拿着的锁没人用，第 1 轮照常起 heartbeat-watch，退出不是 75，"
                  "状态目录被建出来；4 轮都没跳过，假 curl 0 次（没有告警，也没有恢复）"),
                 ("S15.MBA.45 S15.iMac.45", "现网版 precheck 没有 lock-held-alert：两轮都照常跑，退出不是 75，假 curl 0 次"),
                 ("S15.MBA.bad S15.iMac.bad", "现网版 precheck 没有 lock-held-alert：照常跑，退出不是 75")):
    for i in ids.split():
        FAIL[i] = why
PASS = ("S0.same S0.bot " + " ".join("S1.c%02d" % n for n in range(1, 15)) + " S1.curl S3 S6 S6b.box "
        "S9.5c2d0575 S9.94e4b0bc S9.439cd438 S9.mba S10.MBA S10.iMac S12.old "
        "S14.MBA.kill S14.MBA.term S14.MBA.crash S14.iMac.kill S14.iMac.term S14.iMac.crash").split()
for i, why in {"S0.bot": 'base 收件人仍是 coding-assistant',
               "S1.bot": '本分支这版是 base，ops-system 待发行数为 0',
               "S3": 'base 的待发告警发给 coding-assistant',
               **{i: '现网版没有 lockf 和 lock-held-alert，每轮照常跑，假 curl 0 次'
                  for i in ("S15.MBA.rf", "S15.iMac.rf", "S15.MBA.old", "S15.iMac.old")}}.items():
    FAIL[i] = why
PASS = [i for i in PASS if i not in FAIL]
assert len(FAIL) == 40 and len(PASS) == 31
# 第五轮新加的 7 项、第五轮补充新加的 6 项该挂的，挂的原因要在演练的「实际」一栏里对得上
# （FAILURE-MODES.md C15、「回退测试的期望（第五轮补）」「回退测试的期望（第五轮补充）」）
S15_RE = r"^第 1–4 轮退出 (?!75、)\d+、\d+、\d+、\d+（跳过 0 轮），[^；]*第 1 轮后状态目录有；.*；假 curl 每轮之后累计 [^；]*，共 0 次$"
WHY_RE = {"S13": r"；B：[^；]*（在 A 跑的期间），没超时，用时 [\d.]+ 秒，退出 1，.*，ssh \d+ 次、orca [1-9]\d* 次，状态目录前后不一样；C：",
          "S14.MBA.held": r"^退出 (?!75，)\d+，.*；目录有；", "S14.iMac.held": r"^退出 (?!75，)\d+，.*；目录有；",
          "S14.MBA.nodir": r"^退出 (?!73，)\d+，.*；目录有；", "S14.iMac.nodir": r"^退出 (?!73，)\d+，.*；目录有；",
          "S14.MBA.timeout": r"^探锁退出 0（[^）]*），探锁在第一轮开始后 [\d.]+–[\d.]+ 秒（第一轮还在跑）；第一轮超时被杀，用时 [\d.]+ 秒；替身起了 [1-9]\d* 次",
          "S14.iMac.timeout": r"^探锁退出 0（[^）]*），探锁在第一轮开始后 [\d.]+–[\d.]+ 秒（第一轮还在跑）；第一轮超时被杀，用时 [\d.]+ 秒；替身起了 [1-9]\d* 次",
          "S15.MBA": S15_RE, "S15.iMac": S15_RE,
          "S15.MBA.45": r"^44 分钟：退出 (?!75，)\d+，.*，假 curl 0 次；46 分钟：退出 (?!75，)\d+，.*，假 curl 0 次",
          "S15.iMac.45": r"^44 分钟：退出 (?!75，)\d+，.*，假 curl 0 次；46 分钟：退出 (?!75，)\d+，.*，假 curl 0 次",
          "S15.MBA.bad": r"^乱码：退出 (?!75，)\d+，.*；目录：退出 (?!75，)\d+，",
          "S15.iMac.bad": r"^乱码：退出 (?!75，)\d+，.*；目录：退出 (?!75，)\d+，"}
WHY_RE.update({"S0.bot": r'本分支 BOT = "coding-assistant"',
               "S1.bot": r'「将 POST 给 ops-system」0 行',
               "S3": r'dry-run，将 POST 给 coding-assistant',
               **{i: r'退出 (?!75，)\d+，.*；假 curl 每轮之后累计 [^；]*，共 0 次$'
                  for i in ("S15.MBA.rf", "S15.iMac.rf", "S15.MBA.old", "S15.iMac.old")}})
assert len(WHY_RE) == 20 and set(WHY_RE) <= set(FAIL)
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "results.tsv"), encoding="utf-8") if l.strip()]
got = {r[0]: r for r in rows}
# 该挂的每项从 raw/ 里取输出原文（前两行，去掉开头的时间戳）：演练的「实际」一栏只摘期望子串所在的那行，挂了常常是空的。
RAW = {"S0.diff": "S0/diff-base-new.txt", "S2.sh": "mba/S2-sh.out mba/S2-sh.err", "S2.zsh": "mba/S2-zsh.out mba/S2-zsh.err",
       "S4": "mba/S4.out mba/S4.err", "S4.wrapper": "mba/S4-wrapper.out mba/S4-wrapper.err", "S4b": "mba/S4b.out mba/S4b.err",
       "S5.iMac": "S5-imac/edit.err", "S5.MBA": "mba/S5/edit.out mba/S5/edit.err", "S5b": "mba/S5b.out mba/S5b.err",
       "S7": "mba/S7-runs.err", "S6b.parallel": "S6b/parallel.out S6b/parallel.err", "S6b.final": "S6b/final.out S6b/final.err",
       "S8.mba": "S8/mba.out S8/mba.err", "S8.imac-noid": "S8/imac.out S8/imac.err",
       "S8.parallel": "S8/imac-parallel.out S8/imac-parallel.err", "S8.final": "S8/imac-final.out S8/imac-final.err",
       "S8.rollback": "S8/imac-rollback.out S8/imac-rollback.err", "S8.refuse": "S8/bad-id.out S8/bad-id.err",
       "S11": "S11/bash-n.txt", "S12": "mba/S12.out mba/S12.err", "S13": "mba/S13-B.out mba/S13-B.err",
       "S14.MBA.held": "mba/S14/held.out mba/S14/held.err", "S14.iMac.held": "S14-imac/held.out S14-imac/held.err",
       "S14.MBA.nodir": "mba/S14/nodir.out mba/S14/nodir.err", "S14.iMac.nodir": "S14-imac/nodir.out S14-imac/nodir.err",
       "S14.MBA.timeout": "mba/S14/timeout.probe.rc mba/S14/timeout.probe.err",
       "S14.iMac.timeout": "S14-imac/timeout.probe.rc S14-imac/timeout.probe.err",
       "S15.MBA": "mba/S15/r1.out mba/S15/r1.err", "S15.iMac": "S15-imac/r1.out S15-imac/r1.err",
       "S15.MBA.45": "mba/S15/45a.out mba/S15/45a.err", "S15.iMac.45": "S15-imac/45a.out S15-imac/45a.err",
       "S15.MBA.bad": "mba/S15/bad-a.out mba/S15/bad-a.err", "S15.iMac.bad": "S15-imac/bad-a.out S15-imac/bad-a.err"}
RAW.update({"S0.bot": "S0/diff-base-new.txt", "S1.bot": "S1/c02.new.out", "S3": "mba/S3.out mba/S3.err",
            "S15.MBA.rf": "mba/S15/rf-a.out mba/S15/rf-a.err", "S15.iMac.rf": "S15-imac/rf-a.out S15-imac/rf-a.err",
            "S15.MBA.old": "mba/S15/old-a.out mba/S15/old-a.err", "S15.iMac.old": "S15-imac/old-a.out S15-imac/old-a.err"})
assert set(RAW) == set(FAIL)


def rawtext(i):
    if i not in RAW:
        return ""
    lines = []
    for p in RAW[i].split():
        try:
            lines += open(os.path.join(out, "raw", p), encoding="utf-8", errors="replace").read().splitlines()
        except OSError:
            lines.append("（没有 raw/%s）" % p)
    lines = [re.sub(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d SGT ", "", l) for l in lines if l.strip()]
    return " ⏎ ".join(lines[:2]) or "（%s 没有内容）" % "、".join("raw/" + p for p in RAW[i].split())


order = [r[0] for r in rows] + [i for i in list(FAIL) + PASS if i not in got]
tab = []
for i in order:
    want = "FAIL" if i in FAIL else "PASS" if i in PASS else "不在期望表里"
    act = got[i][1] if i in got else "没有这一项"
    same = "一致" if act == want else "不一致"
    if same == "一致" and i in WHY_RE and not re.search(WHY_RE[i], got[i][3]):
        same = "不一致（挂了，但原因对不上）"
    tab.append((i, want, act, same, FAIL.get(i, ""), got[i][3] if i in got else "", rawtext(i)))
bad = sum(t[3] != "一致" for t in tab)
with open(os.path.join(out, "rollback.tsv"), "w", encoding="utf-8") as f:
    f.write("编号\t回退后期望\t实际\t和期望\t为什么该挂\t演练的「实际」一栏\traw/ 里的输出原文\n")
    for t in tab:
        f.write("\t".join(t) + "\n")

cell = lambda s, n=0: ((s[:n] + "…") if n and len(s) > n else s).replace("|", "\\|").replace("`", "'")
d = json.load(open(os.path.join(out, "rollback", "defs-live.json"), encoding="utf-8"))
mba_pc = next(c for c in d["create"] if c["machine"] == "mba")["precheck"]
imac_pc = next(e for e in d["edit"] if e["stage"] == "parallel")["set"]["precheck"]
env = open(os.path.join(out, "env.txt"), encoding="utf-8").read().strip().splitlines()
tree = open(os.path.join(out, "rollback", "tree.txt"), encoding="utf-8").read().strip().splitlines()
nf = sum(t[1] == "FAIL" and t[2] == "FAIL" for t in tab)
np_ = sum(t[1] == "PASS" and t[2] == "PASS" for t in tab)
L = ["# B1 回退测试：旧代码（base %s）上跑同一套演练" % base[:7], "",
     "**结果：%d 项里 %d 项和期望一致，%d 项不一致。期望挂的 %d 项挂了 %d 项；期望过的 %d 项过了 %d 项。**"
     % (len(tab), len(tab) - bad, bad, len(FAIL), nf, len(PASS), np_), "",
     "把本 PR 的代码换回 base `%s`，用本分支 `%s` 的演练脚本和回放数据整轮跑 `wake/tests/heartbeat-watch-ssh.sh`。" % (base, head),
     "期望先写在 `automations/heartbeat-1021/FAILURE-MODES.md`「回退测试的期望」「回退测试的期望（第二轮）」「回退测试的期望（第五轮）」"
     "「回退测试的期望（第五轮补）」「回退测试的期望（第五轮补充）」「回退测试的期望（第六轮）」六节，再跑。第五轮新加的 7 项该挂的（S13、S14 的 held、nodir、timeout）"
     "和第五轮补充新加的 6 项该挂的（S15、S15 的 .45、.bad），还要在演练的「实际」一栏里对上挂的原因（回退脚本里的 `WHY_RE`），"
     "第六轮另有 7 项核对原因，共 20 项；对不上记「不一致（挂了，但原因对不上）」。这个文件由回退脚本生成。", "",
     "## 怎么重跑", "", "在 iMac 的仓库根目录：", "", "```bash", "wake/tests/heartbeat-watch-ssh-rollback.sh", "```", "",
     "要求和 `wake/tests/heartbeat-watch-ssh.sh` 一样。整个目录会被重写（有 `.hb-drill` 标记才清空）。", "",
     "## 旧代码怎么放回去", "",
     "- 在临时目录里 `git clone --shared` 本仓库，`checkout --detach` 到 base。base 里没有 `scripts/orca-via-ssh`、`scripts/lock-held-alert` 和 "
     "`automations/heartbeat-1021/register.sh`，`scripts/heartbeat-watch.sh` 是 base 那份。",
     "- 放进去的只有测试和定义：HEAD 的 `wake/tests/heartbeat-watch-ssh.sh`、`wake/tests/hb-replay/`，加一份现网版 "
     "`automations/heartbeat-1021/defs.json`（`rollback/defs-live.json`）。",
     "- 现网版 defs：MBA 那条的 precheck 是现网 box `94e4b0bc` 的原文 `%s`（environment `iMac`，不经 ssh）；`5c2d0575` 的并行版、"
     "最终版都是它的现网原文 `%s`。都没有 lockf 和 lock-held-alert（base 里也没有 `scripts/lock-held-alert`）。" % (mba_pc, imac_pc),
     "- 这个目录里的 `README.md`、`results.tsv`、`env.txt`、`raw/` 是演练脚本照常生成的：`env.txt` 的 commit 是 base，"
     "「未提交的改动」数的是上面放进去的文件。", "",
     "旧代码检出的情况（`rollback/tree.txt`）：", "", "```"] + tree + ["```", "",
     "## 这次运行", ""] + ["- " + cell(l) for l in env] + ["",
     "## 期望挂的 %d 项（本 PR 会改变结果）" % len(FAIL), "",
     "「raw/ 里的输出原文」：冒号前是 `raw/` 下的文件，冒号后是这些文件里不空的前两行（去掉开头的时间戳，⏎ 隔开）。", "",
     "| 编号 | 为什么该挂 | 实际 | 和期望 | raw/ 里的输出原文（截到 240 字） | 演练的「实际」一栏（截到 160 字；核对原因的 20 项截到 600 字） |",
     "|---|---|---|---|---|---|"]
L += ["| %s | %s | %s | %s | %s：%s | %s |" % (t[0], cell(t[4]), t[2], t[3], "、".join(RAW[t[0]].split()), cell(t[6], 240),
                                             cell(t[5], 600 if t[0] in WHY_RE else 160)) for t in tab if t[1] == "FAIL"]
L += ["", "## 期望过的 %d 项（本 PR 不改变结果，用来排除「是环境坏了才挂」）" % len(PASS), "",
      "| 编号 | 实际 | 和期望 | 实际原文（截到 200 字） |", "|---|---|---|---|"]
L += ["| %s | %s | %s | %s |" % (t[0], t[2], t[3], cell(t[5], 200)) for t in tab if t[1] == "PASS"]
other = [t for t in tab if t[1] not in ("FAIL", "PASS")]
if other:
    L += ["", "## 不在期望表里的", "", "| 编号 | 实际 | 实际原文 |", "|---|---|---|"]
    L += ["| %s | %s | %s |" % (t[0], t[2], cell(t[5], 200)) for t in other]
L += ["", "## 文件", "",
      "- `rollback.tsv`：每项一行：编号、回退后期望、实际、和期望一不一致、为什么该挂、演练的「实际」一栏、raw/ 里的输出原文。",
      "- `rollback/tree.txt`：旧代码检出的情况。`rollback/defs-live.json`：现网版 defs。`rollback/drill.log`：演练的屏幕输出。",
      "- `README.md`、`results.tsv`、`env.txt`、`raw/`：演练脚本在旧代码上生成的，格式同 `reports/heartbeat-mba-imac-1021/`。",
      "- `SHA256SUMS`：除它自己以外所有文件的 sha256（`shasum -a 256 -c SHA256SUMS` 校验）。", ""]
open(os.path.join(out, "ROLLBACK.md"), "w", encoding="utf-8").write("\n".join(L))
for t in tab:
    print("%-6s %-16s 期望 %-4s 实际 %-4s %s" % (t[3], t[0], t[1], t[2], (t[6] or t[5])[:120]))
print("回退测试：%d 项里 %d 项和期望一致，%d 项不一致" % (len(tab), len(tab) - bad, bad))
sys.exit(1 if bad else 0)
PY
rc=$?
(cd "$OUT" && find . -type f ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort | while IFS= read -r f; do shasum -a 256 "$f"; done >SHA256SUMS)
echo "产物：$OUT"
exit $rc
